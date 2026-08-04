"""Expense-domain journal sync (DG-308 Phase 4.4, FR-ARCH-2).

Expense event + debt-settlement journal entry create/update/delete logic
extracted from the original monolithic ``journal_sync.py``.
"""

import json
from typing import Any, Optional

from baker.db.schema import (
    ACCOUNTS_PAYABLE_CODE,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    EXPENSE_DEBT_PAYMENT_METHOD,
    EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE,
    INVENTORY_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    REVENUE_UPDATE_TOLERANCE,
    _account_id_by_code,
    _ensure_ap_vendor_sub_account,
    _ensure_staff_payable_sub_account,
    _insert_journal_entry,
)
from baker.services.journal_sync._common import (
    STAFF_ADVANCE_PAYMENT_SOURCE,
    _active_drawer_id,
    _delete_journal_entry_cascade,
    _find_journal_entry,
    _is_locked,
    _reverse_journal_entry,
    _update_journal_entry_in_place,
)


def _resolve_expense_account_code(data: dict) -> Optional[str]:
    """Resolve the expense account code, preferring subcategory over category.

    DG-302 Phase 6 (FR4/AC4): when ``events.data.subcategory`` is present and
    maps to an account code in ``EXPENSE_CATEGORY_TO_ACCOUNT_CODE``, use that
    subcategory code (e.g. Trứng→5110). Otherwise fall back to the parent
    ``category`` code (e.g. Nguyên liệu→5100). Returns ``None`` when neither
    resolves.

    A subcategory code takes precedence over the inventory-purchase path:
    an expense tagged ``category=Nguyên liệu`` + ``subcategory=Trứng`` debits
    account 5110, not Inventory (1300). The inventory-purchase debit only
    applies to expenses that carry no mappable subcategory (FR6 backward
    compatibility).
    """
    subcategory = data.get("subcategory")
    if isinstance(subcategory, str) and subcategory:
        sub_code = EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(subcategory)
        if sub_code:
            return sub_code
    category = data.get("category")
    if isinstance(category, str) and category:
        return EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(category)
    return None

def _is_expense_journallable(data: dict) -> bool:
    """Return True iff an expense event should produce a journal entry.

    Encodes the build-time skip predicate shared by three call sites that must
    agree on which expense events are by-design journalled:

      - ``_build_expense_journal_lines`` (journal_sync) — the create path.
      - ``_source_sum_expense`` (accounting_validation) — the source-ledger
        SUM must exclude events that produce no JE, or it reports a phantom
        delta (CQ-3).
      - ``_expected_expense_credit`` (repair) — detection must not flag
        unjournalled events as missing/stale, or repair becomes
        non-idempotent and creates phantom vendor sub-accounts (CQ-3/CQ-4).

    An event is journallable iff it has a positive numeric ``amount_vnd``, a
    resolvable expense account code (subcategory preferred, then category —
    DG-302 Phase 6), a resolvable payment configuration (``payment_method``
    debt, or a ``payment_source`` in the asset map), and — for debt /
    staff-advance events — a non-empty ``vendor`` / ``paid_by_name``
    respectively.

    This predicate performs no I/O and mutates nothing; callers retain the
    branch-specific resolution (sub-account creation, account-id lookup) after
    it returns True (CQ-5).
    """
    amount = data.get("amount_vnd")
    payment_source = data.get("payment_source")
    payment_method = data.get("payment_method", "")
    if not isinstance(amount, (int, float)) or amount <= 0:
        return False
    if not _resolve_expense_account_code(data):
        return False
    is_debt = payment_method == EXPENSE_DEBT_PAYMENT_METHOD
    if not is_debt and (not isinstance(payment_source, str) or not payment_source):
        return False
    if is_debt:
        if not (data.get("vendor") or "").strip():
            return False
    elif payment_source == STAFF_ADVANCE_PAYMENT_SOURCE:
        if not (data.get("paid_by_name") or "").strip():
            return False
    else:
        if payment_source not in EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE:
            return False
    return True

def _build_expense_journal_lines(
    conn, data: dict[str, Any], summary: str
) -> Optional[tuple[str, list[tuple[int, float, float, str]]]]:
    """Build (description, lines) for an expense event's journal entry.

    Returns None when the expense data is incomplete/unsupported (silently skip).

    DG-302 Phase 6 (FR4/AC4): when ``data.subcategory`` maps to an account
    code, the debit hits that subcategory account (e.g. 5110 for Trứng) and
    the inventory-purchase path is bypassed — the subcategory account is the
    debit target even for inventory parent categories (Nguyên liệu, Bao bì).
    Without a mappable subcategory, the legacy behavior applies: parent
    categories in ``INVENTORY_PURCHASE_CATEGORIES`` debit Inventory (1300).
    """
    amount = data.get("amount_vnd")
    category = data.get("category")
    payment_source = data.get("payment_source")
    payment_method = data.get("payment_method", "")
    if not _is_expense_journallable(data):
        return None

    is_debt = payment_method == EXPENSE_DEBT_PAYMENT_METHOD
    # Phase 6: prefer subcategory account code; fall back to category code.
    subcategory = data.get("subcategory")
    has_subcategory_code = (
        isinstance(subcategory, str)
        and bool(subcategory)
        and bool(EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(subcategory))
    )
    expense_code = _resolve_expense_account_code(data)

    if is_debt:
        # FR3 (DG-245 Phase 3): debt expenses credit a per-vendor sub-account
        # under Accounts Payable (2500) — not the 2500 parent. The vendor
        # field is the creditor identifier (FR2) and resolves to a single
        # sub-account via _ensure_ap_vendor_sub_account (MAX-based 25xx code).
        vendor_name = (data.get("vendor") or "").strip()
        if not vendor_name:
            return None
        payment_account_id = _ensure_ap_vendor_sub_account(conn, vendor_name)
    elif payment_source == STAFF_ADVANCE_PAYMENT_SOURCE:
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

    # Phase 6: a mappable subcategory debits its own account and bypasses the
    # inventory-purchase path (FR4/AC4). Otherwise, parent inventory-purchase
    # categories still debit Inventory (1300) for backward compatibility (FR6).
    if not has_subcategory_code and category in INVENTORY_PURCHASE_CATEGORIES:
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
            drawer_id=_active_drawer_id(conn),
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
            drawer_id=_active_drawer_id(conn),
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )

def _build_debt_settlement_journal_lines(
    conn, event_summary: str, amount: float, payment_source: str,
    vendor_name: str = "",
) -> Optional[tuple[str, list[tuple[int, float, float, str]]]]:
    """Build (description, lines) for a debt settlement journal entry (FR4/FR5).

    Settlement journals DR the vendor's per-vendor 25xx sub-account under
    Accounts Payable (2500) and CR the asset account chosen by
    ``payment_source`` (FR4). FR5 (DG-245 Phase 4): the debit must hit the
    *same* per-vendor sub-account that the originating debt expense credited,
    so a full settlement nets that sub-account to zero. The sub-account is
    resolved via the single-source-of-truth ``_ensure_ap_vendor_sub_account``
    helper (Phase 3).

    When ``vendor_name`` is empty, fall back to the 2500 parent account
    (preserves backwards compatibility for any legacy settlements that lack a
    vendor). When ``payment_source`` is the staff advance source, the credit
    would go to a per-staff sub-account under 2300 — but settlements do not
    currently carry ``paid_by_name``, so the staff advance path is unsupported
    and the function returns None.
    """
    if amount <= 0:
        return None
    if vendor_name and vendor_name.strip():
        ap_account_id = _ensure_ap_vendor_sub_account(conn, vendor_name.strip())
    else:
        ap_account_id = _account_id_by_code(conn, ACCOUNTS_PAYABLE_CODE)
    account_code = EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE.get(payment_source)
    if not account_code:
        return None
    asset_account_id = _account_id_by_code(conn, account_code)
    amount_f = float(amount)
    description = f"Debt settlement: {event_summary}"
    lines = [
        (ap_account_id, amount_f, 0.0, "Trả nợ nhà cung cấp"),
        (asset_account_id, 0.0, amount_f, "Thanh toán nợ"),
    ]
    return description, lines

def _sync_debt_settlement_journal(
    conn,
    settlement_id: int,
    event_id: int,
    event_summary: str,
    amount: float,
    payment_source: str,
    *,
    deleted: bool = False,
) -> None:
    """Create/update/delete the journal entry for a debt settlement.

    Each settlement has its own journal entry keyed by
    ``source_type='expense_settlement'`` and ``source_id=settlement_id`` so
    multiple partial settlements can coexist on the same expense event. On
    delete, unlocked entries are removed and locked entries are reversed.

    FR5 (DG-245 Phase 4): the vendor is resolved from the originating expense
    event's ``data`` JSON (``event.data["vendor"]``) and passed to
    :func:`_build_debt_settlement_journal_lines` so the settlement debits the
    same per-vendor 25xx sub-account the expense credited. A full settlement
    nets that sub-account to zero.
    """
    existing_id = _find_journal_entry(conn, "expense_settlement", settlement_id)

    if deleted:
        if existing_id is None:
            return
        if _is_locked(conn, existing_id):
            _reverse_journal_entry(conn, existing_id)
        else:
            _delete_journal_entry_cascade(conn, existing_id)
        return

    # FR5: resolve the vendor from the originating expense event so the
    # settlement debits the same per-vendor 25xx sub-account.
    vendor_name = ""
    event_row = conn.execute(
        "SELECT data, timestamp FROM events WHERE id = ?", (event_id,)
    ).fetchone()
    transaction_date = None
    if event_row:
        transaction_date = event_row["timestamp"] if "timestamp" in event_row.keys() else None
        try:
            event_data = json.loads(event_row["data"]) if event_row["data"] else {}
        except (ValueError, TypeError):
            event_data = {}
        vendor_name = (event_data.get("vendor") or "").strip() if isinstance(event_data, dict) else ""

    built = _build_debt_settlement_journal_lines(
        conn, event_summary, amount, payment_source, vendor_name=vendor_name
    )
    if built is None:
        if existing_id is not None and not _is_locked(conn, existing_id):
            _delete_journal_entry_cascade(conn, existing_id)
        return
    description, lines = built

    # The settlement's business date is the event's timestamp (the debt was
    # incurred on the event date; settlement records the cash outflow).
    # `transaction_date` is already resolved from `event_row` above.
    if event_row is None:
        transaction_date = None

    if existing_id is None:
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense_settlement",
            source_id=settlement_id,
            lines=lines,
            transaction_date=transaction_date,
            drawer_id=_active_drawer_id(conn),
        )
    elif _is_locked(conn, existing_id):
        _reverse_journal_entry(conn, existing_id)
        _insert_journal_entry(
            conn,
            description=description,
            source_type="expense_settlement",
            source_id=settlement_id,
            lines=lines,
            transaction_date=transaction_date,
            drawer_id=_active_drawer_id(conn),
        )
    else:
        _update_journal_entry_in_place(
            conn, existing_id, description=description, lines=lines
        )
