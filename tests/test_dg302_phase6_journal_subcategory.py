"""Tests for DG-302 Phase 6: accounting integration — subcategory account codes.

Verifies FR4 / AC4:

- Creating an expense with ``category=Nguyên liệu`` + ``subcategory=Trứng``
  produces a journal entry that debits account 5110 (not Inventory 1300,
  not parent 5100).
- Each subcategory maps to its own account code (Trứng→5110, Kem→5120,
  Bột→5130, Phụ gia khác→5140, Hộp & đế→5210, Phụ kiện→5220, Bọc nilon→5230).
- Expenses without a subcategory still debit Inventory (1300) for inventory
  parent categories (FR6 backward compatibility).
- The accounting-validation ``expense_category_mismatch`` check accepts
  subcategory-debited entries (does not flag them as mismatches).
"""

import pytest
from baker.db.connection import get_db
from baker.models.account import Account
from baker.models.journal_entry import JournalEntry

pytestmark = [
    pytest.mark.critical,
    pytest.mark.skip(
        reason="DG-347 Phase 1: cash_drawer_id dropped from events; expense "
               "sync code references the dropped column; re-enable in Phase 3"
    ),
]


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


def _create_expense(client, *, category, subcategory=None, amount=100000,
                   payment_source="Tiền mặt tại quầy", summary="Test expense"):
    data = {
        "amount_vnd": amount,
        "category": category,
        "payment_source": payment_source,
        "payment_method": "TM",
        "vendor": "",
        "note": "",
        "paid_by_name": "",
    }
    if subcategory is not None:
        data["subcategory"] = subcategory
    resp = client.post("/api/events", json={
        "summary": summary,
        "type": "expense",
        "data": data,
    })
    assert resp.status_code == 201, resp.text
    return resp.json()


def _debit_code_for_expense(conn, event_id: int) -> str:
    entries = _journal_for_source(conn, "expense", event_id)
    assert len(entries) == 1, f"expected 1 expense JE, got {len(entries)}"
    lines = _lines_for_entry(conn, entries[0].id)
    debit_line = next(l for l in lines if l.debit > 0)
    acc = Account.get_by_id(conn, debit_line.account_id)
    return acc.code


# ---------------------------------------------------------------------------
# Live API: subcategory expense debits the subcategory account (FR4 / AC4)
# ---------------------------------------------------------------------------


def test_expense_subcategory_trung_debits_5110(api_client):
    """AC4: expense with subcategory 'Trứng' debits account 5110, not 5100/1300."""
    payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory="Trứng",
        amount=50000, summary="Mua trứng",
    )
    eid = int(payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5110"


def test_expense_subcategory_kem_debits_5120(api_client):
    _payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory="Kem",
        amount=30000, summary="Mua kem",
    )
    eid = int(_payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5120"


def test_expense_subcategory_bot_debits_5130(api_client):
    _payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory="Bột",
        amount=20000, summary="Mua bột",
    )
    eid = int(_payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5130"


def test_expense_subcategory_phu_gia_debits_5140(api_client):
    _payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory="Phụ gia khác",
        amount=10000, summary="Mua phụ gia",
    )
    eid = int(_payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5140"


def test_expense_subcategory_hop_de_debits_5210(api_client):
    _payload = _create_expense(
        api_client, category="Bao bì", subcategory="Hộp & đế",
        amount=15000, summary="Mua hộp",
    )
    eid = int(_payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5210"


def test_expense_subcategory_phu_kien_debits_5220(api_client):
    _payload = _create_expense(
        api_client, category="Bao bì", subcategory="Phụ kiện",
        amount=12000, summary="Mua phụ kiện",
    )
    eid = int(_payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5220"


def test_expense_subcategory_boc_nilon_debits_5230(api_client):
    _payload = _create_expense(
        api_client, category="Bao bì", subcategory="Bọc nilon",
        amount=8000, summary="Mua nilon",
    )
    eid = int(_payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "5230"


def test_expense_no_subcategory_legacy_debits_inventory(api_client):
    """FR6: an expense with category='Nguyên liệu' and no subcategory still
    debits Inventory (1300), not 5100 — backward compatibility."""
    payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory=None,
        amount=40000, summary="Mua đường (legacy)",
    )
    eid = int(payload["id"])
    with get_db() as conn:
        assert _debit_code_for_expense(conn, eid) == "1300"


def test_expense_subcategory_credit_unchanged(api_client):
    """The subcategory change only affects the debit side; the credit still
    hits the mapped payment_source account (1101 for Tiền mặt tại quầy)."""
    payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory="Trứng",
        amount=50000, summary="Mua trứng",
    )
    eid = int(payload["id"])
    with get_db() as conn:
        entries = _journal_for_source(conn, "expense", eid)
        lines = _lines_for_entry(conn, entries[0].id)
        credit_line = next(l for l in lines if l.credit > 0)
        credit_acc = Account.get_by_id(conn, credit_line.account_id)
        assert credit_acc.code == "1101"


# ---------------------------------------------------------------------------
# Accounting validation: subcategory entries are not flagged as mismatch
# ---------------------------------------------------------------------------


def test_accounting_validation_accepts_subcategory_entry(api_client):
    """The ``expense_category_mismatch`` check must not flag a subcategory
    journal entry (debit 5110 for Trứng) as a mismatch."""
    from baker.services.accounting_validation import run_validation

    payload = _create_expense(
        api_client, category="Nguyên liệu", subcategory="Trứng",
        amount=50000, summary="Mua trứng",
    )
    eid = int(payload["id"])
    with get_db() as conn:
        report = run_validation(conn)
    check = next(
        c for c in report["checks"] if c["check"] == "expense_category_mismatch"
    )
    assert check["status"] == "pass"
    assert check["issue_count"] == 0
    # source_ledger_totals should also pass (the JE is balanced against the
    # event amount).
    src_check = next(
        c for c in report["checks"] if c["check"] == "source_ledger_totals"
    )
    expense_total = next(
        (t for t in src_check["details"] if t.get("source_type") == "expense"),
        None,
    )
    if expense_total is not None:
        assert expense_total["status"] == "pass", expense_total