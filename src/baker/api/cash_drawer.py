"""Cash drawer API routes (DG-324 Phase 2 / Phase 6; DG-330 Phase 3 / Phase 5).

Endpoints:
    POST /api/cash-drawer/open   — open a daily drawer (FR1, FR9 carry-over)
    POST /api/cash-drawer/close  — close with counted amount + discrepancy (FR7)
    POST /api/cash-drawer/cash-in  — owner puts cash in (FR2/FR3a, three sources)
    POST /api/cash-drawer/cash-out — owner takes cash out (FR3/FR4, two destinations)
    GET  /api/cash-drawer/status  — active drawer or null (FR4)
    GET  /api/cash-drawer/history — paginated past drawers (FR10)

Phase 6 (FR8/FR9): every drawer operation first runs a lazy auto-close check
that closes any open drawer whose ``opened_at`` belongs to a previous local
day, using ``expected_balance`` as the counted amount and ``discrepancy = 0``.
When opening, if a previous-day drawer was just auto-closed, its expected
balance is proposed as today's opening balance and the owner must confirm it
(``carryOverConfirmed`` flag).

DG-330 Phase 3: the cash side of every drawer journal entry now uses account
1101 (Cash in Drawer) instead of the main 1100 cash account, so 1101's balance
always equals the drawer's expected balance (NFR4). Cash-in accepts three
sources (owner cash 1102 / employee 23XX / equity 3100) and cash-out accepts
two destinations (owner cash 1102 / employee advance 23XX). All entries remain
balanced (NFR2), enforced by ``_insert_journal_entry``.

DG-330 Phase 5 (FR10/AC17): when opening a new day with carry-over confirmed
and the opening balance is less than the previous drawer's expected balance,
the difference auto-transfers from 1101 (Cash in Drawer) to 1102 (Owner's
Cash) via a balanced journal entry (DR 1102, CR 1101). This keeps 1101 in
sync with the drawer's expected balance (NFR4) — the excess cash physically
left the drawer and is now held by the owner personally.

Traceability: FR1, FR2, FR3, FR3a, FR4, FR7, FR8, FR9, FR10, FR10a, NFR1, NFR2, NFR4.
"""

import logging
from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from baker.config import TIMEZONE
from baker.db.connection import get_db
from baker.db.schema import (
    _account_id_by_code,
    _ensure_staff_payable_sub_account,
    _insert_journal_entry,
)
from baker.models.cash_drawer import (
    CashDrawer,
    CloseEditRequiresClosedDrawer,
    DrawerNotFound,
    DrawerReconciled,
    IntegrityError,
    InvalidAmount,
    InvalidTransactionType,
    TransactionNotFound,
)
from baker.models.journal_entry import JournalEntry, JournalLine
from baker.utils.time import now_utc

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/cash-drawer", tags=["cash-drawer"])

CASH_DRAWER_ASSET_CODE = "1101"  # Cash in Drawer (sub-account of 1100) — DG-330
OWNER_CASH_CODE = "1102"  # Owner's Cash (sub-account of 1100) — DG-330
EQUITY_CODE = "3100"
REVENUE_CODE = "4100"  # Doanh thu bán hàng
COGS_CODE = "5900"  # Giá vốn hàng bán
INVENTORY_CODE = "1300"  # Hàng tồn kho


def _get_account_balance(
    conn, account_code: str, drawer_id: int | None = None
) -> float:
    """Return the current balance for an account from journal lines.

    Asset/Expense accounts: balance = SUM(debit) - SUM(credit).

    When ``drawer_id`` is provided (DG-347 Phase 2, FR1/AC1), the journal lines
    are filtered via the ``cash_drawer_journal_entries`` join table so only
    lines linked to that drawer contribute to the balance.
    """
    if drawer_id is not None:
        row = conn.execute(
            """
            SELECT a.type,
                   COALESCE(SUM(jl.debit), 0) AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            JOIN journal_lines jl ON jl.account_id = a.id
            JOIN cash_drawer_journal_entries cdje
                 ON cdje.journal_entry_id = jl.journal_entry_id
            WHERE a.code = ? AND cdje.cash_drawer_id = ?
            GROUP BY a.id
            """,
            (account_code, drawer_id),
        ).fetchone()
    else:
        row = conn.execute(
            """
            SELECT a.type,
                   COALESCE(SUM(jl.debit), 0) AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM accounts a
            LEFT JOIN journal_lines jl ON jl.account_id = a.id
            WHERE a.code = ?
            GROUP BY a.id
            """,
            (account_code,),
        ).fetchone()
    if row is None:
        return 0.0
    debit = float(row["total_debit"])
    credit = float(row["total_credit"])
    if row["type"] in ("asset", "expense"):
        return debit - credit
    return credit - debit


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
    # DG-360 Phase 1: surplus/shortage proposal fields (mirror CloseDrawerRequest).
    # Replaces the old transferConfirmed/stockReconciliationConfirmed/
    # unidentifiedSaleConfirmed/ownerCapitalConfirmed fields.
    surplusConfirmed: bool = Field(
        False,
        description="Owner confirmed the surplus nature (DG-360). "
        "Required after a 409 surplusProposal when opening > 1101 reference.",
    )
    surplusSource: Optional[Literal["owner_cash", "unidentified_sale"]] = Field(
        None,
        description="Nature of the surplus: owner_cash → DR 1101/CR 1102; "
        "unidentified_sale → DR 1101/CR 4100 + DR 5900/CR 1300 (50% COGS). "
        "Required when surplusConfirmed is true.",
    )
    shortageConfirmed: bool = Field(
        False,
        description="Owner confirmed the shortage nature (DG-360). "
        "Required after a 409 shortageProposal when opening < 1101 reference.",
    )
    shortageSource: Optional[Literal["owner_withdraw", "equity_loss"]] = Field(
        None,
        description="Nature of the shortage: owner_withdraw → DR 1102/CR 1101; "
        "equity_loss → DR 3100/CR 1101. "
        "Required when shortageConfirmed is true.",
    )


class CloseDrawerRequest(BaseModel):
    countedAmount: int = Field(..., ge=0, description="Số tiền đếm thực tế (VND)")
    note: str = ""
    surplusConfirmed: bool = Field(
        False,
        description="Owner confirmed the surplus nature (DG-331). "
        "Required after a 409 surplusProposal.",
    )
    surplusSource: Optional[Literal["owner_cash", "unidentified_sale"]] = Field(
        None,
        description="Nature of the surplus: owner_cash → DR 1101/CR 1102; "
        "unidentified_sale → DR 1101/CR 4100 + DR 5900/CR 1300 (50% COGS). "
        "Required when surplusConfirmed is true.",
    )
    shortageConfirmed: bool = Field(
        False,
        description="Owner confirmed the shortage nature (DG-331). "
        "Required after a 409 shortageProposal.",
    )
    shortageSource: Optional[Literal["owner_withdraw", "equity_loss"]] = Field(
        None,
        description="Nature of the shortage: owner_withdraw → DR 1102/CR 1101; "
        "equity_loss → DR 3100/CR 1101. "
        "Required when shortageConfirmed is true.",
    )


class CashInRequest(BaseModel):
    """FR3a: cash-in supports three sources.

    - ``owner`` (default): DR 1101 / CR 1102 — owner moves personal cash into the drawer.
    - ``employee``: DR 1101 / CR 23XX — reduces the staff advance; ``staffName`` required.
    - ``equity``: DR 1101 / CR 3100 — owner capital injection.
    """

    amount: int = Field(..., gt=0, description="Số tiền (VND)")
    note: str = ""
    source: Literal["owner", "employee", "equity"] = Field(
        "equity",
        description="Nguồn tiền: owner (Tiền mặt chủ sở hữu — 1102), "
        "employee (Ứng trước nhân viên — 23XX, yêu cầu staffName), "
        "equity (Vốn chủ sở hữu — 3100). Mặc định: equity (tương thích ngược).",
    )
    staffName: Optional[str] = Field(
        None,
        description="Tên nhân viên — bắt buộc khi source='employee'. "
        "Sub-account 23XX được tạo lần đầu qua _ensure_staff_payable_sub_account.",
    )


class CashOutRequest(BaseModel):
    """FR4: cash-out supports two destinations.

    - ``owner`` (default): DR 1102 / CR 1101 — cash moves to the owner's personal cash.
    - ``employee``: DR 23XX / CR 1101 — pay an employee advance; ``staffName`` required.
    """

    amount: int = Field(..., gt=0, description="Số tiền (VND)")
    note: str = ""
    destination: Literal["owner", "employee"] = Field(
        "owner",
        description="Đích đến: owner (Tiền mặt chủ sở hữu — 1102, mặc định), "
        "employee (Ứng trước nhân viên — 23XX, yêu cầu staffName).",
    )
    staffName: Optional[str] = Field(
        None,
        description="Tên nhân viên — bắt buộc khi destination='employee'. "
        "Sub-account 23XX được tạo lần đầu qua _ensure_staff_payable_sub_account.",
    )


class EditTransactionRequest(BaseModel):
    """DG-379 Phase 4.2 (FR1-FR3): edit an open/close transaction's amount
    and/or notes.

    Both fields are optional — send only ``amount`` to edit the amount, only
    ``notes`` to edit the description, or both. ``amount`` must be > 0 when
    provided.
    """

    amount: Optional[int] = Field(
        None,
        gt=0,
        description="Số tiền mới (VND) — phải > 0. Bỏ qua để giữ nguyên amount.",
    )
    notes: Optional[str] = Field(
        None,
        description="Ghi chú mới cho giao dịch (cập nhật journal description). "
        "Bỏ qua để giữ nguyên notes.",
    )


# ---------------------------------------------------------------------------
# Journal helpers (reuse _insert_journal_entry + account resolver pattern)
# ---------------------------------------------------------------------------


def _cash_and_equity_accounts(conn) -> dict[str, int]:
    return {
        "cash_drawer": _account_id_by_code(conn, CASH_DRAWER_ASSET_CODE),
        "owner_cash": _account_id_by_code(conn, OWNER_CASH_CODE),
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
    drawer_id: int | None = None,
) -> dict:
    """Insert a balanced double-entry journal entry for a drawer operation.

    NFR3: enforced by ``_insert_journal_entry`` (raises on debit != credit).
    When ``drawer_id`` is provided (DG-347 Phase 2, FR4), the entry is linked
    to the drawer via the ``cash_drawer_journal_entries`` join table so its
    1101 lines contribute to that drawer's ``expected_balance``.
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
        drawer_id=drawer_id,
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

    Creates a journal entry (debit 1101 Cash in Drawer, credit 3100 equity).
    Only one active drawer may exist at a time (NFR2/single-active-drawer rule).

    FR9 carry-over: if a previous-day drawer is still open, the system
    proposes that drawer's expected balance as today's opening balance and
    requires the owner to confirm it (``carryOverConfirmed``). On confirmation
    the stale drawer is auto-closed (FR8) and today's drawer is opened with
    the requested amount.

    DG-330 reference balance: the 1101 accounting balance is shown as a
    reference. When ``openingBalance < 1101_balance`` the owner must confirm
    the transfer of the difference to 1102 (owner's cash). When
    ``openingBalance > 1101_balance`` the owner must confirm stock
    reconciliation. On confirmation the drawer opens; any excess auto-transfers
    to 1102.
    """
    with get_db() as conn:
        # Resolve the accounting reference balance.
        reference_balance = _get_account_balance(conn, CASH_DRAWER_ASSET_CODE)
        opening = int(body.openingBalance)

        # FR9: detect unclosed previous-day drawers before opening.
        stale = CashDrawer.get_stale_open_before(
            conn, before_iso=_start_of_today_local_iso()
        )
        carry_over_from = None
        if stale:
            latest = stale[-1]
            proposed = latest.expected_balance(conn)
            # Override the accounting reference with the drawer's expected
            # balance when a stale drawer exists (they should be in sync per
            # NFR4, but the drawer is the authoritative source on carry-over).
            reference_balance = proposed
            if not body.carryOverConfirmed:
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
                        "referenceBalance": proposed,
                    },
                )
            # Owner confirmed — auto-close every stale drawer (FR8), then open.
            for drawer in stale:
                drawer.auto_close(conn)
            carry_over_from = {
                "fromDrawerId": str(latest.id),
                "fromExpectedBalance": proposed,
            }

        # Reject when there is already an active drawer (NFR2). This MUST run
        # before the transfer/excess confirmation gates so the "already open"
        # error takes priority over the reference-balance proposals.
        active = CashDrawer.get_active(conn)
        if active is not None:
            raise HTTPException(
                status_code=409,
                detail="Đã có quầy tiền mặt đang mở — phải đóng quầy hiện tại trước khi mở quầy mới.",
            )

        # DG-360 Phase 1: surplus/shortage proposal gates (replaces the old
        # transfer/excess/unidentified-sale gates). These mirror the close
        # drawer confirmation flow and run for ANY non-zero reference_balance
        # (positive OR negative) so 1101 ≤ 0 is no longer skipped. The first
        # open (reference_balance == 0) books the full counted opening without a
        # proposal (FR6). Carry-over confirmation (FR9) implies consent — the
        # owner already acknowledged the previous-day balance, so the proposal
        # step is skipped and the delta is booked directly (defaults:
        # surplus → equity injection, shortage → owner-withdraw).
        if carry_over_from is None and reference_balance != 0:
            delta = opening - int(reference_balance)
            if delta > 0 and not body.surplusConfirmed:
                logger.warning(
                    "open_drawer surplus proposal: drawer=None "
                    "reference=%s opening=%s surplus=%s",
                    int(reference_balance), opening, delta,
                )
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            f"Chênh lệch thừa {delta:,} VND. "
                            f"Số dư kế toán 1101: {int(reference_balance):,}. "
                            f"Số tiền mở quầy: {opening:,}. "
                            f"Chủ thêm tiền mặt hay doanh thu chưa xác định?"
                        ),
                        "surplusProposal": {
                            "referenceBalance": int(reference_balance),
                            "openingBalance": opening,
                            "surplus": delta,
                        },
                    },
                )
            if delta < 0 and not body.shortageConfirmed:
                amt = abs(delta)
                logger.warning(
                    "open_drawer shortage proposal: drawer=None "
                    "reference=%s opening=%s shortage=%s",
                    int(reference_balance), opening, amt,
                )
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            f"Chênh lệch thiếu {amt:,} VND. "
                            f"Số dư kế toán 1101: {int(reference_balance):,}. "
                            f"Số tiền mở quầy: {opening:,}. "
                            f"Chủ rút tiền hay lỗ vốn chủ sở hữu?"
                        ),
                        "shortageProposal": {
                            "referenceBalance": int(reference_balance),
                            "openingBalance": opening,
                            "shortage": amt,
                        },
                    },
                )

        accounts = _cash_and_equity_accounts(conn)
        # DG-354 Phase 3 (FR1/FR2): opening_balance stores the 1101 accounting
        # reference at open time (not the user input); counted_opening_balance
        # stores the user's physical cash count. The open journal entry books
        # the delta (or full opening when reference==0) linked to this drawer.
        # expected_balance() = opening_balance + SUM(linked 1101) then equals
        # the user's requested amount because the linked open entry bridges the
        # gap between the 1101 reference and the counted opening balance.
        drawer = CashDrawer(
            opened_at=now_utc(),
            opening_balance=int(reference_balance),
            counted_opening_balance=opening,
        )
        drawer.save(conn)

        # DG-360 Phase 1 (FR8): only book the delta between opening and
        # reference_balance. When reference_balance == 0 (first open) the full
        # counted opening is booked as DR 1101 / CR 3100. When reference_balance
        # != 0 (positive OR negative) only the delta is booked:
        #
        #   delta > 0 (surplus)  → DR 1101 for delta; nature chosen by surplusSource
        #   delta < 0 (shortage) → CR 1101 for |delta|; nature chosen by shortageSource
        #   delta == 0           → no journal entry (1101 already at target)
        journal = None
        surplus_result = None
        delta = opening - int(reference_balance)
        if int(reference_balance) == 0:
            desc = f"Mở quầy tiền mặt: {opening}"
            if body.note:
                desc += f" — {body.note}"
            journal = _create_drawer_journal_entry(
                conn,
                source_type="cash_drawer_open",
                description=desc,
                debit_account_id=accounts["cash_drawer"],
                credit_account_id=accounts["equity"],
                amount=opening,
                drawer_id=drawer.id,
            )
        elif delta > 0:
            desc = (
                f"Mở quầy tiền mặt: {opening} (chênh lệch tăng {delta})"
            )
            if body.note:
                desc += f" — {body.note}"
            if body.surplusSource == "owner_cash":
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_open",
                    description=desc,
                    debit_account_id=accounts["cash_drawer"],
                    credit_account_id=accounts["owner_cash"],
                    amount=delta,
                    drawer_id=drawer.id,
                )
            elif body.surplusSource == "unidentified_sale":
                cogs = int(delta * 0.5)
                revenue_acct = _account_id_by_code(conn, REVENUE_CODE)
                cogs_acct = _account_id_by_code(conn, COGS_CODE)
                inventory_acct = _account_id_by_code(conn, INVENTORY_CODE)
                sale_desc = (
                    f"Doanh thu chưa xác định khi mở quầy: {delta}"
                )
                lines = [
                    (accounts["cash_drawer"], float(delta), 0.0, sale_desc),
                    (revenue_acct, 0.0, float(delta), sale_desc),
                    (cogs_acct, float(cogs), 0.0, f"Giá vốn 50%: {cogs}"),
                    (inventory_acct, 0.0, float(cogs), f"Giá vốn 50%: {cogs}"),
                ]
                entry_id = _insert_journal_entry(
                    conn,
                    description=sale_desc,
                    source_type="cash_drawer_open",
                    source_id=None,
                    lines=lines,
                    transaction_date=now_utc(),
                    drawer_id=drawer.id,
                )
                entry = JournalEntry.from_row(
                    conn.execute(
                        "SELECT * FROM journal_entries WHERE id = ?",
                        (entry_id,),
                    ).fetchone()
                )
                fetched_lines = JournalLine.list_for_entry(conn, entry_id)
                surplus_result = entry.to_api_dict(fetched_lines)
            else:
                # Default to equity injection (owner capital) when surplus
                # is confirmed but no source picked — backward compatible with
                # the pre-DG-360 plain delta booking.
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_open",
                    description=desc,
                    debit_account_id=accounts["cash_drawer"],
                    credit_account_id=accounts["equity"],
                    amount=delta,
                    drawer_id=drawer.id,
                )
        elif delta < 0:
            amt = abs(delta)
            desc = (
                f"Mở quầy tiền mặt: {opening} (chênh lệch giảm {amt})"
            )
            if body.note:
                desc += f" — {body.note}"
            if body.shortageSource == "owner_withdraw":
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_open",
                    description=desc,
                    debit_account_id=accounts["owner_cash"],
                    credit_account_id=accounts["cash_drawer"],
                    amount=amt,
                    drawer_id=drawer.id,
                )
            elif body.shortageSource == "equity_loss":
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_open",
                    description=desc,
                    debit_account_id=accounts["equity"],
                    credit_account_id=accounts["cash_drawer"],
                    amount=amt,
                    drawer_id=drawer.id,
                )
            else:
                # Default to owner-withdraw (DR 1102 / CR 1101) when shortage
                # is confirmed but no source picked — backward compatible with
                # the pre-DG-360 auto-transfer behavior.
                journal = _create_drawer_journal_entry(
                    conn,
                    source_type="cash_drawer_open",
                    description=desc,
                    debit_account_id=accounts["owner_cash"],
                    credit_account_id=accounts["cash_drawer"],
                    amount=amt,
                    drawer_id=drawer.id,
                )
        # delta == 0 → no journal entry (1101 already at target)
        result = drawer.to_api_dict(conn)
        if journal is not None:
            result["journalEntry"] = journal
        if carry_over_from is not None:
            result["carryOver"] = carry_over_from
        if surplus_result is not None:
            result["surplusJournalEntry"] = surplus_result
        return result


@router.post("/cash-in", status_code=200)
def cash_in(body: CashInRequest):
    """FR2/FR3a: owner (or staff/equity) puts cash into the active drawer.

    Journal entry depends on ``source`` (DG-330 Phase 3):
    - ``owner``  → DR 1101 (Cash in Drawer) / CR 1102 (Owner's Cash)
    - ``employee`` → DR 1101 / CR 23XX (staff sub-account; created on first use)
    - ``equity`` → DR 1101 / CR 3100 (Owner's Equity / capital injection)

    Defaults to ``equity`` for backward compatibility with pre-DG-330 clients
    that POST only ``{amount, note}``. FR8: stale previous-day drawers are
    auto-closed lazily before this operation.
    """
    if body.source == "employee" and not body.staffName:
        raise HTTPException(
            status_code=422,
            detail="source='employee' yêu cầu staffName (tên nhân viên).",
        )
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
        drawer = _require_active_drawer(conn)
        accounts = _cash_and_equity_accounts(conn)
        desc = f"Cho thêm tiền vào quầy: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        # Resolve the credit account based on the source.
        if body.source == "owner":
            credit_account_id = accounts["owner_cash"]
        elif body.source == "employee":
            credit_account_id = _ensure_staff_payable_sub_account(conn, body.staffName)
        else:  # equity
            credit_account_id = accounts["equity"]
        journal = _create_drawer_journal_entry(
            conn,
            source_type="cash_drawer_cash_in",
            description=desc,
            debit_account_id=accounts["cash_drawer"],
            credit_account_id=credit_account_id,
            amount=body.amount,
            drawer_id=drawer.id,
        )
        result = drawer.to_api_dict(conn)
        result["journalEntry"] = journal
        return result


@router.post("/cash-out", status_code=200)
def cash_out(body: CashOutRequest):
    """FR3/FR4: owner takes cash out of the active drawer.

    Journal entry depends on ``destination`` (DG-330 Phase 3):
    - ``owner`` (default) → DR 1102 (Owner's Cash) / CR 1101 (Cash in Drawer)
    - ``employee`` → DR 23XX (staff sub-account; created on first use) / CR 1101

    Defaults to ``owner`` for backward compatibility with pre-DG-330 clients
    that POST only ``{amount, note}``. FR8: stale previous-day drawers are
    auto-closed lazily before this operation.
    """
    if body.destination == "employee" and not body.staffName:
        raise HTTPException(
            status_code=422,
            detail="destination='employee' yêu cầu staffName (tên nhân viên).",
        )
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
        drawer = _require_active_drawer(conn)
        accounts = _cash_and_equity_accounts(conn)
        desc = f"Lấy tiền khỏi quầy: {body.amount}"
        if body.note:
            desc += f" — {body.note}"
        # Resolve the debit account based on the destination.
        if body.destination == "owner":
            debit_account_id = accounts["owner_cash"]
        else:  # employee
            debit_account_id = _ensure_staff_payable_sub_account(conn, body.staffName)
        journal = _create_drawer_journal_entry(
            conn,
            source_type="cash_drawer_cash_out",
            description=desc,
            debit_account_id=debit_account_id,
            credit_account_id=accounts["cash_drawer"],
            amount=body.amount,
            drawer_id=drawer.id,
        )
        result = drawer.to_api_dict(conn)
        result["journalEntry"] = journal
        return result


@router.post("/close", status_code=200)
def close_drawer(body: CloseDrawerRequest):
    """FR7: close the active drawer with a physical cash count.

    Computes discrepancy = counted - expected.

    DG-331 confirmation gates (FR1-FR8, AC1-AC7):
    - Surplus (counted > expected) and no confirmation: return 409 with surplusProposal.
    - Surplus + owner_cash: DR 1101 / CR 1102.
    - Surplus + unidentified_sale: DR 1101 / CR 4100 + DR 5900 / CR 1300 (50% COGS).
    - Shortage (counted < expected) and no confirmation: return 409 with shortageProposal.
    - Shortage + owner_withdraw: DR 1102 / CR 1101.
    - Shortage + equity_loss: DR 3100 / CR 1101.
    - Zero discrepancy: no journal entry, no confirmation required.
    - Backward compatible (NFR2): old clients without flags get the legacy
      behavior (surplus → DR 1101/CR 3100, shortage → DR 3100/CR 1101).

    DG-330 Phase 3: the cash side uses account 1101 (Cash in Drawer) so the
    1101 balance equals the drawer expected balance at all times (NFR4).
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
        drawer = _require_active_drawer(conn)
        accounts = _cash_and_equity_accounts(conn)
        expected = drawer.expected_balance(conn)
        discrepancy = drawer.close(conn, counted_amount=body.countedAmount)
        journal = None
        surplus_result = None

        if discrepancy > 0:
            if not body.surplusConfirmed:
                logger.warning(
                    "close_drawer surplus proposal: drawer=%s expected=%s "
                    "counted=%s surplus=%s",
                    drawer.id, expected, body.countedAmount, discrepancy,
                )
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            f"Chênh lệch thừa {discrepancy:,} VND. "
                            f"Số dư dự kiến: {expected:,}. "
                            f"Số tiền đếm thực tế: {body.countedAmount:,}. "
                            f"Chủ thêm tiền mặt hay doanh thu chưa xác định?"
                        ),
                        "surplusProposal": {
                            "expectedBalance": expected,
                            "countedAmount": body.countedAmount,
                            "surplus": discrepancy,
                        },
                    },
                )
            else:
                desc = (
                    f"Đóng quầy tiền mặt: đếm={body.countedAmount}, "
                    f"chênh lệch={discrepancy}"
                )
                if body.note:
                    desc += f" — {body.note}"
                if body.surplusSource == "owner_cash":
                    journal = _create_drawer_journal_entry(
                        conn,
                        source_type="cash_drawer_close_adjust",
                        description=desc,
                        debit_account_id=accounts["cash_drawer"],
                        credit_account_id=accounts["owner_cash"],
                        amount=discrepancy,
                        drawer_id=drawer.id,
                    )
                elif body.surplusSource == "unidentified_sale":
                    cogs = int(discrepancy * 0.5)
                    revenue_acct = _account_id_by_code(conn, REVENUE_CODE)
                    cogs_acct = _account_id_by_code(conn, COGS_CODE)
                    inventory_acct = _account_id_by_code(conn, INVENTORY_CODE)
                    sale_desc = (
                        f"Doanh thu chưa xác định khi đóng quầy: {discrepancy}"
                    )
                    lines = [
                        (accounts["cash_drawer"], float(discrepancy), 0.0, sale_desc),
                        (revenue_acct, 0.0, float(discrepancy), sale_desc),
                        (cogs_acct, float(cogs), 0.0, f"Giá vốn 50%: {cogs}"),
                        (inventory_acct, 0.0, float(cogs), f"Giá vốn 50%: {cogs}"),
                    ]
                    entry_id = _insert_journal_entry(
                        conn,
                        description=sale_desc,
                        source_type="cash_drawer_close_adjust",
                        source_id=None,
                        lines=lines,
                        transaction_date=now_utc(),
                        drawer_id=drawer.id,
                    )
                    entry = JournalEntry.from_row(
                        conn.execute(
                            "SELECT * FROM journal_entries WHERE id = ?",
                            (entry_id,),
                        ).fetchone()
                    )
                    fetched_lines = JournalLine.list_for_entry(conn, entry_id)
                    surplus_result = entry.to_api_dict(fetched_lines)
        elif discrepancy < 0:
            amt = abs(discrepancy)
            if not body.shortageConfirmed:
                logger.warning(
                    "close_drawer shortage proposal: drawer=%s expected=%s "
                    "counted=%s shortage=%s",
                    drawer.id, expected, body.countedAmount, amt,
                )
                raise HTTPException(
                    status_code=409,
                    detail={
                        "message": (
                            f"Chênh lệch thiếu {amt:,} VND. "
                            f"Số dư dự kiến: {expected:,}. "
                            f"Số tiền đếm thực tế: {body.countedAmount:,}. "
                            f"Chủ rút tiền hay lỗ vốn chủ sở hữu?"
                        ),
                        "shortageProposal": {
                            "expectedBalance": expected,
                            "countedAmount": body.countedAmount,
                            "shortage": amt,
                        },
                    },
                )
            else:
                desc = (
                    f"Đóng quầy tiền mặt: đếm={body.countedAmount}, "
                    f"chênh lệch={discrepancy}"
                )
                if body.note:
                    desc += f" — {body.note}"
                if body.shortageSource == "owner_withdraw":
                    journal = _create_drawer_journal_entry(
                        conn,
                        source_type="cash_drawer_close_adjust",
                        description=desc,
                        debit_account_id=accounts["owner_cash"],
                        credit_account_id=accounts["cash_drawer"],
                        amount=amt,
                        drawer_id=drawer.id,
                    )
                elif body.shortageSource == "equity_loss":
                    journal = _create_drawer_journal_entry(
                        conn,
                        source_type="cash_drawer_close_adjust",
                        description=desc,
                        debit_account_id=accounts["equity"],
                        credit_account_id=accounts["cash_drawer"],
                        amount=amt,
                        drawer_id=drawer.id,
                    )
        # Zero discrepancy: no journal entry, no confirmation required (FR8).
        result = drawer.to_api_dict(conn)
        if journal is not None:
            result["journalEntry"] = journal
        if surplus_result is not None:
            result["surplusJournalEntry"] = surplus_result
        return result


@router.get("/status")
def drawer_status():
    """FR4: return the active (open) drawer with expected balance, or null.

    FR8: stale previous-day drawers are auto-closed lazily before this read.
    DG-331 FR9: includes previousCloseCountedAmount (counted_amount of most
    recent closed drawer) when no active drawer exists, for display in the
    open dialog as "Số dư sau khi đóng quầy lần trước".
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
        drawer = CashDrawer.get_active(conn)
        # DG-347 Phase 4 (FR11/AC10): accountingBalance1101 is the global 1101
        # balance (unchanged). expectedBalance is derived per-drawer via the
        # join table (open) or from closing_balance (closed) by the model. For
        # an open single-active drawer both values are equal because all 1101
        # journal lines are linked to that drawer.
        accounting_balance_1101 = int(_get_account_balance(conn, CASH_DRAWER_ASSET_CODE))
        if drawer:
            result = drawer.to_api_dict(conn)
            result["accountingBalance1101"] = accounting_balance_1101
            # DG-363 Phase 2 (FR7): include the breakdown snapshot when the
            # active drawer is closed (defensive — the active drawer is
            # normally open, but if it is closed the client can render the
            # snapshot directly). Open drawers return an empty list; the
            # client aggregates breakdown live from transactions (Phase 3).
            result["breakdownSnapshot"] = (
                CashDrawer.get_breakdown_snapshot(conn, drawer.id)
                if drawer.status == "closed"
                else []
            )
            return result
        recent = CashDrawer.get_most_recent_closed(conn)
        if recent:
            data = {"activeDrawer": None}
            data["previousCloseCountedAmount"] = recent.counted_amount
            data["accountingBalance1101"] = accounting_balance_1101
            data["breakdownSnapshot"] = CashDrawer.get_breakdown_snapshot(
                conn, recent.id
            )
            return data
        # FR3 (DG-337 phase 4.1): always return accountingBalance1101, even when
        # no active drawer and no closed-drawer history exist, so the client
        # never receives a null balance display.
        return {
            "activeDrawer": None,
            "previousCloseCountedAmount": None,
            "accountingBalance1101": accounting_balance_1101,
            "breakdownSnapshot": [],
        }


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
        items = []
        for d in drawers:
            item = d.to_api_dict(conn)
            # DG-363 Phase 2 (FR7): embed the breakdown snapshot for each
            # closed drawer so the History tab renders the breakdown from
            # the snapshot (source of truth) without re-aggregating journal
            # entries (NFR1). Open drawers return an empty list.
            item["breakdownSnapshot"] = (
                CashDrawer.get_breakdown_snapshot(conn, d.id)
                if d.status == "closed"
                else []
            )
            items.append(item)
        return {
            "total": total,
            "limit": limit,
            "offset": offset,
            "items": items,
        }


@router.get("/{drawer_id}/transactions")
def drawer_transactions(
    drawer_id: int,
    limit: int = Query(50, ge=1, le=500, description="Số kết quả tối đa"),
    offset: int = Query(0, ge=0, description="Bỏ qua bao nhiêu kết quả"),
):
    """FR1/FR2 (DG-343 Phase 1): unified, paginated list of all cash
    transactions for a given drawer, ordered newest-first.

    Each item includes ``type`` (journal source_type), ``amount`` (signed:
    + for inflow, - for outflow, derived from the net 1101 movement),
    ``timestamp`` (transaction_date fallback to created_at), ``note``
    (journal description), and — as of Phase 4 — ``reference`` and
    ``reference_detail`` describing the originating document. For
    ``payment_transaction`` rows, ``reference`` is the order receiving code
    and ``reference_detail`` the customer name; for ``expense`` rows,
    ``reference`` is the event summary and ``reference_detail`` the
    "staff_name — payment_source" string parsed from the event JSON. Cash
    operations that do not touch 1101 (bank transfers, card payments) are
    excluded.
    """
    with get_db() as conn:
        # Validate the drawer exists; 404 if not.
        drawer = CashDrawer.get_by_id(conn, drawer_id)
        if drawer is None:
            raise HTTPException(
                status_code=404,
                detail=f"Không tìm thấy quầy tiền mặt id={drawer_id}.",
            )
        items, total = CashDrawer.get_transactions(
            conn, drawer_id, limit=limit, offset=offset
        )
        return {
            "total": total,
            "limit": limit,
            "offset": offset,
            "items": items,
        }


@router.patch("/{drawer_id}/transactions/{entry_id}", status_code=200)
def edit_transaction(
    drawer_id: int,
    entry_id: int,
    body: EditTransactionRequest,
):
    """DG-379 Phase 4.2 (FR1-FR5, AC1-AC4): edit an open/close transaction's
    amount and/or notes in-place.

    - Updates ``journal_entries.description`` (notes) in-place (FR3).
    - Updates ``journal_lines.debit``/``credit`` (amount) in-place (FR1/FR2).
    - Recalculates ``closing_balance``, ``counted_amount``, ``discrepancy`` and
      regenerates the breakdown snapshot when editing a close transaction (FR5/FR6).
    - All updates run in a single DB transaction (FR9, NFR2: debit == credit).
    - 409 if the drawer is reconciled (FR7); 404 if drawer or entry missing;
      400 if the entry is not an open/close type or amount <= 0.
    """
    if body.amount is None and body.notes is None:
        raise HTTPException(
            status_code=400,
            detail="Phải cung cấp ít nhất một trường: amount hoặc notes.",
        )
    with get_db() as conn:
        try:
            result = CashDrawer.edit_transaction(
                conn,
                drawer_id,
                entry_id,
                amount=body.amount,
                notes=body.notes,
            )
        except DrawerNotFound as exc:
            raise HTTPException(
                status_code=404,
                detail=f"Không tìm thấy quầy tiền mặt id={exc.drawer_id}.",
            ) from exc
        except DrawerReconciled as exc:
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Quầy tiền mặt id={exc.drawer_id} đã được đối soát (reconciled) — "
                    "không thể sửa giao dịch."
                ),
            ) from exc
        except TransactionNotFound as exc:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"Không tìm thấy giao dịch id={exc.entry_id} "
                    f"thuộc quầy id={exc.drawer_id}."
                ),
            ) from exc
        except InvalidTransactionType as exc:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Không thể sửa giao dịch loại '{exc.source_type}'. "
                    "Chỉ giao dịch Mở quầy (cash_drawer_open) và Đóng quầy "
                    "(cash_drawer_close_adjust) mới có thể sửa."
                ),
            ) from exc
        except CloseEditRequiresClosedDrawer as exc:
            raise HTTPException(
                status_code=409,
                detail=(
                    f"Không thể sửa giao dịch đóng quầy khi quầy id={exc.drawer_id} "
                    "vẫn đang mở."
                ),
            ) from exc
        except InvalidAmount as exc:
            raise HTTPException(
                status_code=400,
                detail=f"Số tiền phải > 0 (nhận được {exc.amount}).",
            ) from exc
        except IntegrityError as exc:
            logger.error("edit_transaction integrity error: %s (%s)", exc.entry_id, exc.reason)
            raise HTTPException(
                status_code=500,
                detail="Lỗi toàn vẹn dữ liệu — vui lòng liên hệ hỗ trợ.",
            ) from exc
        return result


@router.patch("/{drawer_id}/reconcile", status_code=200)
def reconcile_drawer(drawer_id: int):
    """DG-379 Phase 4.2 (FR8, AC6): mark a drawer as reconciled.

    Sets ``cash_drawer.reconciled = 1`` so further transaction edits are
    rejected with 409. Idempotent — re-reconciling an already-reconciled
    drawer is a no-op and returns 200.
    """
    with get_db() as conn:
        try:
            reconciled = CashDrawer.reconcile(conn, drawer_id)
        except DrawerNotFound as exc:
            raise HTTPException(
                status_code=404,
                detail=f"Không tìm thấy quầy tiền mặt id={exc.drawer_id}.",
            ) from exc
        return {
            "id": str(drawer_id),
            "reconciled": bool(reconciled),
        }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _require_active_drawer(conn) -> CashDrawer:
    drawer = CashDrawer.get_active(conn)
    if drawer is None:
        raise HTTPException(
            status_code=409,
            detail="Không có quầy tiền mặt đang mở — hãy mở quầy trước.",
        )
    return drawer