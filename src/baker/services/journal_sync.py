"""Journal auto-generation sync helpers.

These helpers create/update/delete double-entry journal entries for the
primary financial transactions (expenses, payments, order delivery, waste).
They are consumed by the events, payment_transactions, orders, reconciliations,
and stock routers so that every financial transaction automatically produces
a matching journal entry.

Accounting failures must never block the primary business operation: callers
wrap each ``_sync_*`` call in try/except with ``logger.exception``.
"""

import logging
from typing import Any, Optional

from baker.db.schema import (
    ACCOUNTS_RECEIVABLE_CODE,
    BUS_SHIPPING_HELD_CODE,
    COGS_CODE,
    CUSTOMER_DEPOSITS_CODE,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE,
    INVENTORY_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    ORDER_REVENUE_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    PAYMENT_OUTFLOW_TYPES,
    REVENUE_UPDATE_TOLERANCE,
    _account_id_by_code,
    _ensure_staff_payable_sub_account,
    _insert_journal_entry,
)
from baker.models.journal_entry import JournalEntry, JournalLine
from baker.models.payment_transaction import PaymentTransaction
from baker.services.cost_resolver import resolve_product_cost

logger = logging.getLogger("baker.server")

STAFF_ADVANCE_PAYMENT_SOURCE = "Nhân viên ứng trước"

# Backwards-compatible alias kept so any external import of the legacy name
# continues to resolve to the centralized constant in ``baker.db.schema``.
_REVENUE_UPDATE_TOLERANCE = REVENUE_UPDATE_TOLERANCE


def _find_journal_entry(conn, source_type: str, source_id: int) -> Optional[int]:
    """Return the journal_entries.id for the given source, or None."""
    row = conn.execute(
        "SELECT id, locked_at FROM journal_entries "
        "WHERE source_type = ? AND source_id = ? ORDER BY id DESC LIMIT 1",
        (source_type, source_id),
    ).fetchone()
    if row is None:
        return None
    return int(row["id"])


def _is_locked(conn, entry_id: int) -> bool:
    row = conn.execute(
        "SELECT locked_at FROM journal_entries WHERE id = ?", (entry_id,)
    ).fetchone()
    return bool(row and row["locked_at"])


def _delete_journal_entry_cascade(conn, entry_id: int) -> None:
    """Delete a journal entry and its lines (CASCADE handled by DB, but be explicit)."""
    conn.execute("DELETE FROM journal_lines WHERE journal_entry_id = ?", (entry_id,))
    conn.execute("DELETE FROM journal_entries WHERE id = ?", (entry_id,))


def _reverse_journal_entry(conn, entry_id: int) -> Optional[int]:
    """Create a reversal entry that swaps debit/credit of the original entry.

    Returns the new reversal entry id, or None if the original has no lines.
    """
    orig = conn.execute(
        "SELECT description, source_type, source_id, transaction_date "
        "FROM journal_entries WHERE id = ?",
        (entry_id,),
    ).fetchone()
    if orig is None:
        return None
    lines = JournalLine.list_for_entry(conn, entry_id)
    if not lines:
        return None
    reversed_lines = [
        (line.account_id, float(line.credit), float(line.debit), line.description or "")
        for line in lines
    ]
    # FR12: the reversal preserves the original entry's transaction_date so
    # the correction relates to the same period as the entry being reversed.
    orig_transaction_date = orig["transaction_date"] if "transaction_date" in orig.keys() else None
    return _insert_journal_entry(
        conn,
        description=f"Reversal: {orig['description']}",
        source_type=orig["source_type"],
        source_id=orig["source_id"],
        lines=reversed_lines,
        transaction_date=orig_transaction_date,
    )


def _update_journal_entry_in_place(
    conn, entry_id: int, *, description: str, lines: list[tuple[int, float, float, str]]
) -> None:
    """Replace the lines of an unlocked journal entry with the given lines."""
    conn.execute("DELETE FROM journal_lines WHERE journal_entry_id = ?", (entry_id,))
    for account_id, debit, credit, line_desc in lines:
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, account_id, float(debit), float(credit), line_desc),
        )
    conn.execute(
        "UPDATE journal_entries SET description = ? WHERE id = ?",
        (description, entry_id),
    )


def _build_expense_journal_lines(
    conn, data: dict[str, Any], summary: str
) -> Optional[tuple[str, list[tuple[int, float, float, str]]]]:
    """Build (description, lines) for an expense event's journal entry.

    Returns None when the expense data is incomplete/unsupported (silently skip).
    """
    amount = data.get("amount_vnd")
    category = data.get("category")
    payment_source = data.get("payment_source")
    if not isinstance(amount, (int, float)) or amount <= 0:
        return None
    if not isinstance(category, str) or not category:
        return None
    if not isinstance(payment_source, str) or not payment_source:
        return None

    expense_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)
    if not expense_code:
        return None

    if payment_source == STAFF_ADVANCE_PAYMENT_SOURCE:
        staff_name = (data.get("paid_by_name") or "").strip()
        if not staff_name:
            return None
        payment_account_id = _ensure_staff_payable_sub_account(conn, staff_name)
    else:
        account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
        if not account_code:
            return None
        payment_account_id = _account_id_by_code(conn, account_code)

    amount_f = float(amount)
    description = f"Expense: {summary}"

    if category in INVENTORY_PURCHASE_CATEGORIES:
        inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
        lines = [
            (inventory_account_id, amount_f, 0.0, "Nhập kho nguyên vật liệu"),
            (payment_account_id, 0.0, amount_f, "Thanh toán"),
        ]
    else:
        expense_account_id = _account_id_by_code(conn, expense_code)
        lines = [
            (expense_account_id, amount_f, 0.0, "Chi phí"),
            (payment_account_id, 0.0, amount_f, "Thanh toán"),
        ]
    return description, lines


def _sync_expense_journal(
    conn,
    event_id: int,
    data: dict[str, Any],
    summary: str,
    *,
    deleted: bool = False,
) -> None:
    """Create/update/delete the journal entry for an expense event.

    Wrap in try/except by the caller — accounting must never break expense CRUD.
    """
    existing_id = _find_journal_entry(conn, "expense", event_id)

    if deleted:
        if existing_id is None:
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        return

    built = _build_expense_journal_lines(conn, data, summary)
    if built is None:
        # Cannot build new lines; if an existing entry exists and is unlocked,
        # it is now stale — delete it in place.
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        return
    description, lines = built

    # FR4: the expense event's `timestamp` is the business event date.
    event_row = conn.execute(
        "SELECT timestamp FROM events WHERE id = ?", (event_id,)
    ).fetchone()
    transaction_date = event_row["timestamp"] if event_row else None

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense",
            source_id=event_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    elif _is_locked(conn, existing_id):
        # Locked: reverse the original, then create a new correct entry.
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense",
            source_id=event_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )


def _bus_shipping_allocation_for_order(
    conn, order_id: int
) -> tuple[str, float]:
    """Return ``(delivery_type, shipping_fee)`` for the order, or ``("pickup", 0)``.

    Reads the orders table directly so callers do not need to pass the values.
    """
    row = conn.execute(
        "SELECT delivery_type, shipping_fee FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()
    if row is None:
        return "pickup", 0.0
    return (row["delivery_type"] or "pickup"), float(row["shipping_fee"] or 0)


def _held_shipping_for_order(
    conn, order_id: int, *, exclude_txn_id: Optional[int] = None
) -> float:
    """Return the net shipping already held in 2200 for the order.

    Sums 2200 credits (held) minus 2200 debits (released) across all journal
    entries that credit 2200 for this order's shipping. Two source types can
    place shipping into 2200:

    - ``payment_transaction`` entries (Phase 2 payment-time split): the
      shipping portion of a deposit payment credits 2200.
    - ``order_shipping_hold`` entries (Phase 5 backfill): the one-time
      migration moves the shipping portion from 2100 to 2200 for delivered
      bus orders that pre-date the payment split.

    When ``exclude_txn_id`` is given, that transaction's journal entry is
    excluded from the sum — used on the update path so the current
    transaction's stale entry does not skew the allocation. The exclude
    clause only applies to ``payment_transaction`` entries (where
    ``source_id`` is a transaction id); ``order_shipping_hold`` entries are
    never excluded because their ``source_id`` is the order id.
    """
    exclude_clause = ""
    tx_params: list = [order_id]
    if exclude_txn_id is not None:
        exclude_clause = " AND je.source_id != ?"
        tx_params.append(exclude_txn_id)
    # Params: payment_transactions.order_id, [exclude_txn_id], hold source_id,
    # then the account code (shared by both branches via a.code = ?).
    row = conn.execute(
        f"""
        SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS net_held
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = ?
          AND (
                ( je.source_type = 'payment_transaction'
                    AND je.source_id IN (
                        SELECT id FROM payment_transactions WHERE order_id = ?
                    )
                    {exclude_clause}
                )
             OR
                ( je.source_type = 'order_shipping_hold'
                    AND je.source_id = ?
                )
              )
        """,
        [BUS_SHIPPING_HELD_CODE] + tx_params + [order_id],
    ).fetchone()
    return float(row["net_held"] or 0)


def _build_payment_journal_lines(
    conn,
    amount: float,
    ptype: str,
    method: str,
    *,
    order_id: Optional[int] = None,
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
    exclude_txn_id: Optional[int] = None,
) -> tuple[str, list[tuple[int, float, float, str]]]:
    """Build (description, lines) for a payment_transaction's journal entry.

    Bus orders (``delivery_type == 'bus'``) with ``shipping_fee > 0`` split the
    inflow credit between Customer Deposits (2100) and Bus Shipping Held (2200).
    The shipping portion is allocated to 2200 only up to the order's
    ``shipping_fee`` across all payments (first payments cover shipping; later
    payments go entirely to 2100). ``exclude_txn_id`` is used on the update
    path so the current transaction's stale entry does not skew the allocation.

    Outflow transactions (refund/tien_rut) are NOT split in Phase 2 — the
    2200 release at refund time is deferred to Phase 3 (revenue exclusion +
    shipping release). Outflows use the standard reverse lines (debit
    Customer Deposits, credit Asset) so the held shipping balance in 2200 is
    preserved until the delivery release entry handles it.

    Non-bus orders and bus orders with no shipping_fee behave exactly as before.
    """
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(method or "cash", "1100")
    asset_account_id = _account_id_by_code(conn, asset_code)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    amount_f = float(amount)
    ptype = ptype or "deposit"

    # Determine the shipping portion to allocate to 2200 for this inflow payment.
    shipping_portion = 0.0
    is_bus = delivery_type == "bus"
    if is_bus and shipping_fee > 0 and order_id is not None:
        already_held = _held_shipping_for_order(
            conn, order_id, exclude_txn_id=exclude_txn_id
        )
        remaining_shipping = max(0.0, shipping_fee - already_held)
        shipping_portion = min(amount_f, remaining_shipping)

    if ptype in PAYMENT_OUTFLOW_TYPES:
        # Cash flows back to customer. Phase 2 does NOT split outflows — the
        # 2200 release is deferred to Phase 3 (delivery shipping release).
        # Standard reverse lines: debit Customer Deposits, credit Asset.
        lines = [
            (deposits_account_id, amount_f, 0.0, "Hoàn tiền khách"),
            (asset_account_id, 0.0, amount_f, "Trả lại tiền"),
        ]
        description = f"Payment: {ptype} {amount_f}"
        return description, lines

    # Inflow: customer pays in. Debit Asset, credit Customer Deposits (+ 2200
    # for the bus shipping portion).
    if shipping_portion > 0:
        bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)
        deposit_portion = amount_f - shipping_portion
        lines = [
            (asset_account_id, amount_f, 0.0, "Tiền khách đặt/cọc"),
            (deposits_account_id, 0.0, deposit_portion, "Tiền khách đặt cọc"),
            (bus_shipping_account_id, 0.0, shipping_portion, "Tiền ship bus giữ hộ"),
        ]
        description = f"Payment: {ptype} {amount_f} (bus shipping split)"
        return description, lines
    # Default inflow (no shipping split)
    lines = [
        (asset_account_id, amount_f, 0.0, "Tiền khách đặt/cọc"),
        (deposits_account_id, 0.0, amount_f, "Tiền khách đặt cọc"),
    ]
    description = f"Payment: {ptype} {amount_f}"
    return description, lines


def _sync_payment_journal(
    conn,
    txn_id: int,
    amount: float,
    ptype: str,
    method: str,
    *,
    order_id: Optional[int] = None,
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
    deleted: bool = False,
) -> None:
    """Create/update/delete the journal entry for a payment_transaction.

    When ``order_id`` is provided, the order's ``delivery_type`` and
    ``shipping_fee`` are read from the orders table unless explicitly
    overridden by the ``delivery_type`` / ``shipping_fee`` keyword arguments.
    Bus orders with shipping split the credit between 2100 and 2200 (see
    :func:`_build_payment_journal_lines`).
    """
    # Resolve order context from the orders table when only order_id is given.
    if order_id is not None and (not delivery_type or delivery_type == "pickup") and shipping_fee == 0.0:
        d_type, s_fee = _bus_shipping_allocation_for_order(conn, order_id)
        delivery_type = d_type
        shipping_fee = s_fee

    existing_id = _find_journal_entry(conn, "payment_transaction", txn_id)

    if deleted:
        if existing_id is None:
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        return

    if not isinstance(amount, (int, float)) or float(amount) <= 0:
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        return

    # FR4: the payment transaction's `created_at` is the business event date.
    txn_row = conn.execute(
        "SELECT created_at FROM payment_transactions WHERE id = ?", (txn_id,)
    ).fetchone()
    transaction_date = txn_row["created_at"] if txn_row else None

    description, lines = _build_payment_journal_lines(
        conn,
        amount,
        ptype,
        method,
        order_id=order_id,
        delivery_type=delivery_type,
        shipping_fee=shipping_fee,
        exclude_txn_id=txn_id if existing_id is not None else None,
    )

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    elif _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
            transaction_date=transaction_date,
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )


def _reconcile_order_revenue_entry(
    conn,
    order_id: int,
    order_ref: str,
    *,
    total_price: Optional[float] = None,
    respect_locks: bool = True,
) -> None:
    """Reconcile the ``source_type = 'order'`` revenue entry for a delivered order.

    Single source of truth for revenue recognition — shared by the live sync
    (:func:`_sync_delivered_order_journal`) and the migration backfill
    (:func:`baker.db.schema._backfill_delivered_order_journal_entries`).

    Revenue rules:
      - Paid orders (net deposits > 0): debit Customer Deposits (2100), credit
        Order Revenue (4100) for net payments (deposits − tien_rut refunds).
      - Unpaid orders (zero net deposits): debit Accounts Receivable (1500),
        credit Order Revenue (4100) for ``total_price`` (customer debt). Only
        applied when the order had no deposits and no refunds.
      - Net deposits <= 0 with prior deposits (refunds drained them): no entry.

    Bus shipping exclusion (FR3): when the order's ``delivery_type == 'bus'``
    and ``shipping_fee > 0``, the recognized revenue is reduced by the
    shipping fee, since bus shipping is held separately in account 2200 and
    must never flow into revenue account 4100. The revenue amount becomes
    ``max(0.0, net_deposits − shipping_fee)``. Non-bus orders and bus orders
    with ``shipping_fee == 0`` are unchanged.

    Update handling: if a revenue entry already exists, its 2100 debit is
    compared against the current revenue amount (net deposits minus any
    applicable shipping fee). When they differ by more than
    ``REVENUE_UPDATE_TOLERANCE`` the stale entry is removed and a corrected
    one is created.

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

    existing = conn.execute(
        "SELECT id FROM journal_entries WHERE source_type = 'order' AND source_id = ?",
        (order_id,),
    ).fetchone()
    net = PaymentTransaction.total_paid_net(conn, order_id)

    # Bus shipping exclusion (FR3): shipping fees held in 2200 are not revenue.
    # Reduce the recognized revenue amount by shipping_fee for bus orders.
    order_row = conn.execute(
        "SELECT delivery_type, shipping_fee, total_price, due_date, created_at FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()
    revenue_amount = float(net)
    if order_row is not None:
        delivery_type = order_row["delivery_type"] or "pickup"
        shipping_fee = float(order_row["shipping_fee"] or 0)
        if delivery_type == "bus" and shipping_fee > 0:
            revenue_amount = max(0.0, revenue_amount - shipping_fee)

    if existing:
        existing_id = int(existing["id"])
        # Compare the existing entry's 2100 debit against the current revenue
        # amount (which excludes bus shipping fees when applicable).
        row = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit), 0) AS debit_2100
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = ?
            """,
            (existing_id, CUSTOMER_DEPOSITS_CODE),
        ).fetchone()
        current_debit = float(row["debit_2100"]) if row else 0.0
        mismatch = abs(current_debit - max(revenue_amount, 0.0))
        if mismatch <= REVENUE_UPDATE_TOLERANCE:
            # Entry already matches the expected revenue amount — leave it.
            return
        if respect_locks and _is_locked(conn, existing_id):
            # Locked: cannot delete. Reverse the stale entry, then create a
            # corrected one below.
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)

    # FR4/FR11: order revenue uses the order's due_date (fallback created_at)
    # as the business event date.
    order_transaction_date = None
    if order_row is not None:
        order_transaction_date = order_row["due_date"] or order_row["created_at"] or None

    if revenue_amount > 0:
        # Paid: move net deposits (minus bus shipping) to revenue
        _insert_journal_entry(
            conn,
            description=f"Order revenue: {order_ref}",
            source_type="order",
            source_id=order_id,
            lines=[
                (deposits_account_id, revenue_amount, 0.0, "Chuyển cọc sang doanh thu"),
                (revenue_account_id, 0.0, revenue_amount, "Doanh thu bán hàng"),
            ],
            transaction_date=order_transaction_date,
        )
    else:
        # Truly unpaid (no deposits and no refunds): record the order total
        # as accounts receivable (customer debt). Bus shipping exclusion does
        # not apply here because there were no deposits to hold shipping in
        # 2200; the full order total remains a receivable. When total_price
        # is unknown the order row is read from the orders table to remain
        # backwards compatible with callers that omit it.
        if PaymentTransaction.total_paid_excl_outflows(conn, order_id) <= 0:
            if total_price is None:
                total_price = float(order_row["total_price"] or 0) if order_row else 0.0
            if total_price > 0:
                _insert_journal_entry(
                    conn,
                    description=f"Order revenue (AR): {order_ref}",
                    source_type="order",
                    source_id=order_id,
                    lines=[
                        (ar_account_id, float(total_price), 0.0, "Phải thu khách hàng"),
                        (revenue_account_id, 0.0, float(total_price), "Doanh thu bán hàng"),
                    ],
                    transaction_date=order_transaction_date,
                )
        # else: net <= 0 but deposits existed (refunds drained them) → no
        # revenue to recognize; skip creating any entry.


def _sync_bus_shipping_release_entry(
    conn, order_id: int, order_ref: str
) -> None:
    """Create the shipping release entry for a delivered bus order (FR4).

    Bus orders hold the shipping fee in account 2200 at payment time (see
    :func:`_build_payment_journal_lines`). At delivery the held shipping is
    released to the cash asset account (1100): debit 2200, credit 1100.

    Behaviour:
      - Non-bus orders or ``shipping_fee <= 0``: no-op.
      - The release amount is ``min(shipping_fee, held_in_2200)`` so the
        entry never releases more than was actually held.
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

    held_in_2200 = _held_shipping_for_order(conn, order_id)
    release_amount = min(shipping_fee, held_in_2200)
    if release_amount <= 0:
        return

    bus_shipping_account_id = _account_id_by_code(conn, BUS_SHIPPING_HELD_CODE)
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get("cash", "1100")
    asset_account_id = _account_id_by_code(conn, asset_code)
    description = f"Shipping release: {order_ref}"
    # FR4/FR11: shipping release uses the order's due_date (fallback created_at).
    order_transaction_date = order_row["due_date"] or order_row["created_at"] or None

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
    )


def _sync_delivered_order_journal(conn, order_id: int, order_ref: str) -> None:
    """Create/update revenue conversion + COGS journal entries for a delivered/completed order.

    Revenue recognition is delegated to :func:`_reconcile_order_revenue_entry`
    (see its docstring for the paid/unpaid/refund-drained rules). This wrapper
    then handles COGS.

    COGS: one entry per order summing cost_at_sale*qty for items with a
    resolved cost > 0. cost_at_sale is populated at delivery time from
    cost_history (via resolve_product_cost), applying the documented baseline
    fallback when no historical cost is in effect.
    """
    _reconcile_order_revenue_entry(conn, order_id, order_ref, respect_locks=True)

    # Release the held bus shipping (2200 → 1100) at delivery (FR4). Wrapped in
    # try/except so accounting failures never block the primary business
    # operation (NFR1).
    try:
        _sync_bus_shipping_release_entry(conn, order_id, order_ref)
    except Exception:
        logger.exception(
            "Failed to sync bus shipping release entry for order %s (%s)",
            order_id,
            order_ref,
        )

    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    # FR4/FR11: order COGS uses the order's due_date (fallback created_at).
    order_date_row = conn.execute(
        "SELECT due_date, created_at FROM orders WHERE id = ?", (order_id,)
    ).fetchone()
    order_transaction_date = (
        order_date_row["due_date"] or order_date_row["created_at"] or None
        if order_date_row else None
    )
    # COGS: one entry per order summing cost_at_sale*qty for items with a
    # resolved cost > 0. cost_at_sale is populated at delivery time from
    # cost_history (via resolve_product_cost), applying the documented baseline
    # fallback when no historical cost is in effect.
    existing_cogs = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'order_cogs' AND source_id = ?",
        (order_id,),
    ).fetchone()
    if existing_cogs:
        return
    items = conn.execute(
        "SELECT oi.id AS item_id, oi.product_id, oi.quantity, oi.cost_at_sale "
        "FROM order_items oi "
        "WHERE oi.order_id = ? AND oi.is_extra = 0 AND oi.is_gift = 0",
        (order_id,),
    ).fetchall()
    total_cogs = 0.0
    for irow in items:
        qty = int(irow["quantity"] or 0)
        if qty <= 0:
            continue
        cost_at_sale = float(irow["cost_at_sale"] or 0)
        if cost_at_sale == 0:
            # Populate cost_at_sale at delivery time using cost_history with
            # baseline fallback. Skip re-population when already set.
            product_id = irow["product_id"]
            if product_id is None:
                continue
            try:
                pid = int(product_id)
            except (TypeError, ValueError):
                continue
            cost_at_sale = resolve_product_cost(conn, pid)
            if cost_at_sale > 0:
                conn.execute(
                    "UPDATE order_items SET cost_at_sale = ? WHERE id = ?",
                    (cost_at_sale, int(irow["item_id"])),
                )
        if cost_at_sale > 0:
            total_cogs += cost_at_sale * qty
    # COGS entry is created once per order with the accumulated total_cogs
    # from all items (out of the per-item loop). Inserting inside the loop
    # produced duplicate entries with partial/incorrect totals for multi-item
    # orders (review finding C-1).
    if total_cogs > 0:
        _insert_journal_entry(
            conn,
            description=f"Order COGS: {order_ref}",
            source_type="order_cogs",
            source_id=order_id,
            lines=[
                (cogs_account_id, total_cogs, 0.0, "Giá vốn hàng bán"),
                (inventory_account_id, 0.0, total_cogs, "Xuất kho"),
            ],
            transaction_date=order_transaction_date,
        )


def _sync_waste_cogs_journal(
    conn, product_id: int, movement_id: int, quantity: int
) -> None:
    """Create a COGS journal entry for wasted stock (source_type ``waste_cogs``).

    Debits COGS (5900) and credits Inventory (1300) for the cost of the wasted
    quantity. Cost is resolved via :func:`resolve_product_cost` (cost_history →
    baseline fallback). When the resolved cost is zero, no entry is created
    (consistent with sale COGS behaviour for zero-cost items).

    Idempotent: skips when a ``waste_cogs`` entry already exists for the given
    stock movement.
    """
    if quantity <= 0:
        return

    existing = conn.execute(
        "SELECT 1 FROM journal_entries WHERE source_type = 'waste_cogs' AND source_id = ?",
        (movement_id,),
    ).fetchone()
    if existing:
        return

    unit_cost = resolve_product_cost(conn, product_id)
    total = unit_cost * quantity
    if total <= 0:
        return

    # FR5: waste COGS uses the stock movement's `created_at` as the business
    # event date (queried via source_id = movement_id).
    movement_row = conn.execute(
        "SELECT created_at FROM stock_movements WHERE id = ?", (movement_id,)
    ).fetchone()
    transaction_date = movement_row["created_at"] if movement_row else None

    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    _insert_journal_entry(
        conn,
        description=f"Waste COGS: movement #{movement_id} product {product_id}",
        source_type="waste_cogs",
        source_id=movement_id,
        lines=[
            (cogs_account_id, float(total), 0.0, "Giá vốn hàng hao hụt"),
            (inventory_account_id, 0.0, float(total), "Xuất kho hao hụt"),
        ],
        transaction_date=transaction_date,
    )