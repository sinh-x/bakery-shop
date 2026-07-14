"""Tests for debt expense API — DG-212 Phases 1 & 2.

Extracted from tests/test_api_accounts.py (CQ-4: the 1747-line file interleaved
debt tests with order/payment tests). Covers:

- DG-212 Phase 1 (FR1, FR2, FR3, AC2): debt expense creation journals credit
  2500 (Accounts Payable); vendor required; payment_source omitted.
- DG-212 Phase 2 (FR4, FR5, FR7, FR8, FR9, FR10, AC3, AC4): debt settlement
  endpoint, outstanding debts listing, debt status filter, delete/edit
  re-sync behavior.

Helpers are duplicated locally (matches the standalone-test-file convention used
elsewhere in tests/ — e.g. test_api_payment_transactions.py).
"""

from baker.db.connection import get_db
from baker.models.account import Account
from baker.models.journal_entry import JournalEntry


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _journal_for_source(conn, source_type: str, source_id: int):
    rows = conn.execute(
        "SELECT * FROM journal_entries WHERE source_type = ? AND source_id = ? ORDER BY id",
        (source_type, source_id),
    ).fetchall()
    return [JournalEntry.from_row(r) for r in rows]


def _lines_for_entry(conn, entry_id: int):
    from baker.models.journal_entry import JournalLine
    return JournalLine.list_for_entry(conn, entry_id)


def _create_debt_expense(client, amount=500000, vendor="Nhà cung cấp A",
                         category="Vận chuyển", summary="Nợ bột mì"):
    payload = {
        "summary": summary,
        "type": "expense",
        "data": {
            "amount_vnd": amount,
            "category": category,
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": vendor,
            "note": "ghi nợ",
            "paid_by_name": "",
        },
    }
    resp = client.post("/api/events", json=payload)
    assert resp.status_code == 201
    return resp.json()


# ---------------------------------------------------------------------------
# Phase 1 — debt expense creation (FR1, FR2, FR3, AC2)
# ---------------------------------------------------------------------------


def test_debt_expense_creates_journal_entry_crediting_2500(api_client):
    """AC2 (DG-245 Phase 3): expense with payment_method='Nợ', vendor='Nhà cung cấp A'
    → debit expense account, credit a per-vendor 25xx sub-account under 2500."""
    resp = api_client.post("/api/events", json={
        "summary": "Nợ bột mì",
        "type": "expense",
        "data": {
            "amount_vnd": 200000,
            "category": "Vận chuyển",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "Nhà cung cấp A",
            "note": "ghi nợ",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 201
    eid = int(resp.json()["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        assert len(lines) == 2
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        assert debit_line.debit == 200000.0
        assert credit_line.credit == 200000.0
        # "Vận chuyển" is a non-inventory expense → debit 5300 (Delivery/Shipping)
        expense_acc = Account.get_by_id(conn, debit_line.account_id)
        assert expense_acc.code == "5300"
        # Credit must hit a per-vendor sub-account under Accounts Payable (2500),
        # not the 2500 parent itself (DG-245 Phase 3, FR2/FR3).
        ap_acc = Account.get_by_id(conn, credit_line.account_id)
        assert ap_acc.code.startswith("25") and ap_acc.code != "2500"
        assert ap_acc.name == "Nhà cung cấp A"
        parent_acc = Account.get_by_id(conn, ap_acc.parent_id)
        assert parent_acc.code == "2500"


def test_debt_expense_inventory_category_debits_inventory_credits_2500(api_client):
    """Debt expense for an inventory-purchase category (Nguyên liệu) debits
    Inventory (1300) and credits a per-vendor 25xx sub-account under 2500."""
    resp = api_client.post("/api/events", json={
        "summary": "Nợ nguyên liệu",
        "type": "expense",
        "data": {
            "amount_vnd": 150000,
            "category": "Nguyên liệu",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "Nhà cung cấp B",
            "note": "ghi nợ",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 201
    eid = int(resp.json()["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        inventory_acc = Account.get_by_id(conn, debit_line.account_id)
        assert inventory_acc.code == "1300"
        ap_acc = Account.get_by_id(conn, credit_line.account_id)
        assert ap_acc.code.startswith("25") and ap_acc.code != "2500"
        assert ap_acc.name == "Nhà cung cấp B"
        parent_acc = Account.get_by_id(conn, ap_acc.parent_id)
        assert parent_acc.code == "2500"


def test_debt_expense_omits_payment_source(api_client):
    """FR2: payment_source is not required when payment_method is 'Nợ'."""
    resp = api_client.post("/api/events", json={
        "summary": "Nợ tiền",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Khác",
            "payment_method": "Nợ",
            "vendor": "Nhà cung cấp C",
            "note": "ghi nợ",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 201


def test_debt_expense_rejects_empty_vendor(api_client):
    """FR2: vendor (creditor) is required when payment_method is 'Nợ'."""
    resp = api_client.post("/api/events", json={
        "summary": "Nợ không có chủ nợ",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Khác",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "  ",
            "note": "ghi nợ",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 422
    assert "vendor" in resp.json()["detail"]


def test_accounts_payable_2500_seeded(api_client):
    """DG-212: account 2500 'Phải trả người bán (Accounts Payable)' is seeded."""
    resp = api_client.get("/api/accounts")
    assert resp.status_code == 200
    tree = resp.json()
    liability_group = next(a for a in tree if a["code"] == "2000")
    child_codes = {c["code"] for c in liability_group["children"]}
    assert "2500" in child_codes


# ---------------------------------------------------------------------------
# Phase 2 — debt settlement + outstanding debts (FR4, FR5, FR7, FR8,
# FR9, FR10, AC3, AC4)
# ---------------------------------------------------------------------------


def test_settle_debt_records_actor_in_history(api_client):
    """CQ-1: POST /api/expenses/{id}/settle?settled_by=X records X as the audit actor."""
    expense = _create_debt_expense(api_client, amount=200000)
    eid = int(expense["id"])
    resp = api_client.post(
        f"/api/expenses/{eid}/settle?settled_by=Phuong",
        json={
            "amount": 200000,
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
        },
    )
    assert resp.status_code == 200
    with get_db() as conn:
        rows = conn.execute(
            "SELECT actor, action_type FROM event_history "
            "WHERE event_id = ? AND action_type = 'settle' ORDER BY id DESC",
            (eid,),
        ).fetchall()
        assert len(rows) >= 1
        assert rows[0]["actor"] == "Phuong"


def test_settle_debt_full_creates_journal_entry(api_client):
    """FR4: POST /api/expenses/{id}/settle creates DR 2500 / CR Asset journal."""
    expense = _create_debt_expense(api_client, amount=500000)
    eid = int(expense["id"])
    resp = api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 500000,
        "payment_method": "Tiền mặt",
        "payment_source": "Shop tiền mặt",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["settled_amount"] == 500000
    assert body["remaining"] == 0
    assert body["status"] == "paid"
    with get_db() as conn:
        # Find the settlement journal entry (source_type='expense_settlement').
        rows = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type = 'expense_settlement' "
            "AND source_id = ? ORDER BY id",
            (body["settlement_id"],),
        ).fetchall()
        assert len(rows) == 1
        entry_id = int(rows[0]["id"])
        lines = _lines_for_entry(conn, entry_id)
        debit_line = next(l for l in lines if l.debit > 0)
        credit_line = next(l for l in lines if l.credit > 0)
        # DR 2500 (Accounts Payable), CR 1100 (Cash on Hand — Shop tiền mặt)
        ap_acc = Account.get_by_id(conn, debit_line.account_id)
        asset_acc = Account.get_by_id(conn, credit_line.account_id)
        assert ap_acc.code == "2500"
        assert asset_acc.code == "1100"
        assert debit_line.debit == 500000.0
        assert credit_line.credit == 500000.0


def test_settle_debt_partial_tracks_remaining_balance(api_client):
    """AC3: settle 300,000 of 500,000 → remaining 200,000, status 'Trả một phần'."""
    expense = _create_debt_expense(api_client, amount=500000,
                                   vendor="Nhà cung cấp A", summary="Nợ NCC A")
    eid = int(expense["id"])
    resp = api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 300000,
        "payment_method": "Chuyển khoản",
        "payment_source": "TK Phượng VCB",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["settled_amount"] == 300000
    assert body["remaining"] == 200000
    assert body["status"] == "partial"
    # Second partial settlement to clear the rest.
    resp2 = api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 200000,
        "payment_method": "Tiền mặt",
        "payment_source": "Shop tiền mặt",
    })
    assert resp2.status_code == 200
    body2 = resp2.json()
    assert body2["settled_amount"] == 500000
    assert body2["remaining"] == 0
    assert body2["status"] == "paid"
    # Two distinct settlement journal entries must exist.
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type = 'expense_settlement' "
            "AND source_id IN (?, ?) ORDER BY id",
            (body["settlement_id"], body2["settlement_id"]),
        ).fetchall()
        assert len(rows) == 2


def test_settle_debt_rejects_amount_exceeding_remaining(api_client):
    """Cannot settle more than the remaining debt balance."""
    expense = _create_debt_expense(api_client, amount=500000)
    eid = int(expense["id"])
    resp = api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 600000,
        "payment_method": "Tiền mặt",
        "payment_source": "Shop tiền mặt",
    })
    assert resp.status_code == 422


def test_settle_non_debt_expense_rejected(api_client):
    """Settlement endpoint only applies to debt expenses."""
    resp = api_client.post("/api/events", json={
        "summary": "Chi phí mặt",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Khác",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ",
            "note": "",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 201
    eid = int(resp.json()["id"])
    settle = api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 50000,
        "payment_method": "Tiền mặt",
        "payment_source": "Shop tiền mặt",
    })
    assert settle.status_code == 422


def test_list_outstanding_debts_grouped_by_creditor(api_client):
    """AC4: GET /api/expenses/debts groups by creditor with totals."""
    _create_debt_expense(api_client, amount=500000, vendor="Nhà cung cấp A",
                         summary="Nợ A1")
    _create_debt_expense(api_client, amount=200000, vendor="Nhà cung cấp A",
                         summary="Nợ A2")
    _create_debt_expense(api_client, amount=100000, vendor="Nhà cung cấp B",
                         summary="Nợ B1")
    resp = api_client.get("/api/expenses/debts")
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 3
    assert body["total_owed"] == 800000.0
    creditor_map = {g["creditor"]: g for g in body["creditors"]}
    a = creditor_map["Nhà cung cấp A"]
    assert a["count"] == 2
    assert a["total_owed"] == 700000.0
    b = creditor_map["Nhà cung cấp B"]
    assert b["count"] == 1
    assert b["total_owed"] == 100000.0


def test_list_outstanding_debts_filter_by_creditor(api_client):
    """AC4: filtering by creditor returns only that creditor's debts."""
    _create_debt_expense(api_client, amount=500000, vendor="Nhà cung cấp A")
    _create_debt_expense(api_client, amount=100000, vendor="Nhà cung cấp B")
    resp = api_client.get("/api/expenses/debts?creditor=Nh%C3%A0%20cung%20c%E1%BA%A5p%20A")
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    assert body["creditors"][0]["creditor"] == "Nhà cung cấp A"


def test_list_outstanding_debts_excludes_settled_by_default(api_client):
    """Outstanding debts list with status=all still shows paid debts, but
    filtering by status=unpaid excludes fully-settled ones."""
    expense = _create_debt_expense(api_client, amount=300000, vendor="NCC X")
    eid = int(expense["id"])
    api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 300000,
        "payment_method": "Tiền mặt",
        "payment_source": "Shop tiền mặt",
    })
    # status=all returns both
    all_resp = api_client.get("/api/expenses/debts?status=all")
    assert all_resp.json()["count"] == 1
    assert all_resp.json()["creditors"][0]["debts"][0]["status"] == "paid"
    # status=unpaid returns none
    unpaid_resp = api_client.get("/api/expenses/debts?status=unpaid")
    assert unpaid_resp.json()["count"] == 0


def test_list_events_debt_status_filter_unpaid(api_client):
    """FR7: list events supports debt_status filter."""
    _create_debt_expense(api_client, amount=200000, vendor="NCC Y", summary="Nợ Y")
    # A non-debt expense should NOT appear when filtering for unpaid debts.
    api_client.post("/api/events", json={
        "summary": "Tiền mặt",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Khác",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ",
            "note": "",
            "paid_by_name": "Phượng",
        },
    })
    resp = api_client.get("/api/events?type=expense&debt_status=unpaid")
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["payment_method"] == "Nợ"


def test_delete_debt_expense_reverses_settlement_journals(api_client):
    """FR9: deleting a debt expense reverses its settlement journal entries."""
    expense = _create_debt_expense(api_client, amount=400000, vendor="NCC Z")
    eid = int(expense["id"])
    settle_resp = api_client.post(f"/api/expenses/{eid}/settle", json={
        "amount": 200000,
        "payment_method": "Tiền mặt",
        "payment_source": "Shop tiền mặt",
    })
    sid = settle_resp.json()["settlement_id"]
    with get_db() as conn:
        before = _journal_for_source(conn, "expense_settlement", sid)
        assert len(before) == 1
    del_resp = api_client.delete(f"/api/events/{eid}?deleted_by=test")
    assert del_resp.status_code == 204
    with get_db() as conn:
        after = _journal_for_source(conn, "expense_settlement", sid)
        # Unlocked settlement entry is removed on delete (FR9).
        assert len(after) == 0
        # The original expense journal entry is also removed.
        expense_entries = _journal_for_source(conn, "expense", eid)
        assert len(expense_entries) == 0


def test_edit_debt_expense_re_syncs_journal(api_client):
    """FR10: editing a debt expense re-syncs its journal entry."""
    expense = _create_debt_expense(api_client, amount=300000, vendor="NCC W",
                                   category="Vận chuyển")
    eid = int(expense["id"])
    with get_db() as conn:
        orig = _journal_for_source(conn, "expense", eid)
        assert len(orig) == 1
        orig_id = orig[0].id
    # Edit amount → journal should re-sync in place (unlocked).
    patch_resp = api_client.patch(f"/api/events/{eid}", json={
        "data": {
            "amount_vnd": 450000,
            "category": "Vận chuyển",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "NCC W",
            "note": "ghi nợ (đã sửa)",
            "paid_by_name": "",
        },
    })
    assert patch_resp.status_code == 200
    with get_db() as conn:
        after = _journal_for_source(conn, "expense", eid)
        assert len(after) == 1
        lines = _lines_for_entry(conn, after[0].id)
        debit_line = next(l for l in lines if l.debit > 0)
        assert debit_line.debit == 450000.0
        # Same entry id (in-place update).
        assert after[0].id == orig_id


# ---------------------------------------------------------------------------
# DG-245 Phase 3 — per-vendor 25xx sub-account + cash↔debt edit round-trip
# ---------------------------------------------------------------------------


def test_per_vendor_sub_account_is_max_based_and_unique(api_client):
    """FR2: two distinct vendors get distinct 25xx sub-accounts, MAX-based,
    and the same vendor reuses its existing sub-account."""
    _create_debt_expense(api_client, amount=100000, vendor="NCC Alpha",
                         summary="Nợ Alpha 1")
    _create_debt_expense(api_client, amount=100000, vendor="NCC Beta",
                         summary="Nợ Beta 1")
    _create_debt_expense(api_client, amount=100000, vendor="NCC Alpha",
                         summary="Nợ Alpha 2")
    with get_db() as conn:
        rows = conn.execute(
            "SELECT code, name FROM accounts "
            "WHERE parent_id = (SELECT id FROM accounts WHERE code = '2500') "
            "ORDER BY code"
        ).fetchall()
        names = [r["name"] for r in rows]
        codes = [r["code"] for r in rows]
        # Two distinct vendor sub-accounts, each used twice (idempotent).
        assert names.count("NCC Alpha") == 1
        assert names.count("NCC Beta") == 1
        # MAX-based: first sub-account is 2501, second is 2502.
        assert "2501" in codes
        assert "2502" in codes


def test_cash_to_debt_to_cash_edit_round_trip(api_client):
    """AC2 (DG-245 Phase 3): editing an expense cash→debt→cash produces the
    correct credit each time and leaves no stale journal entry.

    - Start as cash expense → credit asset 1100 (Shop tiền mặt).
    - Edit to debt → credit vendor 25xx sub-account under 2500.
    - Edit back to cash → credit 1100 again.
    - Exactly one journal entry exists for the expense at each step (in-place
      update, no stale entries).
    """
    # 1. Create a cash expense.
    resp = api_client.post("/api/events", json={
        "summary": "Tiền mặt ban đầu",
        "type": "expense",
        "data": {
            "amount_vnd": 200000,
            "category": "Vận chuyển",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC RoundTrip",
            "note": "",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 201
    eid = int(resp.json()["id"])

    def _credit_code(conn):
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1, "expected exactly one journal entry"
        lines = _lines_for_entry(conn, entries[0].id)
        credit_line = next(l for l in lines if l.credit > 0)
        return Account.get_by_id(conn, credit_line.account_id).code, entries[0].id

    with get_db() as conn:
        code_cash, entry_id_1 = _credit_code(conn)
    assert code_cash == "1100"

    # 2. Edit cash → debt. The existing unlocked JE is updated in place and
    #    its credit must now hit the vendor's 25xx sub-account (not 2500).
    patch_debt = api_client.patch(f"/api/events/{eid}", json={
        "data": {
            "amount_vnd": 200000,
            "category": "Vận chuyển",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "NCC RoundTrip",
            "note": "chuyển sang nợ",
            "paid_by_name": "",
        },
    })
    assert patch_debt.status_code == 200
    with get_db() as conn:
        code_debt, entry_id_2 = _credit_code(conn)
        # Sub-account under 2500, not the 2500 parent.
        assert code_debt.startswith("25") and code_debt != "2500"
        # In-place update: same entry id, no stale JE.
        assert entry_id_2 == entry_id_1

    # 3. Edit debt → cash. The credit must return to the asset 1100 and the
    #    entry must still be the same in-place JE (no stale entry left behind).
    patch_cash = api_client.patch(f"/api/events/{eid}", json={
        "data": {
            "amount_vnd": 200000,
            "category": "Vận chuyển",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC RoundTrip",
            "note": "chuyển lại tiền mặt",
            "paid_by_name": "",
        },
    })
    assert patch_cash.status_code == 200
    with get_db() as conn:
        code_cash2, entry_id_3 = _credit_code(conn)
    assert code_cash2 == "1100"
    assert entry_id_3 == entry_id_1


def test_edit_debt_expense_vendor_change_switches_sub_account(api_client):
    """Editing a debt expense to a different vendor re-points the credit to
    that vendor's own 25xx sub-account (single source of truth)."""
    _create_debt_expense(api_client, amount=150000, vendor="NCC Gamma",
                         summary="Nợ Gamma")
    expense = _create_debt_expense(api_client, amount=150000, vendor="NCC Delta",
                                   summary="Nợ Delta")
    eid = int(expense["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        credit_line = next(l for l in lines if l.credit > 0)
        delta_acc = Account.get_by_id(conn, credit_line.account_id)
        assert delta_acc.name == "NCC Delta"

    # Re-point to the existing Gamma sub-account (must reuse, not create new).
    patch_resp = api_client.patch(f"/api/events/{eid}", json={
        "data": {
            "amount_vnd": 150000,
            "category": "Vận chuyển",
            "payment_method": "Nợ",
            "payment_source": "",
            "vendor": "NCC Gamma",
            "note": "đổi chủ nợ",
            "paid_by_name": "",
        },
    })
    assert patch_resp.status_code == 200
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        assert len(entries) == 1
        lines = _lines_for_entry(conn, entries[0].id)
        credit_line = next(l for l in lines if l.credit > 0)
        gamma_acc = Account.get_by_id(conn, credit_line.account_id)
        assert gamma_acc.name == "NCC Gamma"
        # Only two vendor sub-accounts should exist (Gamma + Delta).
        rows = conn.execute(
            "SELECT name FROM accounts "
            "WHERE parent_id = (SELECT id FROM accounts WHERE code = '2500')"
        ).fetchall()
        vendor_names = {r["name"] for r in rows}
        assert vendor_names == {"NCC Gamma", "NCC Delta"}
