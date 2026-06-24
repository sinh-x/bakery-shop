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
    COGS_CODE,
    CUSTOMER_DEPOSITS_CODE,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    EXPENSE_PAYMENT_SOURCE_TO_ASSET_CODE,
    INVENTORY_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    ORDER_REVENUE_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    PAYMENT_OUTFLOW_TYPES,
    REVENUE_UPDATE_TOLERANCE,
    _account_id_by_code,
    _ensure_staff_advance_sub_account,
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
        "SELECT description, source_type, source_id FROM journal_entries WHERE id = ?",
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
    return _insert_journal_entry(
        conn,
        description=f"Reversal: {orig['description']}",
        source_type=orig["source_type"],
        source_id=orig["source_id"],
        lines=reversed_lines,
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
        asset_account_id = _ensure_staff_advance_sub_account(conn, staff_name)
    else:
        asset_code = EXPENSE_PAYMENT_SOURCE_TO_ASSET_CODE.get(payment_source)
        if not asset_code:
            return None
        asset_account_id = _account_id_by_code(conn, asset_code)

    amount_f = float(amount)
    description = f"Expense: {summary}"

    if category in INVENTORY_PURCHASE_CATEGORIES:
        inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
        lines = [
            (inventory_account_id, amount_f, 0.0, "Nhập kho nguyên vật liệu"),
            (asset_account_id, 0.0, amount_f, "Thanh toán"),
        ]
    else:
        expense_account_id = _account_id_by_code(conn, expense_code)
        lines = [
            (expense_account_id, amount_f, 0.0, "Chi phí"),
            (asset_account_id, 0.0, amount_f, "Thanh toán"),
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

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense",
            source_id=event_id,
            lines=lines,
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
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )


def _build_payment_journal_lines(
    conn, amount: float, ptype: str, method: str
) -> tuple[str, list[tuple[int, float, float, str]]]:
    """Build (description, lines) for a payment_transaction's journal entry."""
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(method or "cash", "1100")
    asset_account_id = _account_id_by_code(conn, asset_code)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    amount_f = float(amount)
    ptype = ptype or "deposit"
    if ptype in PAYMENT_OUTFLOW_TYPES:
        # Cash flows back to customer: debit Customer Deposits, credit Asset.
        lines = [
            (deposits_account_id, amount_f, 0.0, "Hoàn tiền khách"),
            (asset_account_id, 0.0, amount_f, "Trả lại tiền"),
        ]
    else:
        # Customer pays in: debit Asset, credit Customer Deposits.
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
    deleted: bool = False,
) -> None:
    """Create/update/delete the journal entry for a payment_transaction."""
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

    description, lines = _build_payment_journal_lines(conn, amount, ptype, method)

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
        )
    elif _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="payment_transaction",
            source_id=txn_id,
            lines=lines,
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

    Update handling: if a revenue entry already exists, its 2100 debit is
    compared against the current net deposits. When they differ by more than
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

    if existing:
        existing_id = int(existing["id"])
        # Compare the existing entry's 2100 debit against current net deposits.
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
        mismatch = abs(current_debit - max(net, 0.0))
        if mismatch <= REVENUE_UPDATE_TOLERANCE:
            # Entry already matches net deposits — leave it untouched.
            return
        if respect_locks and _is_locked(conn, existing_id):
            # Locked: cannot delete. Reverse the stale entry, then create a
            # corrected one below.
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)

    if net > 0:
        # Paid: move net deposits to revenue
        _insert_journal_entry(
            conn,
            description=f"Order revenue: {order_ref}",
            source_type="order",
            source_id=order_id,
            lines=[
                (deposits_account_id, float(net), 0.0, "Chuyển cọc sang doanh thu"),
                (revenue_account_id, 0.0, float(net), "Doanh thu bán hàng"),
            ],
        )
    else:
        # Truly unpaid (no deposits and no refunds): record the order total
        # as accounts receivable (customer debt). When total_price is unknown
        # the order row is read from the orders table to remain backwards
        # compatible with callers that omit it.
        if PaymentTransaction.total_paid_excl_outflows(conn, order_id) <= 0:
            if total_price is None:
                order_row = conn.execute(
                    "SELECT total_price FROM orders WHERE id = ?", (order_id,)
                ).fetchone()
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
                )
        # else: net <= 0 but deposits existed (refunds drained them) → no
        # revenue to recognize; skip creating any entry.


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

    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    cogs_account_id = _account_id_by_code(conn, COGS_CODE)
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
    )