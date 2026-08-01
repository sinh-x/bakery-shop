"""Cash drawer API routes (DG-324 Phase 2).

Endpoints:
    POST /api/cash-drawer/open   — open a daily drawer (FR1)
    POST /api/cash-drawer/close  — close with counted amount + discrepancy (FR7)
    POST /api/cash-drawer/cash-in  — owner puts cash in (FR2)
    POST /api/cash-drawer/cash-out — owner takes cash out (FR3)
    GET  /api/cash-drawer/status  — active drawer or null (FR4)
    GET  /api/cash-drawer/history — paginated past drawers (FR10)

All balance-affecting operations create balanced double-entry journal entries
via the shared ``_create_manual_journal_entry`` factory (NFR3): cash → debit
1100 / credit 3100 (equity), cash-out reverses the direction.

Traceability: FR1, FR2, FR3, FR4, FR7, FR8, FR9, FR10, NFR1, NFR3.
"""

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from baker.db.connection import get_db
from baker.db.schema import PAYMENT_METHOD_TO_ASSET_CODE, _account_id_by_code, _insert_journal_entry
from baker.models.cash_drawer import CashDrawer
from baker.models.journal_entry import JournalEntry, JournalLine
from baker.utils.time import now_utc

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/cash-drawer", tags=["cash-drawer"])

CASH_ASSET_CODE = "1100"
EQUITY_CODE = "3100"


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------


class OpenDrawerRequest(BaseModel):
    openingBalance: int = Field(..., ge=0, description="Số dư đầu ngày (VND)")
    note: str = ""


class CloseDrawerRequest(BaseModel):
    countedAmount: int = Field(..., ge=0, description="Số tiền đếm thực tế (VND)")
    note: str = ""


class CashMovementRequest(BaseModel):
    amount: int = Field(..., gt=0, description="Số tiền (VND)")
    note: str = ""


# ---------------------------------------------------------------------------
# Journal helpers (reuse _insert_journal_entry + account resolver pattern)
# ---------------------------------------------------------------------------


def _cash_and_equity_accounts(conn) -> dict[str, int]:
    return {
        "cash": _account_id_by_code(conn, CASH_ASSET_CODE),
        "equity": _account_id_by_code(conn, EQUITY_CODE),
    }


def _create_drawer_journal_entry(
    conn,
    *,
    source_type: str,
    description: str,
    debit_account_id: int,
    credit_account_id: int,
    amount: int,
) -> dict:
    """Insert a balanced double-entry journal entry for a drawer operation.

    NFR3: enforced by ``_insert_journal_entry`` (raises on debit != credit).
    Returns the API dict of the created entry (with lines).
    """
    amt = float(amount)
    lines = [
        (debit_account_id, amt, 0.0, description),
        (credit_account_id, 0.0, amt, description),
    ]
    entry_id = _insert_journal_entry(
        conn,
        description=description,
        source_type=source_type,
        source_id=None,
        lines=lines,
        transaction_date=now_utc(),
    )
    entry = JournalEntry.from_row(
        conn.execute("SELECT * FROM journal_entries WHERE id = ?", (entry_id,)).fetchone()
    )
    fetched_lines = JournalLine.list_for_entry(conn, entry_id)
    return entry.to_api_dict(fetched_lines)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/open", status_code=201)
def open_drawer(body: OpenDrawerRequest):
    """FR1: open a daily cash drawer with a starting balance.

    Creates a journal entry (debit 1100, credit 3100). Only one active drawer
    may exist at a time (NFR2/single-active-drawer rule).
    """
    with get_db() as conn:
        active = CashDrawer.get_active(conn)
        if active is not None:
            raise HTTPException(
                status_code=409,
                detail="Đã có quỹ tiền mặt đang mở — phải đóng quỹ hiện tại trước khi mở quỹ mới.",
            )
        accounts = _cash_and_equity_accounts(conn)
        drawer = CashDrawer(opened_at=now_utc(), opening_balance=int(body.openingBalance))
        drawer.save(conn)
        desc = f"Mở quỹ tiền mặt: {body.openingBalance}"
        if body.note:
            desc += f" — {body.note}"
        journal = _create_drawer_journal_entry(
            conn,
            source_type="cash_drawer_open",
            description=desc,
            debit_account_id=accounts["cash"],
            credit_account_id=accounts["equity"],
            amount=body.openingBalance,
        )
        result = drawer.to_api_dict()
        result["journalEntry"] = journal
        return result


@router.post("/cash-in", status_code=200)
def cash_in(body: CashMovementRequest):
    """FR2: owner puts cash into the active drawer.

    Creates a journal entry (debit 1100, credit 3100).
    """
    with get_db() as conn:
        drawer = _require_active_drawer(conn)
        accounts = _cash_and_equity_accounts(conn)
        drawer.add_owner_in(conn, body.amount)
        desc = f"Cho thêm tiền vào quỹ: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        journal = _create_drawer_journal_entry(
            conn,
            source_type="cash_drawer_cash_in",
            description=desc,
            debit_account_id=accounts["cash"],
            credit_account_id=accounts["equity"],
            amount=body.amount,
        )
        result = drawer.to_api_dict()
        result["journalEntry"] = journal
        return result


@router.post("/cash-out", status_code=200)
def cash_out(body: CashMovementRequest):
    """FR3: owner takes cash out of the active drawer.

    Creates a journal entry (debit 3100, credit 1100).
    """
    with get_db() as conn:
        drawer = _require_active_drawer(conn)
        accounts = _cash_and_equity_accounts(conn)
        drawer.add_owner_out(conn, body.amount)
        desc = f"Lấy tiền khỏi quỹ: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        journal = _create_drawer_journal_entry(
            conn,
            source_type="cash_drawer_cash_out",
            description=desc,
            debit_account_id=accounts["equity"],
            credit_account_id=accounts["cash"],
            amount=body.amount,
        )
        result = drawer.to_api_dict()
        result["journalEntry"] = journal
        return result


@router.post("/close", status_code=200)
def close_drawer(body: CloseDrawerRequest):
    """FR7: close the active drawer with a physical cash count.

    Computes discrepancy = counted - expected. When the discrepancy is
    non-zero, an adjustment journal entry is recorded (debit/credit 1100 vs
    3100) so the books match the counted cash. A zero-discrepancy close
    produces no additional journal entry.
    """
    with get_db() as conn:
        drawer = _require_active_drawer(conn)
        accounts = _cash_and_equity_accounts(conn)
        discrepancy = drawer.close(conn, counted_amount=body.countedAmount)
        desc = f"Đóng quỹ tiền mặt: đếm={body.countedAmount}, chênh lệch={discrepancy}"
        if body.note:
            desc += f" — {body.note}"
        journal = None
        if discrepancy != 0:
            amt = abs(discrepancy)
            if discrepancy > 0:
                # Surplus: more cash than books — debit 1100, credit 3100.
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_close_adjust",
                    description=desc,
                    debit_account_id=accounts["cash"],
                    credit_account_id=accounts["equity"],
                    amount=amt,
                )
            else:
                # Shortage: less cash than books — debit 3100, credit 1100.
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_close_adjust",
                    description=desc,
                    debit_account_id=accounts["equity"],
                    credit_account_id=accounts["cash"],
                    amount=amt,
                )
        result = drawer.to_api_dict()
        if journal is not None:
            result["journalEntry"] = journal
        return result


@router.get("/status")
def drawer_status():
    """FR4: return the active (open) drawer with expected balance, or null."""
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        return drawer.to_api_dict() if drawer else None


@router.get("/history")
def drawer_history(
    since: Optional[str] = Query(None, description="Từ ngày (ISO)"),
    until: Optional[str] = Query(None, description="Đến ngày (ISO)"),
    limit: int = Query(50, ge=1, le=500, description="Số kết quả tối đa"),
    offset: int = Query(0, ge=0, description="Bỏ qua bao nhiêu kết quả"),
):
    """FR10: paginated list of past drawers, filterable by date range."""
    with get_db() as conn:
        drawers, total = CashDrawer.list_history(
            conn, since=since, until=until, limit=limit, offset=offset
        )
        return {
            "total": total,
            "limit": limit,
            "offset": offset,
            "items": [d.to_api_dict() for d in drawers],
        }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _require_active_drawer(conn) -> CashDrawer:
    drawer = CashDrawer.get_active(conn)
    if drawer is None:
        raise HTTPException(
            status_code=409,
            detail="Không có quỹ tiền mặt đang mở — hãy mở quỹ trước.",
        )
    return drawer