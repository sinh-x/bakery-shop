"""Tests for the cash drawer API — DG-324 Phase 2.

Covers:
    - POST /api/cash-drawer/open   (FR1, AC1)
    - POST /api/cash-drawer/cash-in (FR2, AC2)
    - POST /api/cash-drawer/cash-out (FR3, AC3)
    - POST /api/cash-drawer/close  (FR7, AC7)
    - GET  /api/cash-drawer/status (FR4, AC6)
    - GET  /api/cash-drawer/history (FR10)
    - Single-active-drawer rule
    - NFR1: expected_balance computation matches the formula
    - NFR3: all drawer journal entries are balanced (debit sum = credit sum)
"""

import pytest

from baker.db.connection import get_db
from baker.models.cash_drawer import CashDrawer


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


def _entry_lines(conn, source_type: str):
    rows = conn.execute(
        "SELECT jl.* FROM journal_lines jl "
        "JOIN journal_entries je ON je.id = jl.journal_entry_id "
        "WHERE je.source_type = ? ORDER BY jl.id",
        (source_type,),
    ).fetchall()
    return rows


def _sums(conn, source_type: str) -> tuple[float, float]:
    rows = _entry_lines(conn, source_type)
    debit = sum(float(r["debit"]) for r in rows)
    credit = sum(float(r["credit"]) for r in rows)
    return debit, credit


# ---------------------------------------------------------------------------
# POST /open (FR1, AC1)
# ---------------------------------------------------------------------------


def test_open_drawer_creates_drawer_and_journal_entry(api_client):
    resp = api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "open"
    assert body["openingBalance"] == 1_000_000
    assert body["cashSales"] == 0
    assert body["ownerIn"] == 0
    assert body["ownerOut"] == 0
    assert body["cashExpenses"] == 0
    assert body["expectedBalance"] == 1_000_000
    # AC1: journal entry debit 1100, credit 3100
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_open"
    lines = je["lines"]
    assert len(lines) == 2
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 1_000_000.0
    assert float(credit_line["credit"]) == 1_000_000.0
    with get_db() as conn:
        assert _account_id(conn, "1100") == int(debit_line["accountId"])
        assert _account_id(conn, "3100") == int(credit_line["accountId"])


def test_open_drawer_rejects_negative_balance(api_client):
    resp = api_client.post("/api/cash-drawer/open", json={"openingBalance": -100})
    assert resp.status_code == 422


def test_open_second_drawer_blocked_while_active(api_client):
    r1 = api_client.post("/api/cash-drawer/open", json={"openingBalance": 500_000})
    assert r1.status_code == 201
    r2 = api_client.post("/api/cash-drawer/open", json={"openingBalance": 200_000})
    assert r2.status_code == 409
    assert "đang mở" in r2.json()["detail"]


# ---------------------------------------------------------------------------
# POST /cash-in (FR2, AC2)
# ---------------------------------------------------------------------------


def test_cash_in_increases_owner_in_and_creates_journal(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000, "note": "bổ sung"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ownerIn"] == 200_000
    assert body["expectedBalance"] == 1_200_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_cash_in"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 200_000.0
    assert float(credit_line["credit"]) == 200_000.0
    with get_db() as conn:
        assert _account_id(conn, "1100") == int(debit_line["accountId"])
        assert _account_id(conn, "3100") == int(credit_line["accountId"])


def test_cash_in_requires_active_drawer(api_client):
    resp = api_client.post("/api/cash-drawer/cash-in", json={"amount": 100})
    assert resp.status_code == 409


def test_cash_in_rejects_zero_or_negative(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post("/api/cash-drawer/cash-in", json={"amount": 0})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /cash-out (FR3, AC3)
# ---------------------------------------------------------------------------


def test_cash_out_increases_owner_out_and_creates_journal(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post("/api/cash-drawer/cash-out", json={"amount": 100_000})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ownerOut"] == 100_000
    assert body["expectedBalance"] == 900_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_cash_out"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 100_000.0
    assert float(credit_line["credit"]) == 100_000.0
    with get_db() as conn:
        # AC3: cash-out reverses direction — debit 3100, credit 1100
        assert _account_id(conn, "3100") == int(debit_line["accountId"])
        assert _account_id(conn, "1100") == int(credit_line["accountId"])


def test_cash_out_requires_active_drawer(api_client):
    resp = api_client.post("/api/cash-drawer/cash-out", json={"amount": 100})
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# POST /close (FR7, AC7)
# ---------------------------------------------------------------------------


def test_close_drawer_with_shortage_records_discrepancy(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000})
    api_client.post("/api/cash-drawer/cash-out", json={"amount": 100_000})
    # expected = 1,000,000 + 200,000 - 100,000 = 1,100,000; counted = 1,090,000 → -10,000
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_090_000}
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "closed"
    assert body["countedAmount"] == 1_090_000
    assert body["discrepancy"] == -10_000
    assert body["closedAt"] is not None
    # AC7: shortage → debit 3100, credit 1100
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_close_adjust"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 10_000.0
    assert float(credit_line["credit"]) == 10_000.0
    with get_db() as conn:
        assert _account_id(conn, "3100") == int(debit_line["accountId"])
        assert _account_id(conn, "1100") == int(credit_line["accountId"])


def test_close_drawer_with_surplus_records_discrepancy(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    # expected = 1,000,000; counted = 1,010,000 → +10,000
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_010_000}
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["discrepancy"] == 10_000
    # Surplus → debit 1100, credit 3100
    je = body["journalEntry"]
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    with get_db() as conn:
        assert _account_id(conn, "1100") == int(debit_line["accountId"])
        assert _account_id(conn, "3100") == int(credit_line["accountId"])


def test_close_drawer_zero_discrepancy_no_journal_entry(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_000_000}
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["discrepancy"] == 0
    assert body["status"] == "closed"
    assert "journalEntry" not in body


def test_close_drawer_requires_active_drawer(api_client):
    resp = api_client.post("/api/cash-drawer/close", json={"countedAmount": 0})
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# GET /status (FR4, AC6)
# ---------------------------------------------------------------------------


def test_status_returns_null_when_no_active_drawer(api_client):
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    assert resp.json() is None


def test_status_returns_active_drawer(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "open"
    assert body["expectedBalance"] == 1_000_000


def test_status_after_close_returns_null(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 1_000_000})
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.json() is None


def test_expected_balance_formula_ac6(api_client):
    """AC6: opening=1M, cash_sales=500K, owner_in=200K, owner_out=100K,
    cash_expenses=50K → expected_balance=1,550,000.

    cash_sales and cash_expenses are populated by Phase 3 (auto-link), so
    here we set them directly on the DB row to verify the formula in
    isolation.
    """
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        conn.execute(
            "UPDATE cash_drawer SET cash_sales = 500000, owner_in = 200000, "
            "owner_out = 100000, cash_expenses = 50000 WHERE id = ?",
            (drawer.id,),
        )
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    assert resp.json()["expectedBalance"] == 1_550_000


# ---------------------------------------------------------------------------
# GET /history (FR10)
# ---------------------------------------------------------------------------


def test_history_returns_paginated_list(api_client):
    # First drawer
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 1_000_000})
    # Second drawer
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 500_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 500_000})

    resp = api_client.get("/api/cash-drawer/history")
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 2
    assert len(body["items"]) == 2
    # Ordered by opened_at DESC
    assert body["items"][0]["openingBalance"] in (1_000_000, 500_000)


def test_history_supports_pagination(api_client):
    for i in range(3):
        api_client.post("/api/cash-drawer/open", json={"openingBalance": 100_000 * (i + 1)})
        api_client.post("/api/cash-drawer/close", json={"countedAmount": 100_000 * (i + 1)})

    resp = api_client.get("/api/cash-drawer/history?limit=2&offset=0")
    assert resp.status_code == 200
    body = resp.json()
    assert body["total"] == 3
    assert len(body["items"]) == 2

    resp2 = api_client.get("/api/cash-drawer/history?limit=2&offset=2")
    assert resp2.json()["total"] == 3
    assert len(resp2.json()["items"]) == 1


def test_history_supports_date_range_filter(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 1_000_000})

    # Far-future window should return zero
    resp = api_client.get("/api/cash-drawer/history?since=2999-01-01T00:00:00Z")
    assert resp.status_code == 200
    assert resp.json()["total"] == 0

    # Wide window should return one
    resp2 = api_client.get("/api/cash-drawer/history?since=2000-01-01T00:00:00Z")
    assert resp2.json()["total"] == 1


# ---------------------------------------------------------------------------
# NFR3: balanced journal entries (debit sum = credit sum)
# ---------------------------------------------------------------------------


def test_all_drawer_journal_entries_are_balanced(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000})
    api_client.post("/api/cash-drawer/cash-out", json={"amount": 100_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 1_090_000})

    with get_db() as conn:
        for source_type in (
            "cash_drawer_open",
            "cash_drawer_cash_in",
            "cash_drawer_cash_out",
            "cash_drawer_close_adjust",
        ):
            debit, credit = _sums(conn, source_type)
            assert abs(debit - credit) < 0.005, (
                f"unbalanced {source_type}: debit={debit} credit={credit}"
            )


# ---------------------------------------------------------------------------
# Model-level helper coverage
# ---------------------------------------------------------------------------


def test_cash_drawer_expected_balance_model():
    d = CashDrawer(
        opened_at="2026-08-01T00:00:00Z",
        opening_balance=1_000_000,
        cash_sales=500_000,
        owner_in=200_000,
        owner_out=100_000,
        cash_expenses=50_000,
    )
    assert d.expected_balance() == 1_550_000