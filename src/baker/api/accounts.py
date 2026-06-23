"""Accounting API routes — chart of accounts, journal, balances, lock, owner
capital/draw, and staff reimbursement.

Also exposes journal auto-generation sync helpers used by the events,
payment_transactions, and orders routers so that every financial transaction
automatically produces a double-entry journal entry.
"""

import logging
from datetime import datetime
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from baker.db.connection import get_db
from baker.db.schema import (
    COGS_CODE,
    CUSTOMER_DEPOSITS_CODE,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    EXPENSE_PAYMENT_SOURCE_TO_ASSET_CODE,
    INVENTORY_CODE,
    ORDER_REVENUE_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    PAYMENT_OUTFLOW_TYPES,
    _account_id_by_code,
    _ensure_staff_advance_sub_account,
    _insert_journal_entry,
)
from baker.services.cost_resolver import resolve_product_cost
from baker.models.account import Account
from baker.models.journal_entry import JournalEntry, JournalLine
from baker.models.payment_transaction import PaymentTransaction

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/accounts", tags=["accounts"])

STAFF_ADVANCE_PAYMENT_SOURCE = "Nhân viên ứng trước"


# ---------------------------------------------------------------------------
# Journal sync helpers (used by events/payment/orders routers)
# ---------------------------------------------------------------------------


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

    expense_account_id = _account_id_by_code(conn, expense_code)
    amount_f = float(amount)
    description = f"Expense: {summary}"
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


def _sync_delivered_order_journal(conn, order_id: int, order_ref: str) -> None:
    """Create revenue conversion + COGS journal entries for a delivered order.

    Idempotent: skips if entries already exist for this order.
    """
    inventory_account_id = _account_id_by_code(conn, INVENTORY_CODE)
    revenue_account_id = _account_id_by_code(conn, ORDER_REVENUE_CODE)
    deposits_account_id = _account_id_by_code(conn, CUSTOMER_DEPOSITS_CODE)
    cogs_account_id = _account_id_by_code(conn, COGS_CODE)

    # Revenue conversion: net payments (excl. tien_rut) from Customer Deposits → Revenue.
    net = PaymentTransaction.total_paid_excl_tien_rut(conn, order_id)
    if net > 0:
        existing = conn.execute(
            "SELECT 1 FROM journal_entries WHERE source_type = 'order' AND source_id = ?",
            (order_id,),
        ).fetchone()
        if not existing:
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


# ---------------------------------------------------------------------------
# API request/response models
# ---------------------------------------------------------------------------


class JournalLockRequest(BaseModel):
    since: str
    until: str
    lockedBy: str = Field(default="", max_length=100)


class OwnerCapitalRequest(BaseModel):
    amount: float
    method: str = "cash"  # 'cash' → 1100, 'transfer' → 1200
    note: str = ""


class OwnerDrawRequest(BaseModel):
    amount: float
    method: str = "cash"
    note: str = ""


class StaffReimburseRequest(BaseModel):
    staffName: str
    amount: float
    method: str = "cash"
    note: str = ""


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


def _account_with_children(conn, account: Account) -> dict:
    """Build a hierarchical dict for one account, recursing into sub-accounts."""
    subs = Account.get_sub_accounts(conn, account.id)
    sub_dicts = [_account_with_children(conn, sub) for sub in subs]
    return {
        **account.to_api_dict(),
        "children": sub_dicts,
    }


@router.get("")
def list_accounts():
    """Danh sách tài khoản phân cấp (chart of accounts)."""
    with get_db() as conn:
        all_accounts = Account.list_all(conn)
        # Build a tree starting from top-level accounts (parent_id IS NULL).
        top_level = [a for a in all_accounts if a.parent_id is None]
        return [_account_with_children(conn, a) for a in top_level]


@router.get("/journal")
def list_journal(
    since: Optional[str] = Query(None, description="Từ ngày (ISO)"),
    until: Optional[str] = Query(None, description="Đến ngày (ISO)"),
    account_id: Optional[int] = Query(None, description="Lọc theo account id"),
    source_type: Optional[str] = Query(None, description="Lọc theo source_type"),
    source_id: Optional[int] = Query(None, description="Lọc theo source_id"),
    limit: int = Query(100, ge=1, le=1000, description="Số kết quả tối đa"),
    offset: int = Query(0, ge=0, description="Bỏ qua bao nhiêu kết quả"),
):
    """Tra cứu journal entries với filter và phân trang."""
    with get_db() as conn:
        conditions: list[str] = []
        params: list = []
        if since is not None:
            conditions.append("je.created_at >= ?")
            params.append(since)
        if until is not None:
            conditions.append("je.created_at <= ?")
            params.append(until)
        if source_type is not None:
            conditions.append("je.source_type = ?")
            params.append(source_type)
        if source_id is not None:
            conditions.append("je.source_id = ?")
            params.append(source_id)
        if account_id is not None:
            conditions.append(
                "EXISTS (SELECT 1 FROM journal_lines jl WHERE jl.journal_entry_id = je.id AND jl.account_id = ?)"
            )
            params.append(account_id)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        total_row = conn.execute(
            f"SELECT COUNT(*) AS c FROM journal_entries je {where}",
            params,
        ).fetchone()
        total = int(total_row["c"])

        rows = conn.execute(
            f"SELECT je.* FROM journal_entries je {where} "
            "ORDER BY je.created_at DESC, je.id DESC LIMIT ? OFFSET ?",
            [*params, limit, offset],
        ).fetchall()

        items: list[dict] = []
        for r in rows:
            entry = JournalEntry.from_row(r)
            lines = JournalLine.list_for_entry(conn, entry.id)
            d = entry.to_api_dict(lines)
            # Enrich lines with account code/name for convenience.
            for line in d["lines"]:
                acc = Account.get_by_id(conn, int(line["accountId"]))
                if acc:
                    line["accountCode"] = acc.code
                    line["accountName"] = acc.name
                    line["accountType"] = acc.type
            items.append(d)

        return {"total": total, "limit": limit, "offset": offset, "items": items}


@router.get("/balances")
def get_balances():
    """Số dư hiện tại của từng tài khoản (tính từ journal_lines)."""
    with get_db() as conn:
        return JournalEntry.get_balances(conn)


@router.post("/journal/lock")
def lock_journal(body: JournalLockRequest):
    """Khóa journal entries trong khoảng [since, until]."""
    if not body.since or not body.until:
        raise HTTPException(status_code=422, detail="since và until là bắt buộc")
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    with get_db() as conn:
        count = JournalEntry.lock_range(
            conn, since=body.since, until=body.until, locked_at=now, locked_by=body.lockedBy
        )
        return {"lockedCount": count, "lockedAt": now}


@router.post("/owner-capital", status_code=201)
def owner_capital(body: OwnerCapitalRequest):
    """Ghi nhận vốn chủ sở hữu đưa vào tiệm: debit Asset, credit Owner's Equity."""
    if body.amount <= 0:
        raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(body.method, "1100")
    with get_db() as conn:
        asset_account_id = _account_id_by_code(conn, asset_code)
        equity_account_id = _account_id_by_code(conn, "3100")
        desc = f"Vốn chủ sở hữu đưa vào: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        entry_id = _insert_journal_entry(
            conn,
            description=desc,
            source_type="owner_capital",
            source_id=None,
            lines=[
                (asset_account_id, float(body.amount), 0.0, "Tiền đưa vào"),
                (equity_account_id, 0.0, float(body.amount), "Vốn chủ sở hữu"),
            ],
        )
        entry = JournalEntry.from_row(
            conn.execute("SELECT * FROM journal_entries WHERE id = ?", (entry_id,)).fetchone()
        )
        lines = JournalLine.list_for_entry(conn, entry_id)
        return entry.to_api_dict(lines)


@router.post("/owner-draw", status_code=201)
def owner_draw(body: OwnerDrawRequest):
    """Ghi nhận chủ sở hữu rút vốn: debit Owner's Equity, credit Asset."""
    if body.amount <= 0:
        raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(body.method, "1100")
    with get_db() as conn:
        asset_account_id = _account_id_by_code(conn, asset_code)
        equity_account_id = _account_id_by_code(conn, "3100")
        desc = f"Chủ rút vốn: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        entry_id = _insert_journal_entry(
            conn,
            description=desc,
            source_type="owner_draw",
            source_id=None,
            lines=[
                (equity_account_id, float(body.amount), 0.0, "Giảm vốn"),
                (asset_account_id, 0.0, float(body.amount), "Rút tiền"),
            ],
        )
        entry = JournalEntry.from_row(
            conn.execute("SELECT * FROM journal_entries WHERE id = ?", (entry_id,)).fetchone()
        )
        lines = JournalLine.list_for_entry(conn, entry_id)
        return entry.to_api_dict(lines)


@router.post("/staff-reimburse", status_code=201)
def staff_reimburse(body: StaffReimburseRequest):
    """Hoàn ứng cho nhân viên: debit Staff Advances sub-account, credit Asset."""
    if body.amount <= 0:
        raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")
    if not body.staffName.strip():
        raise HTTPException(status_code=422, detail="staffName là bắt buộc")
    asset_code = PAYMENT_METHOD_TO_ASSET_CODE.get(body.method, "1100")
    with get_db() as conn:
        staff_account_id = _ensure_staff_advance_sub_account(conn, body.staffName.strip())
        asset_account_id = _account_id_by_code(conn, asset_code)
        desc = f"Hoàn ứng cho {body.staffName}: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        entry_id = _insert_journal_entry(
            conn,
            description=desc,
            source_type="staff_reimburse",
            source_id=None,
            lines=[
                (staff_account_id, float(body.amount), 0.0, "Ứng trước nhân viên"),
                (asset_account_id, 0.0, float(body.amount), "Trả tiền hoàn ứng"),
            ],
        )
        entry = JournalEntry.from_row(
            conn.execute("SELECT * FROM journal_entries WHERE id = ?", (entry_id,)).fetchone()
        )
        lines = JournalLine.list_for_entry(conn, entry_id)
        return entry.to_api_dict(lines)