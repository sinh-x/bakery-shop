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
from baker.models.cash_drawer import CashDrawer
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


def _get_account_balance(conn, account_code: str) -> float:
    """Return the current balance for an account from journal lines.

    Asset/Expense accounts: balance = SUM(debit) - SUM(credit).
    """
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
    transferConfirmed: bool = Field(
        False,
        description="Owner confirms the difference between opening balance and "
        "accounting 1101 balance should transfer to 1102 (owner's cash). "
        "Required when openingBalance < 1101 reference balance.",
    )
    stockReconciliationConfirmed: bool = Field(
        False,
        description="Owner confirms stock reconciliation is complete — the "
        "extra cash above the accounting 1101 balance is legitimate from POS "
        "sales. Required when openingBalance > 1101 reference balance.",
    )
    unidentifiedSaleConfirmed: bool = Field(
        False,
        description="Owner confirms the excess should be recorded as an "
        "unidentified sale with 50% COGS markup. Creates journal entry "
        "DR 1101 / CR 4100 (revenue) + DR 5900 / CR 1300 (50% COGS). "
        "Only valid when stockReconciliationConfirmed is true.",
    )
    ownerCapitalConfirmed: bool = Field(
        False,
        description="Owner confirms the excess is personal cash injected "
        "into the shop (owner capital / equity). Creates journal entry "
        "DR 1101 / CR 3100 for the excess. Only used when "
        "openingBalance > 1101 reference balance.",
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
            proposed = latest.expected_balance()
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
                detail="Đã có quỹ tiền mặt đang mở — phải đóng quỹ hiện tại trước khi mở quỹ mới.",
            )

        # DG-330 confirmation gates for non-carry-over cases (or post-carry-over
        # confirmed). Guards run when we have a reference balance to compare
        # against and the user has not yet confirmed the specific gate.
        # Carry-over confirmation (FR9) implies transfer consent — the owner
        # already acknowledged the previous-day balance, so auto-transfer
        # proceeds without an extra confirmation step.
        if carry_over_from is None or body.carryOverConfirmed:
            if reference_balance > 0:
                if (opening < reference_balance and not body.transferConfirmed
                        and carry_over_from is None):
                    excess = int(reference_balance - opening)
                    raise HTTPException(
                        status_code=409,
                        detail={
                            "message": (
                                f"Số tiền mở quỹ ({opening:,}) thấp hơn số dư "
                                f"kế toán 1101 ({int(reference_balance):,}). "
                                f"Chênh lệch {excess:,} sẽ chuyển vào "
                                f"Tiền mặt chủ sở hữu (1102). Xác nhận?"
                            ),
                            "transferProposal": {
                                "referenceBalance": int(reference_balance),
                                "openingBalance": opening,
                                "excess": excess,
                            },
                            "referenceBalance": int(reference_balance),
                        },
                    )
                if opening > reference_balance and reference_balance > 0 and not body.stockReconciliationConfirmed and not body.ownerCapitalConfirmed and carry_over_from is None:
                    excess = int(opening - reference_balance)
                    raise HTTPException(
                        status_code=409,
                        detail={
                            "message": (
                                f"Số tiền mở quỹ ({opening:,}) cao hơn số dư "
                                f"kế toán 1101 ({int(reference_balance):,}). "
                                f"Chênh lệch {excess:,}. Xác nhận đã đối chiếu "
                                f"kho hàng POS?"
                            ),
                            "excessProposal": {
                                "referenceBalance": int(reference_balance),
                                "openingBalance": opening,
                                "excess": excess,
                            },
                            "referenceBalance": int(reference_balance),
                        },
                    )
                if opening > reference_balance and reference_balance > 0 and body.stockReconciliationConfirmed and not body.unidentifiedSaleConfirmed and carry_over_from is None:
                    excess = int(opening - reference_balance)
                    raise HTTPException(
                        status_code=409,
                        detail={
                            "message": (
                                f"Chênh lệch {excess:,} VND. Ghi nhận thành "
                                f"doanh thu chưa xác định với 50% giá vốn?"
                            ),
                            "unidentifiedSaleProposal": {
                                "referenceBalance": int(reference_balance),
                                "openingBalance": opening,
                                "excess": excess,
                                "cogsPct": 50,
                            },
                            "referenceBalance": int(reference_balance),
                        },
                    )

        accounts = _cash_and_equity_accounts(conn)
        drawer = CashDrawer(opened_at=now_utc(), opening_balance=opening)
        drawer.save(conn)

        # DG-330: when opening balance < accounting 1101 reference, the excess
        # moved from drawer to owner's cash (1102). Since 1101 already holds the
        # reference balance from migration/prior entries, we only create the
        # auto-transfer (DR 1102 / CR 1101 = excess). No open journal entry is
        # created — the 1101 position was already established by prior entries
        # and the auto-transfer adjusts it down to the opening balance.
        # 1101 = reference - excess + 0 (no open DR) = opening.
        auto_transfer = None
        if reference_balance > 0 and opening < reference_balance:
            excess = int(reference_balance - opening)
            transfer_desc = (
                f"Chuyển tiền thừa từ quỹ sang tiền mặt chủ sở hữu: {excess}"
            )
            auto_transfer = _create_drawer_journal_entry(
                conn,
                source_type="cash_drawer_auto_transfer",
                description=transfer_desc,
                debit_account_id=accounts["owner_cash"],
                credit_account_id=accounts["cash_drawer"],
                amount=excess,
            )
            journal = None
        else:
            # Normal open — no prior 1101 adjustment needed.
            desc = f"Mở quỹ tiền mặt: {opening}"
            if body.note:
                desc += f" — {body.note}"
            journal = _create_drawer_journal_entry(
                conn,
                source_type="cash_drawer_open",
                description=desc,
                debit_account_id=accounts["cash_drawer"],
                credit_account_id=accounts["equity"],
                amount=opening,
            )
        # DG-330: unidentified sale — when opening balance exceeds the
        # accounting 1101 balance and the owner confirms stock reconciliation
        # AND chooses to record as an unidentified sale. Creates a balanced
        # journal entry: DR 1101 / CR 4100 (revenue) + DR 5900 / CR 1300
        # (50% COGS). Uses source_type="unidentified_sale" for easy
        # identification and future allocation.
        unidentified_sale = None
        if opening > reference_balance > 0 and body.unidentifiedSaleConfirmed:
            excess = int(opening - reference_balance)
            cogs = int(excess * 0.5)
            revenue_acct = _account_id_by_code(conn, REVENUE_CODE)
            cogs_acct = _account_id_by_code(conn, COGS_CODE)
            inventory_acct = _account_id_by_code(conn, INVENTORY_CODE)
            sale_desc = (
                f"Doanh thu chưa xác định khi mở quỹ (đã đối chiếu kho): {excess}"
            )
            sale_lines = [
                (accounts["cash_drawer"], float(excess), 0.0, sale_desc),
                (revenue_acct, 0.0, float(excess), sale_desc),
                (cogs_acct, float(cogs), 0.0, f"Giá vốn 50%: {cogs}"),
                (inventory_acct, 0.0, float(cogs), f"Giá vốn 50%: {cogs}"),
            ]
            sale_entry_id = _insert_journal_entry(
                conn,
                description=sale_desc,
                source_type="unidentified_sale",
                source_id=None,
                lines=sale_lines,
                transaction_date=now_utc(),
            )
            sale_entry = JournalEntry.from_row(
                conn.execute(
                    "SELECT * FROM journal_entries WHERE id = ?", (sale_entry_id,)
                ).fetchone()
            )
            fetched_lines = JournalLine.list_for_entry(conn, sale_entry_id)
            unidentified_sale = sale_entry.to_api_dict(fetched_lines)
        # DG-330: owner capital injection — when opening balance exceeds the
        # accounting 1101 balance and the owner chooses to record the excess
        # as personal cash injected into the shop. Creates journal entry
        # DR 1101 / CR 3100 for the excess.
        owner_capital = None
        if opening > reference_balance > 0 and body.ownerCapitalConfirmed:
            excess = int(opening - reference_balance)
            capital_desc = (
                f"Chủ cho thêm tiền mặt khi mở quỹ (vốn chủ sở hữu): {excess}"
            )
            owner_capital = _create_drawer_journal_entry(
                conn,
                source_type="cash_drawer_owner_capital",
                description=capital_desc,
                debit_account_id=accounts["cash_drawer"],
                credit_account_id=accounts["equity"],
                amount=excess,
            )
        result = drawer.to_api_dict()
        if journal is not None:
            result["journalEntry"] = journal
        if carry_over_from is not None:
            result["carryOver"] = carry_over_from
        if auto_transfer is not None:
            result["autoTransfer"] = auto_transfer
        if unidentified_sale is not None:
            result["unidentifiedSale"] = unidentified_sale
        if owner_capital is not None:
            result["ownerCapital"] = owner_capital
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
        drawer.add_owner_in(conn, body.amount)
        desc = f"Cho thêm tiền vào quỹ: {body.amount}"
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
        )
        result = drawer.to_api_dict()
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
        drawer.add_owner_out(conn, body.amount)
        desc = f"Lấy tiền khỏi quỹ: {body.amount}"
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
        )
        result = drawer.to_api_dict()
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
        expected = drawer.expected_balance()
        discrepancy = drawer.close(conn, counted_amount=body.countedAmount)
        journal = None
        surplus_result = None
        shortage_result = None

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
                    f"Đóng quỹ tiền mặt: đếm={body.countedAmount}, "
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
                    )
                elif body.surplusSource == "unidentified_sale":
                    cogs = int(discrepancy * 0.5)
                    revenue_acct = _account_id_by_code(conn, REVENUE_CODE)
                    cogs_acct = _account_id_by_code(conn, COGS_CODE)
                    inventory_acct = _account_id_by_code(conn, INVENTORY_CODE)
                    sale_desc = (
                        f"Doanh thu chưa xác định khi đóng quỹ: {discrepancy}"
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
                    f"Đóng quỹ tiền mặt: đếm={body.countedAmount}, "
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
                    )
                elif body.shortageSource == "equity_loss":
                    journal = _create_drawer_journal_entry(
                        conn,
                        source_type="cash_drawer_close_adjust",
                        description=desc,
                        debit_account_id=accounts["equity"],
                        credit_account_id=accounts["cash_drawer"],
                        amount=amt,
                    )
        # Zero discrepancy: no journal entry, no confirmation required (FR8).
        result = drawer.to_api_dict()
        if journal is not None:
            result["journalEntry"] = journal
        if surplus_result is not None:
            result["surplusJournalEntry"] = surplus_result
        if shortage_result is not None:
            result["shortageJournalEntry"] = shortage_result
        return result


@router.get("/status")
def drawer_status():
    """FR4: return the active (open) drawer with expected balance, or null.

    FR8: stale previous-day drawers are auto-closed lazily before this read.
    DG-331 FR9: includes previousCloseCountedAmount (counted_amount of most
    recent closed drawer) when no active drawer exists, for display in the
    open dialog as "Số dư sau khi đóng quỹ lần trước".
    """
    with get_db() as conn:
        _auto_close_stale_drawers(conn)
        drawer = CashDrawer.get_active(conn)
        if drawer:
            return drawer.to_api_dict()
        recent = CashDrawer.get_most_recent_closed(conn)
        if recent:
            data = {"activeDrawer": None}
            data["previousCloseCountedAmount"] = recent.counted_amount
            return data
        return None


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