"""Payment-domain journal sync (DG-308 Phase 4.4, FR-ARCH-2).

Payment-transaction journal entry build/sync logic and the held-shipping /
held-tien-rut balance helpers, extracted from the original monolithic
``journal_sync.py``.
"""

from typing import Optional

from baker.db.schema import (
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    PAYMENT_OUTFLOW_TYPES,
    REVENUE_UPDATE_TOLERANCE,
    TIEN_RUT_HELD_CODE,
    TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE,
    UNALLOCATED_BANK_CODE,
    _account_id_by_code,
    _insert_journal_entry,
)
from baker.services.journal_sync._common import (
    _active_drawer_id,
    _delete_journal_entry_cascade,
    _find_journal_entry,
    _is_locked,
    _reverse_journal_entry,
    _update_journal_entry_in_place,
    run_journal_sync,
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

def _held_tien_rut_for_order(
    conn, order_id: int, *, exclude_txn_id: Optional[int] = None
) -> float:
    """Return the net tien_rut currently held in account 2400 for the order.

    Sums 2400 credits (held at payment time — DR Asset / CR 2400) minus 2400
    debits (returned to the customer at delivery, or reversed by
    invalidation/reversal) across the order's ``payment_transaction`` and
    ``order`` journal entries. Used by :func:`_reconcile_order_revenue_entry`
    to determine how much 2400 to return to the customer at delivery (FR3,
    DG-198 reversal).

    ``exclude_txn_id`` excludes that transaction's journal entry from the sum —
    used on the update path so the current transaction's stale entry does not
    skew the total.
    """
    exclude_clause = ""
    params: list = [order_id]
    if exclude_txn_id is not None:
        exclude_clause = " AND je.source_id != ?"
        params.append(exclude_txn_id)
    row = conn.execute(
        f"""
        SELECT COALESCE(SUM(jl.credit - jl.debit), 0) AS net_held
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = ?
          AND je.source_type = 'payment_transaction'
          AND je.source_id IN (
              SELECT id FROM payment_transactions WHERE order_id = ?
          )
          {exclude_clause}
        """,
        [TIEN_RUT_HELD_CODE] + params,
    ).fetchone()
    return float(row["net_held"] or 0)

def _resolve_transaction_asset_code(
    method: str,
    payment_source: str,
) -> str:
    """Resolve the asset account code for a payment_transaction journal line.

    DG-244 Phase 4 routing rules (FR4/FR5/FR8):

      * ``payment_source`` in ``TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE``
        → that bank sub-account (1210 Phượng VCB / 1220 Ân VCB). The
        ``method`` is ignored — when an account is explicitly selected, the
        journal entry references that bank account regardless of method.
      * ``payment_source`` empty/None/unrecognized AND ``method == 'transfer'``
        → ``UNALLOCATED_BANK_CODE`` (1290). This replaces the old
        ``PAYMENT_METHOD_TO_ASSET_CODE['transfer']`` (1200) default so
        unallocated transfer deposits land in a distinct account. Phase 5
        historical backfill will move existing 1200 transfer entries to 1290.
      * ``payment_source`` empty/None/unrecognized AND method is ``cash``/``card``
        → ``PAYMENT_METHOD_TO_ASSET_CODE[method]`` (1100). Non-transfer
        methods keep their existing behavior (FR5 only mandates the
        un-allocated fallback for transfer-type payments routed to a bank).

    Unknown ``payment_source`` values (not in the map) are treated as
    un-allocated rather than rejected, so a stale label never breaks
    journal sync — the entry still balances and is reassignable via Edit
    Payment.
    """
    ps = (payment_source or "").strip()
    if ps and ps in TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE:
        return TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE[ps]
    method_norm = method or "cash"
    if method_norm == "transfer":
        return UNALLOCATED_BANK_CODE
    return PAYMENT_METHOD_TO_ASSET_CODE.get(method_norm, "1100")

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
    payment_source: str = "",
) -> tuple[str, list[tuple[int, float, float, str]]]:
    """Build (description, lines) for a payment_transaction's journal entry.

    Bus orders (``delivery_type == 'bus'``) with ``shipping_fee > 0`` split the
    inflow credit between Customer Deposits (2100) and Bus Shipping Held (2200).
    The shipping portion is allocated to 2200 only up to the order's
    ``shipping_fee`` across all payments (first payments cover shipping; later
    payments go entirely to 2100). ``exclude_txn_id`` is used on the update
    path so the current transaction's stale entry does not skew the allocation.

    Outflow transactions (``refund``) are NOT split — the 2200 release at
    refund time is deferred to Phase 3 (revenue exclusion + shipping release).
    ``refund`` debits 2100 (Customer Deposits) and credits the asset account —
    the reverse of a normal deposit. The held shipping balance in 2200 is
    preserved until the delivery release entry handles it.

    ``tien_rut`` is a deposit inflow (DG-198 reversal): the customer gives cash
    to the shop for safekeeping. It journals DR Asset / CR 2400 (Tien Rut Held)
    — NOT split into 2200 because tien_rut is not a product deposit. At
    delivery 2400 is returned to the customer via a separate ``order`` journal
    entry (see :func:`_reconcile_order_revenue_entry`).

    Non-bus orders and bus orders with no shipping_fee behave exactly as before.

    DG-244 Phase 4: ``payment_source`` routes the asset (debit) side to a
    distinct bank sub-account when set, or to the un-allocated bank account
    (1290) when empty on a transfer. See :func:`_resolve_transaction_asset_code`.
    """
    asset_code = _resolve_transaction_asset_code(method, payment_source)
    asset_account_id = _account_id_by_code(conn, asset_code)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    tien_rut_account_id = _account_id_by_code(conn, TIEN_RUT_HELD_CODE)
    amount_f = float(amount)
    ptype = ptype or "deposit"

    # Tien rut deposit inflow (DG-198 reversal): DR Asset, CR 2400. Not split
    # into 2200 — tien_rut is cash held for the customer, not a product deposit.
    if ptype == "tien_rut":
        lines = [
            (asset_account_id, amount_f, 0.0, "Tiền khách gửi giữ hộ"),
            (tien_rut_account_id, 0.0, amount_f, "Tiền rút tạm giữ"),
        ]
        description = f"Payment: tien_rut {amount_f}"
        return description, lines

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
        # Refund: cash flows back to customer. Phase 2 does NOT split outflows —
        # the 2200 release is deferred to Phase 3 (delivery shipping release).
        # refund debits 2100 (Customer Deposits) and credits the asset account.
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

def _maybe_retrigger_bus_shipping_release(
    conn,
    order_id: Optional[int],
    *,
    deleted: bool,
) -> None:
    """Re-trigger the bus shipping release sync for an already-completed order.

    DG-366 Phase 3 (FR2/FR3). When a payment is created, updated, or deleted
    for a bus order that is already in ``delivered`` or ``completed`` status,
    the ``order_shipping_release`` entry must be re-evaluated:

      - Create path (FR2/AC2): a completed bus order with no prior release
        gets its release entry created for the full ``shipping_fee``.
      - Update path (FR2/AC3): an existing release is re-synced; the
        underlying :func:`_sync_bus_shipping_release_entry` is idempotent
        when the release amount already matches ``shipping_fee`` (within
        ``REVENUE_UPDATE_TOLERANCE``), so an update that does not change
        ``shipping_fee`` is a no-op.
      - Delete path (FR3/AC4): when the last payment is deleted and no held
        shipping remains in 2200, the release entry is removed. Removal is
        delegated to :func:`_sync_bus_shipping_release_entry`, which — per
        Phase 1 — always releases the full ``shipping_fee``; when there is
        no held shipping to release (held == 0) the release entry is
        deleted so the 2200 account does not carry a stale debit. The
        deletion is performed here as a targeted cleanup so the release
        sync never has to recompute the removal decision.

    The re-trigger is fire-and-forget via :func:`run_journal_sync` (NFR1):
    a shipping release sync failure never blocks the payment CRUD
    operation. The ``source_type``/``source_id`` pair on the
    ``run_journal_sync`` call ties any failure back to the order for audit
    logging (FR4, established in Phase 2).

    The order is loaded once to determine ``delivery_type`` and ``status``;
    non-bus orders and orders not yet delivered/completed are skipped (the
    delivery/completion sync paths already create the release entry).
    """
    if order_id is None:
        return
    row = conn.execute(
        "SELECT delivery_type, status, order_ref FROM orders WHERE id = ?",
        (order_id,),
    ).fetchone()
    if row is None:
        return
    delivery_type = row["delivery_type"] or "pickup"
    status = row["status"] or "new"
    if delivery_type != "bus" or status not in ("delivered", "completed"):
        return

    order_ref = row["order_ref"] or str(order_id)

    # Lazy import: ``order`` imports from ``payment`` at module load, so a
    # top-level import here would create a circular dependency.
    from baker.services.journal_sync.order import _sync_bus_shipping_release_entry

    if deleted:
        # FR3/AC4: if no held shipping remains in 2200 after deletion, the
        # release entry must be removed so the 2200 account does not carry a
        # stale debit. ``_sync_bus_shipping_release_entry`` always releases
        # the full ``shipping_fee`` (Phase 1), so when held == 0 we delete
        # the existing release entry directly; otherwise we re-sync so the
        # release amount is re-validated against the new held balance.
        held = _held_shipping_for_order(conn, order_id)
        existing_id = _find_journal_entry(conn, "order_shipping_release", order_id)
        if existing_id is not None and held <= REVENUE_UPDATE_TOLERANCE:
            if _is_locked(conn, existing_id):
                _reverse_journal_entry(conn, existing_id)
            else:
                _delete_journal_entry_cascade(conn, existing_id)
            return
        # Held shipping remains — fall through to the re-sync path so the
        # release entry is reconciled against the new held balance.
        run_journal_sync(
            _sync_bus_shipping_release_entry,
            conn, order_id, order_ref,
            log_label=(
                f"bus shipping release re-sync (payment delete) for order "
                f"{order_id} ({order_ref})"
            ),
            source_type="order_shipping_release",
            source_id=order_id,
        )
        return

    # FR2/AC2/AC3: re-trigger the release sync (idempotent if amounts match).
    run_journal_sync(
        _sync_bus_shipping_release_entry,
        conn, order_id, order_ref,
        log_label=(
            f"bus shipping release re-sync (payment change) for order "
            f"{order_id} ({order_ref})"
        ),
        source_type="order_shipping_release",
        source_id=order_id,
    )


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
    payment_source: str = "",
) -> None:
    """Create/update/delete the journal entry for a payment_transaction.

    When ``order_id`` is provided, the order's ``delivery_type`` and
    ``shipping_fee`` are read from the orders table unless explicitly
    overridden by the ``delivery_type`` / ``shipping_fee`` keyword arguments.
    Bus orders with shipping split the credit between 2100 and 2200 (see
    :func:`_build_payment_journal_lines`).

    DG-244 Phase 4: ``payment_source`` is forwarded to
    :func:`_build_payment_journal_lines` so the asset (debit) side routes to
    the selected bank sub-account (1210/1220) or the un-allocated fallback
    (1290) on transfers with no source. On the ``deleted=True`` path the
    existing entry is reversed/deleted directly (no asset re-resolution), so
    ``payment_source`` is informational there.
    """
    # Resolve order context from the orders table when only order_id is given.
    if order_id is not None and (not delivery_type or delivery_type == "pickup") and shipping_fee == 0.0:
        d_type, s_fee = _bus_shipping_allocation_for_order(conn, order_id)
        delivery_type = d_type
        shipping_fee = s_fee

    existing_id = _find_journal_entry(conn, "payment_transaction", txn_id)

    if deleted:
        if existing_id is None:
            _maybe_retrigger_bus_shipping_release(conn, order_id, deleted=True)
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        _maybe_retrigger_bus_shipping_release(conn, order_id, deleted=True)
        return

    if not isinstance(amount, (int, float)) or float(amount) <= 0:
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        _maybe_retrigger_bus_shipping_release(conn, order_id, deleted=False)
        return

    # FR4: the payment transaction's `created_at` is the business event date.
    # DG-244 Phase 4: also read the persisted payment_source so callers that
    # don't thread payment_source (e.g. orders.py shipping-fee re-sync) still
    # route to the correct bank sub-account. The column is optional on legacy
    # schemas (added by v76); fall back to '' when absent so historical
    # migration callables don't raise.
    has_payment_source_col = bool(conn.execute(
        "SELECT 1 FROM pragma_table_info('payment_transactions') "
        "WHERE name = 'payment_source'"
    ).fetchone())
    if has_payment_source_col:
        txn_row = conn.execute(
            "SELECT created_at, payment_source FROM payment_transactions WHERE id = ?",
            (txn_id,),
        ).fetchone()
    else:
        txn_row = conn.execute(
            "SELECT created_at, '' AS payment_source FROM payment_transactions WHERE id = ?",
            (txn_id,),
        ).fetchone()
    transaction_date = txn_row["created_at"] if txn_row else None
    # If the caller did not pass payment_source, fall back to the persisted
    # value (e.g. orders.py shipping-fee re-sync path reads rows directly
    # without threading payment_source through). When the caller DOES pass
    # a non-empty value, that wins — it reflects the latest update payload.
    persisted_source = (
        txn_row["payment_source"] if txn_row and "payment_source" in txn_row.keys() else ""
    ) or ""
    effective_source = payment_source if payment_source else persisted_source

    description, lines = _build_payment_journal_lines(
        conn,
        amount,
        ptype,
        method,
        order_id=order_id,
        delivery_type=delivery_type,
        shipping_fee=shipping_fee,
        exclude_txn_id=txn_id if existing_id is not None else None,
        payment_source=effective_source,
    )

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
            transaction_date=transaction_date,
            drawer_id=_active_drawer_id(conn),
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
            drawer_id=_active_drawer_id(conn),
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )

    # FR2/AC2/AC3: re-trigger the bus shipping release sync for an
    # already-completed bus order so a payment change after delivery creates
    # or re-syncs the ``order_shipping_release`` entry. Fire-and-forget via
    # ``run_journal_sync`` (NFR1) — never blocks the payment CRUD operation.
    _maybe_retrigger_bus_shipping_release(conn, order_id, deleted=False)
