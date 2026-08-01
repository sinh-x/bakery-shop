"""Cash drawer API routes (DG-324 Phase 2 / Phase 6).

Endpoints:
    POST /api/cash-drawer/open   — open a daily drawer (FR1, FR9 carry-over)
    POST /api/cash-drawer/close  — close with counted amount + discrepancy (FR7)
    POST /api/cash-drawer/cash-in  — owner puts cash in (FR2)
    POST /api/cash-drawer/cash-out — owner takes cash out (FR3)
    GET  /api/cash-drawer/status  — active drawer or null (FR4)
    GET  /api/cash-drawer/history — paginated past drawers (FR10)

Phase 6 (FR8/FR9): every drawer operation first runs a lazy auto-close check
that closes any open drawer whose ``opened_at`` belongs to a previous local
day, using ``expected_balance`` as the counted amount and ``discrepancy = 0``.
When opening, if a previous-day drawer was just auto-closed, its expected
balance is proposed as today's opening balance and the owner must confirm it
(``carryOverConfirmed`` flag).

All balance-affecting operations create balanced double-entry journal entries
via the shared ``_create_manual_journal_entry`` factory (NFR3): cash → debit
1100 / credit 3100 (equity), cash-out reverses the direction.

Traceability: FR1, FR2, FR3, FR4, FR7, FR8, FR9, FR10, NFR1, NFR3.
"""

import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from baker.config import TIMEZONE
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
    carryOverConfirmed: bool = Field(
        False,
        description="Owner confirms the carried-over balance from the previous "
        "unclosed day (FR9). Required when a carry-over proposal is returned.",
    )


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
# Lazy auto-close at midnight (FR8) + carry-over proposal (FR9)
# ---------------------------------------------------------------------------


def _start_of_today_local_iso() -> str:
    """Return the UTC ISO-8601 timestamp of midnight at the start of the
    current local day. Any open drawer whose ``opened_at`` is strictly before
    this timestamp belongs to a previous local day and is stale (FR8).
    """
    now_local = datetime.now(TIMEZONE)
    midnight_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    midnight_utc = midnight_local.astimezone(timezone.utc)
    return midnight_utc.strftime("%Y-%m-%dT%H:%M:%SZ")


def _auto_close_stale_drawers(conn) -> list[CashDrawer]:
    """FR8 lazy auto-close: close every open drawer from a previous local day.

    Uses ``expected_balance`` as the counted amount and ``discrepancy = 0``
    (NFR1). No close-adjustment journal entry is created because there is no
    discrepancy to absorb (NFR3). Race-condition safety: :meth:`auto_close`
    guards the update with ``WHERE status = 'open'`` so concurrent writers
    cannot double-close the same drawer. Returns the list of auto-closed
    drawers (oldest first); idempotent — returns ``[]`` when none are stale.

    The auto-close is committed in its own transaction (independent of the
    caller's operation) so it persists even when the triggering operation
    later fails — auto-close is housekeeping, not part of the caller's
    atomic unit. This keeps a 409 from a cash-in/close (e.g. no active
    drawer) from undoing the auto-close of a previous-day drawer.
    """
    stale = CashDrawer.get_stale_open_before(conn, before_iso=_start_of_today_local_iso())
    closed: list[CashDrawer] = []
    for drawer in stale:
        drawer.auto_close(conn)
        closed.append(drawer)
    if closed:
        conn.commit()
    return closed


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/open", status_code=201)
def open_drawer(body: OpenDrawerRequest):
    """FR1: open a daily cash drawer with a starting balance.

    Creates a journal entry (debit 1100, credit 3100). Only one active drawer
    may exist at a time (NFR2/single-active-drawer rule).

    FR9 carry-over: if a previous-day drawer is still open, the system
    proposes that drawer's expected balance as today's opening balance and
    requires the owner to confirm it (``carryOverConfirmed``). On confirmation
    the stale drawer is auto-closed (FR8) and today's drawer is opened with
    the requested amount.
    """
    with get_db() as conn:
        # FR9: detect unclosed previous-day drawers before opening.
        stale = CashDrawer.get_stale_open_before(
            conn, before_iso=_start_of_today_local_iso()
        )
        carry_over_from = None
        if stale:
            latest = stale[-1]
            proposed = latest.expected_balance()
            if not body.carryOverConfirmed:
                # Propose the carry-over and require owner confirmation.
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            "Quỹ hôm trước chưa đóng — xác nhận số dư chuyển sang hôm nay."
                        ),
                        "carryOverProposal": {
                            "amount": proposed,
                            "fromDrawerId": str(latest.id),
                            "fromOpenedAt": latest.opened_at,
                            "fromExpectedBalance": proposed,
                        },
                    },
                )
            # Owner confirmed — auto-close every stale drawer (FR8), then open.
            for drawer in stale:
                drawer.auto_close(conn)
            carry_over_from = {
                "fromDrawerId": str(latest.id),
                "fromExpectedBalance": proposed,
            }

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
        if carry_over_from is not None:
            result["carryOver"] = carry_over_from
        return result


@router.post("/cash-in", status_code=200)
def cash_in(body: CashMovementRequest):
    """FR2: owner puts cash into the active drawer.

    Creates a journal entry (debit 1100, credit 3100). FR8: stale previous-day
    drawers are auto-closed lazily before this operation.
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
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

    Creates a journal entry (debit 3100, credit 1100). FR8: stale previous-day
    drawers are auto-closed lazily before this operation.
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
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
    produces no additional journal entry. FR8: stale previous-day drawers
    are auto-closed lazily before this operation.
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
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
    """FR4: return the active (open) drawer with expected balance, or null.

    FR8: stale previous-day drawers are auto-closed lazily before this read.
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
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