"""Order-domain journal sync (DG-308 Phase 4.4, FR-ARCH-2).

Order revenue recognition, AR, tien-rut return, bus-shipping release,
cancellation, and the completed/delivered sync orchestrators, extracted from
the original monolithic ``journal_sync.py``.
"""

from typing import Optional

from baker.db.schema import (
    ACCOUNTS_RECEIVABLE_CODE,
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    REVENUE_UPDATE_TOLERANCE,
    TIEN_RUT_HELD_CODE,
    _account_id_by_code,
    _insert_journal_entry,
)
from baker.models.cash_drawer import CashDrawer
from baker.models.payment_transaction import PaymentTransaction
from baker.services.journal_sync._common import (
    _active_drawer_id,
    _delete_journal_entry_cascade,
    _find_journal_entry,
    _is_locked,
    _resolve_delivered_timestamp,
    _reverse_journal_entry,
    _table_exists,
    run_journal_sync,
)

# Owner's Cash (sub-account of 1100) — used by the shipping-release sync and
# repair when no open drawer covers the order's delivery timestamp (FR4).
# Mirrors the 1102 routing used elsewhere (api/cash_drawer.py, repair/_common).
OWNER_CASH_CODE = "1102"
from baker.services.journal_sync.payment import (
    _held_tien_rut_for_order,
    _resolve_transaction_asset_code,
)
from baker.services.journal_sync.waste import (
    _sync_order_cogs_entry,
    _sync_order_gift_cogs_entry,
)
from baker.utils.time import now_utc


_REVENUE_ENTRY_PREFIX = "Order revenue:"
_AR_ENTRY_PREFIX = "Order revenue (AR):"
_TIEN_RUT_RETURN_PREFIX = "Tien rut return:"

def _reconcile_order_revenue_entry(
    conn,
    order_id: int,
    order_ref: str,
    *,
    total_price: Optional[float] = None,
    respect_locks: bool = True,
) -> None:
    """Reconcile the ``source_type = 'order'`` journal entries for a delivered order.

    Single source of truth for revenue recognition — shared by the live sync
    (:func:`_sync_delivered_order_journal`) and the migration backfill
    (:func:`baker.db.schema._backfill_delivered_order_journal_entries`).

    Revenue rules (DG-198 reversal, FR3):
      - Paid orders (any deposits): create a **revenue entry** that debits
        Customer Deposits (2100) for the full deposit balance still held and
        credits Order Revenue (4100) for that same amount. Deposits only —
        tien_rut is NOT netted against deposits. ``deposit_balance =
        deposits_in − refund_total − shipping_held``.
      - Unpaid orders (zero deposits, zero outflows): debit Accounts Receivable
        (1500), credit Order Revenue (4100) for ``total_price`` (customer debt).
      - Negative or zero deposit balance with zero deposits (nothing held):
        no revenue entry is created (nothing to recognise).

    Tien rut return (DG-198 reversal, FR3): separately, when tien_rut is held
    in 2400 for the order, create a **tien rut return entry** that debits
    Tien Rut Held (2400) for the full held amount and credits the asset
    account (the same asset account as the original tien_rut payment method,
    defaulting to 1100 when the method cannot be determined). This returns the
    held cash to the customer at delivery. The two entries are separate so
    deposits→revenue and tien_rut→return are independent transactions.

    Bus shipping exclusion: when the order's ``delivery_type == 'bus'`` and
    ``shipping_fee > 0``, the recognised revenue is reduced by the shipping
    fee, since bus shipping is held separately in account 2200 and must never
    flow into revenue account 4100.

    Update handling: each entry (revenue, tien rut return) is looked up by its
    description prefix and compared against the expected amounts. When they
    differ by more than ``REVENUE_UPDATE_TOLERANCE`` the stale entry is removed
    and a corrected one is created.

    Lock handling (``respect_locks``):
      - ``True`` (default): locked stale entries are *reversed* rather than
        deleted, then a corrected entry is created below. Used by live sync.
      - ``False``: locked entries are deleted unconditionally. Intended for
        migration-only callers that pre-date lock semantics.

    The AR account is seeded idempotently via the chart-of-accounts seed; this
    helper resolves its id directly (review finding Mn-4).
    """
    revenue_account_id = _account_id_by_code(conn, ORDER_REVENUE_CODE)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    ar_account_id = _account_id_by_code(conn, ACCOUNTS_RECEIVABLE_CODE)
    tien_rut_account_id = _account_id_by_code(conn, TIEN_RUT_HELD_CODE)

    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee, total_price, due_date, created_at FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()

    # Deposit balance still held in 2100 at delivery. Inflows (deposit /
    # payment / full_payment) credit 2100, refunds debit 2100. tien_rut is a
    # deposit inflow but journals to 2400 (not 2100), so it must be SUBTRACTED
    # from deposits_in so the 2100 debit clears exactly the 2100 balance
    # (deposits only — tien_rut is returned separately). For bus orders the
    # shipping portion is split into 2200 at payment time, so it is also
    # subtracted here.
    deposits_in = float(PaymentTransaction.total_paid_excl_outflows(conn, order_id))
    tien_rut_total = float(PaymentTransaction.total_tien_rut(conn, order_id))
    refund_total = float(PaymentTransaction.total_outflows(conn, order_id))
    shipping_held = 0.0
    if order_row is not None:
        delivery_type = order_row["delivery_type"] or "pickup"
        shipping_fee = float(order_row["shipping_fee"] or 0)
        if delivery_type == "bus" and shipping_fee > 0:
            shipping_held = shipping_fee
    deposit_balance = max(0.0, deposits_in - tien_rut_total - refund_total - shipping_held)

    # Net revenue (4100 credit) = deposit balance. Deposits only — tien_rut is
    # returned separately and does not reduce revenue.
    revenue_amount = deposit_balance

    # Tien rut held in 2400 (credits at payment time minus debits at return).
    tien_rut_held = _held_tien_rut_for_order(conn, order_id)

    order_transaction_date = _resolve_delivered_timestamp(conn, order_id, order_ref) or now_utc()

    # --- Revenue entry (deposits → 4100) -----------------------------------
    _reconcile_revenue_entry_lines(
        conn,
        order_id=order_id,
        order_ref=order_ref,
        revenue_account_id=revenue_account_id,
        deposits_account_id=deposits_account_id,
        ar_account_id=ar_account_id,
        deposit_balance=deposit_balance,
        revenue_amount=revenue_amount,
        total_price=total_price,
        order_row=order_row,
        order_transaction_date=order_transaction_date,
        respect_locks=respect_locks,
        deposits_in=deposits_in,
        tien_rut_total=tien_rut_total,
    )

    # --- Tien rut return entry (2400 → Asset) ------------------------------
    _reconcile_tien_rut_return_entry(
        conn,
        order_id=order_id,
        order_ref=order_ref,
        tien_rut_account_id=tien_rut_account_id,
        tien_rut_held=tien_rut_held,
        order_transaction_date=order_transaction_date,
        respect_locks=respect_locks,
    )


# Description prefixes used to identify the two order journal entries.
_REVENUE_ENTRY_PREFIX = "Order revenue:"
_AR_ENTRY_PREFIX = "Order revenue (AR):"
_TIEN_RUT_RETURN_PREFIX = "Tien rut return:"

def _find_order_entry_by_prefix(conn, order_id: int, prefix: str) -> Optional[int]:
    """Return the id of the ``source_type='order'`` entry whose description
    starts with ``prefix``, or None."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order' AND source_id = ? AND description LIKE ? "
        "ORDER BY id DESC LIMIT 1",
        (order_id, prefix + "%"),
    ).fetchone()
    return int(row["id"]) if row else None

def _replace_order_entry(
    conn,
    existing_id: int,
    *,
    respect_locks: bool,
) -> None:
    """Reverse (locked) or delete (unlocked) a stale order journal entry."""
    if respect_locks and _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
    else:
        _delete_journal_entry_cascade(conn, existing_id)

def _sync_cancelled_order_journal(conn, order_id: int) -> None:
    """Reverse (locked) or delete (unlocked) accounting entries for a cancelled order.

    Handles revenue, COGS, gift COGS, and shipping release entries — internal
    accounting entries that can be auto-reversed on cancellation. Payment
    transaction entries are deliberately excluded: they represent real cash
    that requires a human decision (refund vs. manual invalidation).
    """
    entry_id = _find_order_entry_by_prefix(conn, order_id, _REVENUE_ENTRY_PREFIX)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_order_entry_by_prefix(conn, order_id, _AR_ENTRY_PREFIX)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_order_entry_by_prefix(conn, order_id, _TIEN_RUT_RETURN_PREFIX)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_journal_entry(conn, 'order_cogs', order_id)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    # DG-297 Phase 3 (FR5): reverse the promotional gift COGS entry the same way
    # as the main order_cogs entry — locked entries get a reversing entry,
    # unlocked entries are deleted (mirrors the order_cogs pattern above).
    entry_id = _find_journal_entry(conn, 'order_gift_cogs', order_id)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

    entry_id = _find_journal_entry(conn, 'order_shipping_release', order_id)
    if entry_id is not None:
        _replace_order_entry(conn, entry_id, respect_locks=True)

def _reconcile_revenue_entry_lines(
    conn,
    *,
    order_id: int,
    order_ref: str,
    revenue_account_id: int,
    deposits_account_id: int,
    ar_account_id: int,
    deposit_balance: float,
    revenue_amount: float,
    total_price: Optional[float],
    order_row,
    order_transaction_date,
    respect_locks: bool,
    deposits_in: float,
    tien_rut_total: float,
) -> None:
    """Create/update the deposits→revenue (or AR) ``source_type='order'`` entry.

    Looked up by the ``Order revenue:`` / ``Order revenue (AR):`` description
    prefix so it is distinguishable from the tien rut return entry (which
    shares the same source_type/source_id).
    """
    is_ar = deposit_balance <= 0 and (deposits_in - tien_rut_total) <= 0
    prefix = _AR_ENTRY_PREFIX if is_ar else _REVENUE_ENTRY_PREFIX
    existing_id = _find_order_entry_by_prefix(conn, order_id, prefix)

    if is_ar:
        # Truly unpaid (no deposits and no refunds): record the order total
        # as accounts receivable (customer debt). Bus shipping exclusion does
        # not apply here because there were no deposits to hold shipping in
        # 2200; the full order total remains a receivable. When total_price
        # is unknown the order row is read from the orders table to remain
        # backwards compatible with callers that omit it.
        if total_price is None:
            total_price = float(order_row["total_price"] or 0) if order_row else 0.0
        if total_price <= 0:
            return  # nothing to recognise
        expected_debit = float(total_price)
        expected_credit_4100 = float(total_price)
        if existing_id is not None:
            row = conn.execute(
                """
                SELECT
                  COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END), 0) AS debit_1500,
                  COALESCE(SUM(CASE WHEN a.code = ? THEN jl.credit ELSE 0 END), 0) AS credit_4100
                FROM journal_lines jl
                JOIN accounts a ON a.id = jl.account_id
                WHERE jl.journal_entry_id = ?
                """,
                (ACCOUNTS_RECEIVABLE_CODE, ORDER_REVENUE_CODE, existing_id),
            ).fetchone()
            mismatch = abs(float(row["debit_1500"]) - expected_debit) + abs(
                float(row["credit_4100"]) - expected_credit_4100
            )
            if mismatch <= REVENUE_UPDATE_TOLERANCE:
                return
            _replace_order_entry(conn, existing_id, respect_locks=respect_locks)
        _insert_journal_entry(
            conn,
            description=f"Order revenue (AR): {order_ref}",
            source_type="order",
            source_id=order_id,
            lines=[
                (ar_account_id, expected_debit, 0.0, "Phải thu khách hàng"),
                (revenue_account_id, 0.0, expected_credit_4100, "Doanh thu bán hàng"),
            ],
            transaction_date=order_transaction_date,
            drawer_id=_active_drawer_id(conn),
        )
        return

    # Clean up any stale AR entry left over from a prior delivery sync when
    # the order was unpaid but is now paid (e.g. payment arrived between
    # delivery and completion). Without this the AR entry persists alongside
    # the revenue entry, doubling 4100 credit and inflating AR debit.
    stale_ar_id = _find_order_entry_by_prefix(conn, order_id, _AR_ENTRY_PREFIX)
    if stale_ar_id is not None:
        _replace_order_entry(conn, stale_ar_id, respect_locks=respect_locks)

    # Paid: clear the full 2100 deposit balance to revenue (DR 2100, CR 4100).
    # Deposits only — tien_rut is returned separately. Lines with a zero amount
    # are omitted so double-entry integrity holds (DG-198 reversal, FR3).
    if deposit_balance <= 0:
        # deposit_balance <= 0 but deposits existed (nothing held, e.g. fully
        # refunded) → no revenue to recognise; remove any stale revenue entry.
        if existing_id is not None:
            _replace_order_entry(conn, existing_id, respect_locks=respect_locks)
        return

    if existing_id is not None:
        row = conn.execute(
            """
            SELECT
              COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END), 0) AS debit_2100,
              COALESCE(SUM(CASE WHEN a.code = ? THEN jl.credit ELSE 0 END), 0) AS credit_4100
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ?
            """,
            (CUSTOMER_DEPOSITS_CODE, ORDER_REVENUE_CODE, existing_id),
        ).fetchone()
        mismatch = abs(float(row["debit_2100"]) - deposit_balance) + abs(
            float(row["credit_4100"]) - revenue_amount
        )
        if mismatch <= REVENUE_UPDATE_TOLERANCE:
            return
        _replace_order_entry(conn, existing_id, respect_locks=respect_locks)

    lines: list[tuple[int, float, float, str]] = [
        (deposits_account_id, deposit_balance, 0.0, "Chuyển cọc sang doanh thu"),
    ]
    if revenue_amount > 0:
        lines.append(
            (revenue_account_id, 0.0, revenue_amount, "Doanh thu bán hàng")
        )
    _insert_journal_entry(
        conn,
        description=f"Order revenue: {order_ref}",
        source_type="order",
        source_id=order_id,
        lines=lines,
        transaction_date=order_transaction_date,
        drawer_id=_active_drawer_id(conn),
    )

def _resolve_tien_rut_return_asset_account(conn, order_id: int) -> int:
    """Resolve the asset account to credit for the tien rut return entry.

    Uses the same asset account as the original tien_rut payment method. When
    the order has multiple tien_rut transactions with different methods, the
    first one's method is used. Defaults to 1100 (Cash on Hand) when no
    tien_rut payment exists or the method is unknown.

    DG-244 Phase 4: when the first tien_rut transaction carries a
    ``payment_source``, the return credits the same bank sub-account the
    original deposit debited (so the held balance and its return net to zero
    on the same account).

    The ``payment_source`` column is optional on legacy schemas (added by
    migration v76). When absent we fall back to the pre-Phase-4 method-based
    resolution so historical migration callables (v44 backfill) still work on
    pre-v76 databases.
    """
    from baker.models.payment_transaction import _invalidation_filter

    invalidation = _invalidation_filter(conn)
    # Detect the payment_source column once; v44 backfill runs before v76 has
    # added it, so a bare SELECT pt.payment_source would raise OperationalError.
    has_payment_source_col = bool(conn.execute(
        "SELECT 1 FROM pragma_table_info('payment_transactions') "
        "WHERE name = 'payment_source'"
    ).fetchone())
    source_expr = "pt.payment_source" if has_payment_source_col else "''"
    row = conn.execute(
        f"""
        SELECT pt.method AS method, {source_expr} AS payment_source
        FROM payment_transactions pt
        WHERE pt.order_id = ? AND pt.type = 'tien_rut'
          {invalidation}
        ORDER BY pt.id ASC LIMIT 1
        """,
        (order_id,),
    ).fetchone()
    method = row["method"] if row else "cash"
    payment_source = (row["payment_source"] if row else "") or ""
    asset_code = _resolve_transaction_asset_code(method, payment_source)
    return _account_id_by_code(conn, asset_code)

def _reconcile_tien_rut_return_entry(
    conn,
    *,
    order_id: int,
    order_ref: str,
    tien_rut_account_id: int,
    tien_rut_held: float,
    order_transaction_date,
    respect_locks: bool,
) -> None:
    """Create/update the tien rut return ``source_type='order'`` entry.

    At delivery the full tien_rut held in 2400 is returned to the customer:
    DR 2400 (Tien Rut Held), CR Asset (cash returned). Looked up by the
    ``Tien rut return:`` description prefix so it is distinguishable from the
    revenue entry (which shares the same source_type/source_id).

    When ``tien_rut_held <= 0`` any existing return entry is removed (the
    holding has already been cleared or was reversed).
    """
    existing_id = _find_order_entry_by_prefix(conn, order_id, _TIEN_RUT_RETURN_PREFIX)

    if tien_rut_held <= 0:
        if existing_id is not None:
            _replace_order_entry(conn, existing_id, respect_locks=respect_locks)
        return

    asset_account_id = _resolve_tien_rut_return_asset_account(conn, order_id)

    if existing_id is not None:
        row = conn.execute(
            """
            SELECT
              COALESCE(SUM(CASE WHEN a.code = ? THEN jl.debit ELSE 0 END), 0) AS debit_2400,
              COALESCE(SUM(CASE WHEN a.code IN ('1100','1101','1102','1200','1210','1220','1290') THEN jl.credit ELSE 0 END), 0) AS credit_asset
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ?
            """,
            (TIEN_RUT_HELD_CODE, existing_id),
        ).fetchone()
        mismatch = abs(float(row["debit_2400"]) - tien_rut_held) + abs(
            float(row["credit_asset"]) - tien_rut_held
        )
        if mismatch <= REVENUE_UPDATE_TOLERANCE:
            return
        _replace_order_entry(conn, existing_id, respect_locks=respect_locks)

    _insert_journal_entry(
        conn,
        description=f"Tien rut return: {order_ref}",
        source_type="order",
        source_id=order_id,
        lines=[
            (tien_rut_account_id, tien_rut_held, 0.0, "Trả tiền rút cho khách"),
            (asset_account_id, 0.0, tien_rut_held, "Tiền rút đã trả"),
        ],
        transaction_date=order_transaction_date,
        drawer_id=_active_drawer_id(conn),
    )

def _resolve_shipping_release_asset_account(
    conn, order_id: int, order_ref: str
) -> tuple[str, int | None]:
    """Return ``(asset_code, drawer_id)`` for the shipping release credit.

    Drawer-aware account selection (FR3/FR4), shared by the live sync
    (:func:`_sync_bus_shipping_release_entry`) and the repair command
    (:func:`baker.commands.repair.order_revenue._process_shipping_release_order`)
    so both code paths produce identical journal entries.

      - If an open drawer exists and the order's delivery timestamp is at or
        after the drawer's ``opened_at``, credit 1101 (Cash in Drawer) and
        link the entry to that drawer.
      - Otherwise (no open drawer, or delivery predates the open drawer),
        credit 1102 (Owner's Cash) with no drawer link.
    """
    drawer = CashDrawer.get_active(conn) if _table_exists(conn, "cash_drawer") else None
    if drawer is not None:
        delivery_ts = _resolve_delivered_timestamp(conn, order_id, order_ref)
        if delivery_ts is not None and delivery_ts >= drawer.opened_at:
            return PAYMENT_METHOD_TO_ASSET_CODE.get("cash", "1101"), drawer.id
    return OWNER_CASH_CODE, None

def _sync_bus_shipping_release_entry(
    conn, order_id: int, order_ref: str
) -> None:
    """Create the shipping release entry for a delivered bus order (FR4).

    Bus orders hold the shipping fee in account 2200 at payment time (see
    :func:`_build_payment_journal_lines`). At delivery the held shipping is
    released to the cash asset account (1100): debit 2200, credit 1100.

    Behaviour:
      - Non-bus orders or ``shipping_fee <= 0``: no-op.
      - The release amount is always the full ``shipping_fee`` (DG-366 Phase 1,
        FR1): the previous ``min(shipping_fee, held_in_2200)`` gate is removed
        so the release is created even when no payment has been recorded yet.
        The 2200 account may temporarily go negative until a payment credits
        it; this is the intended accounting (shop paid the driver from the
        drawer, the customer owes the shipping).
      - Idempotent: when an existing ``order_shipping_release`` entry matches
        the expected release amount (within tolerance), it is left untouched.
      - Lock semantics (FR6): a locked stale entry is *reversed* then a
        corrected entry is created; an unlocked stale entry is *deleted* and
        recreated.
    """
    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee, due_date, created_at FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()
    if order_row is None:
        return
    delivery_type = order_row["delivery_type"] or "pickup"
    shipping_fee = float(order_row["shipping_fee"] or 0)
    if delivery_type != "bus" or shipping_fee <= 0:
        return

    release_amount = shipping_fee

    bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)
    asset_code, drawer_id = _resolve_shipping_release_asset_account(
        conn, order_id, order_ref
    )
    asset_account_id = _account_id_by_code(conn, asset_code)
    description = f"Shipping release: {order_ref}"
    order_transaction_date = _resolve_delivered_timestamp(conn, order_id, order_ref) or now_utc()

    existing_id = _find_journal_entry(
        conn, "order_shipping_release", order_id
    )
    if existing_id is not None:
        # Compare the existing entry's 2200 debit against release_amount.
        row = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit), 0) AS debit_2200
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = ?
            """,
            (existing_id, BUS_SHIPPING_HELD_CODE),
        ).fetchone()
        current_debit = float(row["debit_2200"]) if row else 0.0
        if abs(current_debit - release_amount) <= REVENUE_UPDATE_TOLERANCE:
            # Already in sync — idempotent no-op.
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)

    _insert_journal_entry(
        conn,
        description=description,
        source_type="order_shipping_release",
        source_id=order_id,
        lines=[
            (bus_shipping_account_id, release_amount, 0.0, "Thanh toán ship bus"),
            (asset_account_id, 0.0, release_amount, "Tiền ship bus đã trả"),
        ],
        transaction_date=order_transaction_date,
        drawer_id=drawer_id,
    )

def _sync_completed_order_journal(conn, order_id: int, order_ref: str) -> None:
    """Reconcile revenue journal entries when an order transitions to "completed".

    DG-269 Phase 2. Mirrors the revenue portion of
    :func:`_sync_delivered_order_journal` but is triggered on the
    delivered→completed (or bypassed-delivery→completed) transition. Delegates
    to :func:`_reconcile_order_revenue_entry`, which already:

      - Queries **all** non-invalidated payment transactions for the order
        (full deposit context, not just delivery-time deposits) — so deposits
        recorded between delivery and completion are reflected.
      - Detects pre-existing ``source_type='order'`` revenue / AR entries via
        their description prefix and reconciles them **within the 0.005 VND
        tolerance** (FR2/NFR4 idempotency):
          * matching amounts → no-op (AC3a),
          * stale amounts → update-in-place / reverse-and-recreate (AC3b),
          * no prior entries (bypassed delivery) → create fresh (AC3c).
      - Handles all payment scenarios (paid deposits, partial paid, AR,
        multi-payment, bus/shipping fee split, tien rut) — same code path as
        delivery sync (FR6).
      - Respects lock semantics (``respect_locks=True``): locked stale entries
        are reversed, not deleted.

    COGS is handled here via :func:`_sync_order_cogs_entry` so orders that
    bypassed "delivered" still get the ``order_cogs`` journal entry
    (DR 5900 / CR 1300) at completion time (DG-276). The call is idempotent —
    an order that already has an ``order_cogs`` entry (e.g. from a prior
    delivery sync on the delivered→completed path) is left untouched (FR2).

    Bus-shipping release entries (2200 → 1100) are created here via
    :func:`_sync_bus_shipping_release_entry` so orders that bypassed
    "delivered" still get the ``order_shipping_release`` entry at completion
    (DG-356). The call is idempotent and a no-op for non-bus orders or
    ``shipping_fee <= 0``.

    Fire-and-forget error handling is provided by the caller wrapping this in
    :func:`run_journal_sync` with ``source_type="order"`` (FR5) — a COGS sync
    failure never blocks the completion transition (FR3).
    """
    _reconcile_order_revenue_entry(conn, order_id, order_ref, respect_locks=True)

    # Release the held bus shipping (2200 → 1100) at completion for orders
    # that bypassed "delivered" (DG-356). Wrapped in the shared non-blocking
    # wrapper so accounting failures never block the primary business
    # operation (NFR1) and are observable via the ``journal_sync_failures``
    # counter — mirrors the delivery-time pattern at lines 599-603.
    run_journal_sync(
        _sync_bus_shipping_release_entry,
        conn, order_id, order_ref,
        log_label=f"bus shipping release sync for order {order_id} ({order_ref})",
        source_type="order_shipping_release",
        source_id=order_id,
    )

    _sync_order_cogs_entry(conn, order_id, order_ref)
    _sync_order_gift_cogs_entry(conn, order_id, order_ref)

def _sync_delivered_order_journal(conn, order_id: int, order_ref: str) -> None:
    """Create/update revenue conversion + COGS journal entries for a delivered/completed order.

    Revenue recognition is delegated to :func:`_reconcile_order_revenue_entry`
    (see its docstring for the paid/unpaid/refund-drained rules). This wrapper
    then handles COGS.

    COGS: one entry per order summing cost_at_sale*qty for items with a
    resolved cost > 0. cost_at_sale is populated at delivery time from
    cost_history (via resolve_product_cost), applying the documented baseline
    fallback when no historical cost is in effect. Sold extras
    (is_extra=1, is_gift=0) are included with per-item DR 5900/CR 1300 lines
    (DG-297 Phase 2, FR1/FR2). Gifted items (is_gift=1) get a separate
    ``order_gift_cogs`` entry with per-item DR 5910/CR 1300 lines (FR3).
    """
    _reconcile_order_revenue_entry(conn, order_id, order_ref, respect_locks=True)

    # Release the held bus shipping (2200 → 1100) at delivery (FR4). Wrapped in
    # the shared non-blocking wrapper so accounting failures never block the
    # primary business operation (NFR1) and are observable via the
    # ``journal_sync_failures`` counter (review finding OPS-1).
    run_journal_sync(
        _sync_bus_shipping_release_entry,
        conn, order_id, order_ref,
        log_label=f"bus shipping release sync for order {order_id} ({order_ref})",
        source_type="order_shipping_release",
        source_id=order_id,
    )

    _sync_order_cogs_entry(conn, order_id, order_ref)
    _sync_order_gift_cogs_entry(conn, order_id, order_ref)
