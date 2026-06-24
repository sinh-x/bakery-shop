"""Accounting API routes — chart of accounts, journal, balances, lock, owner
capital/draw, and staff reimbursement.

Journal auto-generation sync helpers live in :mod:`baker.services.journal_sync`
so they can be shared by the events, payment_transactions, orders,
reconciliations, and stock routers without coupling to this API module.
"""

import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from baker.db.connection import get_db
from baker.db.schema import (
    PAYMENT_METHOD_TO_ASSET_CODE,
    _account_id_by_code,
    _ensure_staff_advance_sub_account,
    _insert_journal_entry,
)
from baker.services.accounting_validation import run_validation
from baker.models.account import Account
from baker.models.journal_entry import JournalEntry, JournalLine

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/accounts", tags=["accounts"])


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
            conditions.append("je.transaction_date >= ?")
            params.append(since)
        if until is not None:
            conditions.append("je.transaction_date <= ?")
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
            "ORDER BY je.transaction_date DESC, je.id DESC LIMIT ? OFFSET ?",
            [*params, limit, offset],
        ).fetchall()

        items: list[dict] = []
        # First pass: collect all journal lines for the page, then batch-fetch
        # the referenced accounts in one query to avoid N+1 per-line lookups.
        page_lines: list[list] = []
        for r in rows:
            entry = JournalEntry.from_row(r)
            lines = JournalLine.list_for_entry(conn, entry.id)
            d = entry.to_api_dict(lines)
            page_lines.append((d, lines))
            items.append(d)
        account_ids = {
            int(line["accountId"])
            for d, lines in page_lines
            for line in d["lines"]
        }
        accounts_by_id = Account.get_by_ids(conn, sorted(account_ids))
        # Enrich lines with account code/name for convenience.
        for d, _lines in page_lines:
            for line in d["lines"]:
                acc = accounts_by_id.get(int(line["accountId"]))
                if acc:
                    line["accountCode"] = acc.code
                    line["accountName"] = acc.name
                    line["accountType"] = acc.type

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
        # FR6: manual entries have no source record — transaction_date is the
        # current time at creation.
        entry_id = _insert_journal_entry(
            conn,
            description=desc,
            source_type="owner_capital",
            source_id=None,
            lines=[
                (asset_account_id, float(body.amount), 0.0, "Tiền đưa vào"),
                (equity_account_id, 0.0, float(body.amount), "Vốn chủ sở hữu"),
            ],
            transaction_date=datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
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
        # FR6: manual entries have no source record — transaction_date is the
        # current time at creation.
        entry_id = _insert_journal_entry(
            conn,
            description=desc,
            source_type="owner_draw",
            source_id=None,
            lines=[
                (equity_account_id, float(body.amount), 0.0, "Giảm vốn"),
                (asset_account_id, 0.0, float(body.amount), "Rút tiền"),
            ],
            transaction_date=datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
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
        # FR6: manual entries have no source record — transaction_date is the
        # current time at creation.
        entry_id = _insert_journal_entry(
            conn,
            description=desc,
            source_type="staff_reimburse",
            source_id=None,
            lines=[
                (staff_account_id, float(body.amount), 0.0, "Ứng trước nhân viên"),
                (asset_account_id, 0.0, float(body.amount), "Trả tiền hoàn ứng"),
            ],
            transaction_date=datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        )
        entry = JournalEntry.from_row(
            conn.execute("SELECT * FROM journal_entries WHERE id = ?", (entry_id,)).fetchone()
        )
        lines = JournalLine.list_for_entry(conn, entry_id)
        return entry.to_api_dict(lines)


@router.get("/validate")
def validate_accounts():
    """Chạy kiểm tra toàn vẹn dữ liệu kế toán (double-entry, COGS, waste, cost history)."""
    with get_db() as conn:
        return run_validation(conn)