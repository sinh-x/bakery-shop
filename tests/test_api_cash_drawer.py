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
from baker.db.schema import _account_id_by_code, _insert_journal_entry
from baker.db.schema import ensure_schema
from baker.models.cash_drawer import CashDrawer

# DG-347 Phase 3 removed the _sync_drawer_tien_rut_out call site and the
# tien_rut_out accumulator column from cash_drawer. These delivery tests
# assert on drawer.tien_rut_out, which is no longer updated (drawer balances
# derive from 1101 journal lines). Retained for historical context; skipped
# because the column they assert on no longer exists.
_PHASE3_SKIP = pytest.mark.skip(
    reason="DG-347 Phase 3: _sync_drawer_tien_rut_out removed; "
           "tien_rut_out accumulator column dropped; drawer balances derive "
           "from 1101 journal lines"
)


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
    assert body["expectedBalance"] == 1_000_000
    # AC3: journal entry debit 1101 (Cash in Drawer), credit 3100 (equity)
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_open"
    lines = je["lines"]
    assert len(lines) == 2
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 1_000_000.0
    assert float(credit_line["credit"]) == 1_000_000.0
    with get_db() as conn:
        assert _account_id(conn, "1101") == int(debit_line["accountId"])
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
    assert body["expectedBalance"] == 1_200_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_cash_in"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 200_000.0
    assert float(credit_line["credit"]) == 200_000.0
    with get_db() as conn:
        # AC3: default source=equity → DR 1101, CR 3100
        assert _account_id(conn, "1101") == int(debit_line["accountId"])
        assert _account_id(conn, "3100") == int(credit_line["accountId"])



def test_cash_in_from_owner_cash_debits_1101_credits_1102(api_client):
    """FR3a: cash-in source=owner → DR 1101 (Cash in Drawer), CR 1102 (Owner's Cash)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/cash-in",
        json={"amount": 300_000, "source": "owner"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["expectedBalance"] == 1_300_000
    je = body["journalEntry"]
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    with get_db() as conn:
        assert _account_id(conn, "1101") == int(debit_line["accountId"])
        assert _account_id(conn, "1102") == int(credit_line["accountId"])



def test_cash_in_from_employee_debits_1101_credits_23xx(api_client):
    """FR3a: cash-in source=employee → DR 1101, CR 23XX (staff sub-account created on first use)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/cash-in",
        json={"amount": 150_000, "source": "employee", "staffName": "Nguyễn Văn A"},
    )
    assert resp.status_code == 200, resp.text
    je = resp.json()["journalEntry"]
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    with get_db() as conn:
        assert _account_id(conn, "1101") == int(debit_line["accountId"])
        # The staff sub-account 23XX was created under 2300.
        staff_row = conn.execute(
            "SELECT id, code FROM accounts WHERE name = ? AND parent_id = ?",
            ("Nguyễn Văn A", _account_id(conn, "2300")),
        ).fetchone()
        assert staff_row is not None
        assert staff_row["code"].startswith("23")
        assert int(staff_row["id"]) == int(credit_line["accountId"])


def test_cash_in_employee_without_staff_name_is_rejected(api_client):
    """FR3a: source=employee without staffName → 422."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/cash-in",
        json={"amount": 100_000, "source": "employee"},
    )
    assert resp.status_code == 422


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
    assert body["expectedBalance"] == 900_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_cash_out"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 100_000.0
    assert float(credit_line["credit"]) == 100_000.0
    with get_db() as conn:
        # AC4: default destination=owner → DR 1102 (Owner's Cash), CR 1101 (Cash in Drawer)
        assert _account_id(conn, "1102") == int(debit_line["accountId"])
        assert _account_id(conn, "1101") == int(credit_line["accountId"])



def test_cash_out_to_owner_debits_1102_credits_1101(api_client):
    """AC4: cash-out destination=owner → DR 1102 (Owner's Cash), CR 1101 (Cash in Drawer)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/cash-out",
        json={"amount": 250_000, "destination": "owner"},
    )
    assert resp.status_code == 200, resp.text
    je = resp.json()["journalEntry"]
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    with get_db() as conn:
        assert _account_id(conn, "1102") == int(debit_line["accountId"])
        assert _account_id(conn, "1101") == int(credit_line["accountId"])



def test_cash_out_to_employee_debits_23xx_credits_1101(api_client):
    """AC5: cash-out destination=employee → DR 23XX (staff sub-account created on first use),
    CR 1101 (Cash in Drawer)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/cash-out",
        json={"amount": 100_000, "destination": "employee", "staffName": "Trần Thị B"},
    )
    assert resp.status_code == 200, resp.text
    je = resp.json()["journalEntry"]
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    with get_db() as conn:
        assert _account_id(conn, "1101") == int(credit_line["accountId"])
        staff_row = conn.execute(
            "SELECT id, code FROM accounts WHERE name = ? AND parent_id = ?",
            ("Trần Thị B", _account_id(conn, "2300")),
        ).fetchone()
        assert staff_row is not None
        assert staff_row["code"].startswith("23")
        assert int(staff_row["id"]) == int(debit_line["accountId"])


def test_cash_out_employee_without_staff_name_is_rejected(api_client):
    """FR4: destination=employee without staffName → 422."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/cash-out",
        json={"amount": 100_000, "destination": "employee"},
    )
    assert resp.status_code == 422


def test_cash_out_requires_active_drawer(api_client):
    resp = api_client.post("/api/cash-drawer/cash-out", json={"amount": 100})
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# POST /close (FR7, AC7)
# ---------------------------------------------------------------------------



def test_close_drawer_with_shortage_records_discrepancy(api_client):
    """Close with shortage: first call returns 409 shortageProposal,
    second call with confirmed flag creates DR 3100 / CR 1101."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000})
    api_client.post("/api/cash-drawer/cash-out", json={"amount": 100_000})
    # expected = 1,100,000; counted = 1,090,000 → -10,000
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_090_000}
    )
    assert resp.status_code == 409, resp.text
    detail = resp.json()["detail"]
    p = detail["shortageProposal"]
    assert p["expectedBalance"] == 1_100_000
    assert p["countedAmount"] == 1_090_000
    assert p["shortage"] == 10_000

    resp2 = api_client.post(
        "/api/cash-drawer/close",
        json={
            "countedAmount": 1_090_000,
            "shortageConfirmed": True,
            "shortageSource": "equity_loss",
        },
    )
    assert resp2.status_code == 200, resp2.text
    body = resp2.json()
    assert body["status"] == "closed"
    assert body["discrepancy"] == -10_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_close_adjust"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 10_000.0
    assert float(credit_line["credit"]) == 10_000.0
    with get_db() as conn:
        assert _account_id(conn, "3100") == int(debit_line["accountId"])
        assert _account_id(conn, "1101") == int(credit_line["accountId"])



def test_close_drawer_with_surplus_records_discrepancy(api_client):
    """Close with surplus: first call returns 409 surplusProposal,
    second call with confirmed flag creates DR 1101 / CR 1102."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_010_000}
    )
    assert resp.status_code == 409, resp.text
    detail = resp.json()["detail"]
    p = detail["surplusProposal"]
    assert p["expectedBalance"] == 1_000_000
    assert p["countedAmount"] == 1_010_000
    assert p["surplus"] == 10_000

    resp2 = api_client.post(
        "/api/cash-drawer/close",
        json={
            "countedAmount": 1_010_000,
            "surplusConfirmed": True,
            "surplusSource": "owner_cash",
        },
    )
    assert resp2.status_code == 200, resp2.text
    body = resp2.json()
    assert body["discrepancy"] == 10_000
    je = body["journalEntry"]
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    with get_db() as conn:
        assert _account_id(conn, "1101") == int(debit_line["accountId"])
        assert _account_id(conn, "1102") == int(credit_line["accountId"])


# ---------------------------------------------------------------------------
# DG-331 Phase 2 — Close drawer confirmation gates (FR2-FR8, AC1-AC7, NFR2)
# ---------------------------------------------------------------------------


def _open_with_expected(api_client, *, opening: int, expected: int) -> None:
    """Open a drawer and adjust its expected balance to the target by
    inserting an additional 1101 journal entry linked to the drawer via
    the join table (replaces the legacy direct cash_sales column update)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": opening})
    if expected != opening:
        delta = expected - opening
        with get_db() as conn:
            drawer = CashDrawer.get_active(conn)
            assert drawer is not None
            cash_acct = _account_id(conn, "1101")
            equity_acct = _account_id(conn, "3100")
            _insert_journal_entry(
                conn,
                description=f"Test adjustment: {delta}",
                source_type="cash_drawer_test_adjust",
                source_id=None,
                lines=[
                    (cash_acct, float(delta), 0.0, "test"),
                    (equity_acct, 0.0, float(delta), "test"),
                ],
                drawer_id=drawer.id,
            )



def test_close_surplus_returns_409_with_surplusProposal_ac1(api_client):
    """AC1: close with surplus and surplusSource set but surplusConfirmed
    false → 409 with surplusProposal {expectedBalance, countedAmount, surplus}.
    """
    # expected = 2,000,000; counted = 3,000,000 → surplus = 1,000,000
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close",
        json={"countedAmount": 3_000_000, "surplusSource": "owner_cash"},
    )
    assert resp.status_code == 409, resp.text
    detail = resp.json()["detail"]
    assert "surplusProposal" in detail
    proposal = detail["surplusProposal"]
    assert proposal["expectedBalance"] == 2_000_000
    assert proposal["countedAmount"] == 3_000_000
    assert proposal["surplus"] == 1_000_000



def test_close_surplus_owner_cash_creates_dr1101_cr1102_ac2(api_client):
    """AC2: close surplus with surplusConfirmed + surplusSource=owner_cash
    → DR 1101 (Cash in Drawer) / CR 1102 (Owner's Cash); discrepancy stored."""
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close",
        json={
            "countedAmount": 3_000_000,
            "surplusConfirmed": True,
            "surplusSource": "owner_cash",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "closed"
    assert body["discrepancy"] == 1_000_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_close_adjust"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 1_000_000.0
    assert float(credit_line["credit"]) == 1_000_000.0
    with get_db() as conn:
        assert _account_id(conn, "1101") == int(debit_line["accountId"])
        assert _account_id(conn, "1102") == int(credit_line["accountId"])



def test_close_surplus_unidentified_sale_creates_compound_entry_ac3(api_client):
    """AC3: close surplus with surplusSource=unidentified_sale → compound
    entry DR 1101/CR 4100 (revenue) + DR 5900/CR 1300 (50% COGS)."""
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close",
        json={
            "countedAmount": 3_000_000,
            "surplusConfirmed": True,
            "surplusSource": "unidentified_sale",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["discrepancy"] == 1_000_000
    # Compound entry returned under surplusJournalEntry key.
    je = body["surplusJournalEntry"]
    assert je["sourceType"] == "cash_drawer_close_adjust"
    lines = je["lines"]
    assert len(lines) == 4
    # All four accounts (1101, 4100, 5900, 1300) must be present.
    with get_db() as conn:
        expected_accts = {
            int(_account_id(conn, c)) for c in ("1101", "4100", "5900", "1300")
        }
    line_accts = {int(l["accountId"]) for l in lines}
    assert line_accts == expected_accts
    # Balanced entry (NFR1).
    debit_sum = sum(float(l["debit"]) for l in lines)
    credit_sum = sum(float(l["credit"]) for l in lines)
    assert abs(debit_sum - credit_sum) < 0.005
    # Revenue line credit = 1,000,000; COGS line debit = 500,000 (50%).
    with get_db() as conn:
        rev_id = _account_id(conn, "4100")
        cogs_id = _account_id(conn, "5900")
        cash_id = _account_id(conn, "1101")
        inv_id = _account_id(conn, "1300")
    rev_line = next(l for l in lines if int(l["accountId"]) == rev_id)
    cogs_line = next(l for l in lines if int(l["accountId"]) == cogs_id)
    cash_line = next(l for l in lines if int(l["accountId"]) == cash_id)
    inv_line = next(l for l in lines if int(l["accountId"]) == inv_id)
    assert float(cash_line["debit"]) == 1_000_000.0
    assert float(rev_line["credit"]) == 1_000_000.0
    assert float(cogs_line["debit"]) == 500_000.0
    assert float(inv_line["credit"]) == 500_000.0



def test_close_shortage_returns_409_with_shortageProposal_ac4(api_client):
    """AC4: close with shortage and shortageSource set but shortageConfirmed
    false → 409 with shortageProposal {expectedBalance, countedAmount, shortage}.
    """
    # expected = 2,000,000; counted = 1,500,000 → shortage = 500,000
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close",
        json={"countedAmount": 1_500_000, "shortageSource": "owner_withdraw"},
    )
    assert resp.status_code == 409, resp.text
    detail = resp.json()["detail"]
    assert "shortageProposal" in detail
    proposal = detail["shortageProposal"]
    assert proposal["expectedBalance"] == 2_000_000
    assert proposal["countedAmount"] == 1_500_000
    assert proposal["shortage"] == 500_000



def test_close_shortage_owner_withdraw_creates_dr1102_cr1101_ac5(api_client):
    """AC5: close shortage with shortageConfirmed + shortageSource=owner_withdraw
    → DR 1102 (Owner's Cash) / CR 1101 (Cash in Drawer); discrepancy stored."""
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close",
        json={
            "countedAmount": 1_500_000,
            "shortageConfirmed": True,
            "shortageSource": "owner_withdraw",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["discrepancy"] == -500_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_close_adjust"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 500_000.0
    assert float(credit_line["credit"]) == 500_000.0
    with get_db() as conn:
        assert _account_id(conn, "1102") == int(debit_line["accountId"])
        assert _account_id(conn, "1101") == int(credit_line["accountId"])



def test_close_shortage_equity_loss_creates_dr3100_cr1101_ac6(api_client):
    """AC6: close shortage with shortageConfirmed + shortageSource=equity_loss
    → DR 3100 (Equity) / CR 1101 (Cash in Drawer); discrepancy stored."""
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close",
        json={
            "countedAmount": 1_500_000,
            "shortageConfirmed": True,
            "shortageSource": "equity_loss",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["discrepancy"] == -500_000
    je = body["journalEntry"]
    assert je["sourceType"] == "cash_drawer_close_adjust"
    lines = je["lines"]
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    assert float(debit_line["debit"]) == 500_000.0
    assert float(credit_line["credit"]) == 500_000.0
    with get_db() as conn:
        assert _account_id(conn, "3100") == int(debit_line["accountId"])
        assert _account_id(conn, "1101") == int(credit_line["accountId"])



def test_close_zero_discrepancy_no_confirmation_required_ac7(api_client):
    """AC7: zero discrepancy close → no journal entry, no confirmation flags
    needed. Drawer closes normally."""
    _open_with_expected(api_client, opening=2_000_000, expected=2_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 2_000_000}
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["discrepancy"] == 0
    assert body["status"] == "closed"
    assert "journalEntry" not in body
    assert "surplusJournalEntry" not in body
    assert "shortageJournalEntry" not in body



def test_close_surplus_old_client_without_flags_backward_compat_nfr2(api_client):
    """NFR2: old client sends close with only countedAmount (no
    surplusConfirmed / surplusSource) → gets 409 surplusProposal just like
    new clients — the confirmation gate triggers for any unconfirmed
    discrepancy."""
    _open_with_expected(api_client, opening=1_000_000, expected=1_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_100_000}
    )
    assert resp.status_code == 409, resp.text
    body = resp.json()
    detail = body["detail"]
    p = detail["surplusProposal"]
    assert p["expectedBalance"] == 1_000_000
    assert p["countedAmount"] == 1_100_000
    assert p["surplus"] == 100_000



def test_close_shortage_old_client_without_flags_backward_compat_nfr2(api_client):
    """NFR2: old client sends close with only countedAmount (no
    shortageConfirmed / shortageSource) → gets 409 shortageProposal just
    like new clients — the confirmation gate triggers for any unconfirmed
    discrepancy."""
    _open_with_expected(api_client, opening=1_000_000, expected=1_000_000)
    resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 900_000}
    )
    assert resp.status_code == 409, resp.text
    body = resp.json()
    detail = body["detail"]
    p = detail["shortageProposal"]
    assert p["expectedBalance"] == 1_000_000
    assert p["countedAmount"] == 900_000
    assert p["shortage"] == 100_000


def test_close_drawer_requires_active_drawer(api_client):
    resp = api_client.post("/api/cash-drawer/close", json={"countedAmount": 0})
    assert resp.status_code == 409


def test_closing_balance_equals_expected_balance(api_client):
    """Regression test DG-350: closing_balance matches the journal-derived
    expected_balance (SUM of all linked 1101 journal lines) for a closed
    drawer.

    opening 500,000 (DR 1101) + cash-in 200,000 (DR 1101) − cash-out 50,000
    (CR 1101) = 650,000 expected balance. The close endpoint persists
    closing_balance = expected_balance at close time; this test verifies the
    persisted value equals the 1101 journal sum computed independently.
    """
    # 1. Open drawer
    resp = api_client.post("/api/cash-drawer/open", json={"openingBalance": 500_000})
    assert resp.status_code in (200, 201), resp.text

    # 2. Create linked 1101 entries via cash-in and cash-out
    ci = api_client.post(
        "/api/cash-drawer/cash-in",
        json={"amount": 200_000, "source": "owner", "method": "cash"},
    )
    assert ci.status_code == 200, ci.text
    co = api_client.post(
        "/api/cash-drawer/cash-out",
        json={"amount": 50_000, "destination": "owner", "method": "cash"},
    )
    assert co.status_code == 200, co.text

    # 3. Close the drawer (counted == expected → no confirmation gate)
    resp = api_client.post("/api/cash-drawer/close", json={"countedAmount": 650_000})
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "closed"

    # 4. Get drawer_id from history
    hist_resp = api_client.get("/api/cash-drawer/history?limit=1")
    assert hist_resp.status_code == 200
    items = hist_resp.json()["items"]
    assert len(items) >= 1
    drawer_id = int(items[0]["id"])

    # 5. Assert closing_balance == journal-derived 1101 sum (the formula
    #    used by expected_balance() for open drawers). For closed drawers
    #    expected_balance() short-circuits to closing_balance, so compute
    #    the journal sum directly to make this a meaningful regression check.
    with get_db() as conn:
        drawer = CashDrawer.get_by_id(conn, drawer_id)
        assert drawer is not None
        assert drawer.status == "closed"
        assert drawer.closing_balance == 650_000

        row = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
            FROM cash_drawer_journal_entries cdje
            JOIN journal_lines jl ON jl.journal_entry_id = cdje.journal_entry_id
            JOIN accounts a ON a.id = jl.account_id
            WHERE cdje.cash_drawer_id = ? AND a.code = '1101'
            """,
            (drawer_id,),
        ).fetchone()
        journal_sum = int(row["balance"])

    assert drawer.closing_balance == journal_sum, (
        f"closing_balance {drawer.closing_balance} != "
        f"journal-derived 1101 sum {journal_sum}"
    )
    # Also verify via the API history response.
    assert int(items[0]["closingBalance"]) == journal_sum


# ---------------------------------------------------------------------------
# GET /status (FR4, AC6)
# ---------------------------------------------------------------------------


def test_status_returns_accounting_balance_when_no_active_drawer(api_client):
    # FR3 (DG-337 phase 4.1): /status must always return accountingBalance1101,
    # even when no active drawer and no closed-drawer history exist.
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    assert body is not None
    assert body.get("activeDrawer") is None
    assert "accountingBalance1101" in body
    assert isinstance(body["accountingBalance1101"], int)



def test_status_returns_active_drawer(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "open"
    assert body["expectedBalance"] == 1_000_000



def test_status_after_close_returns_previous_counted_amount(api_client):
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 1_000_000})
    resp = api_client.get("/api/cash-drawer/status")
    # DG-331 FR9: when no active drawer but a closed drawer exists, status
    # returns previousCloseCountedAmount (counted_amount of most recent closed
    # drawer) instead of null, for display in the open dialog.
    body = resp.json()
    assert body is not None
    assert body.get("activeDrawer") is None
    assert body["previousCloseCountedAmount"] == 1_000_000



def test_expected_balance_formula_ac6(api_client):
    """AC6/FR1: opening=1M, +500K test adjustment → expected_balance=1,500,000.

    The legacy accumulator formula (cash_sales + owner_in - owner_out -
    cash_expenses + tien_rut_in - tien_rut_out) is now replaced by the sum of
    1101 journal lines linked to the drawer via the join table, so we inject
    a 500K 1101 journal entry to verify the journal-derived balance.
    """
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        cash_acct = _account_id(conn, "1101")
        equity_acct = _account_id(conn, "3100")
        _insert_journal_entry(
            conn,
            description="Test +500K",
            source_type="cash_drawer_test_adjust",
            source_id=None,
            lines=[
                (cash_acct, 500_000.0, 0.0, "test"),
                (equity_acct, 0.0, 500_000.0, "test"),
            ],
            drawer_id=drawer.id,
        )
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    assert resp.json()["expectedBalance"] == 1_500_000


# ---------------------------------------------------------------------------
# GET /history (FR10)
# ---------------------------------------------------------------------------



def test_history_returns_paginated_list(api_client):
    # First drawer
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/close", json={"countedAmount": 1_000_000})
    # Second drawer — 1101 balance from first open requires transfer confirmation
    api_client.post("/api/cash-drawer/open", json={
        "openingBalance": 500_000,
        "transferConfirmed": True,
    })
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
        opening = 100_000 * (i + 1)
        # First open (100k): no prior 1101 balance → no gate
        # Second open (200k): > 1101 balance (100k) → excess gate → ownerCapital
        # Third open (300k): > 1101 balance (200k now, not 400k like before fix)
        #   → excess gate → stockRecon+unidSale
        payload: dict = {"openingBalance": opening}
        if i == 1:
            payload["ownerCapitalConfirmed"] = True
        elif i == 2:
            payload["stockReconciliationConfirmed"] = True
            payload["unidentifiedSaleConfirmed"] = True
        open_resp = api_client.post("/api/cash-drawer/open", json=payload)
        assert open_resp.status_code in (200, 201), open_resp.text
        # Close with the journal-derived expected balance so no confirmation
        # gate triggers (DG-347 Phase 2: expected_balance is per-drawer 1101
        # sum, which may differ from opening_balance when carry-over journals
        # only the delta).
        status = api_client.get("/api/cash-drawer/status").json()
        counted = status["expectedBalance"]
        close_resp = api_client.post(
            "/api/cash-drawer/close", json={"countedAmount": counted}
        )
        assert close_resp.status_code == 200, close_resp.text

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



def test_1101_balance_equals_drawer_expected_balance_nfr4(api_client):
    """NFR4/AC3: the 1101 (Cash in Drawer) journal balance must equal the
    drawer expected balance while the drawer is open.

    open 1,000,000 (DR 1101) + cash-in 200,000 (DR 1101) − cash-out 100,000
    (CR 1101) = 1,100,000 expected balance → 1101 net debit balance = 1,100,000.
    """
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000})
    api_client.post("/api/cash-drawer/cash-out", json={"amount": 100_000})
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    expected_balance = resp.json()["expectedBalance"]
    with get_db() as conn:
        row = conn.execute(
            "SELECT "
            "COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS net "
            "FROM journal_lines jl "
            "JOIN journal_entries je ON je.id = jl.journal_entry_id "
            "JOIN accounts a ON a.id = jl.account_id "
            "WHERE a.code = '1101' "
            "  AND je.source_type IN "
            "    ('cash_drawer_open','cash_drawer_cash_in','cash_drawer_cash_out')",
        ).fetchone()
        net_1101 = float(row["net"])
    assert abs(net_1101 - expected_balance) < 0.005, (
        f"1101 net balance {net_1101} != drawer expected {expected_balance}"
    )


# ---------------------------------------------------------------------------
# Model-level helper coverage
# ---------------------------------------------------------------------------


def test_cash_drawer_expected_balance_model():
    """Unit-level: expected_balance() without a conn falls back to
    opening_balance for open drawers and closing_balance for closed drawers.
    The full journal-derived balance is exercised via the API tests below."""
    d_open = CashDrawer(
        opened_at="2026-08-01T00:00:00Z",
        opening_balance=1_000_000,
    )
    assert d_open.expected_balance() == 1_000_000
    d_closed = CashDrawer(
        opened_at="2026-08-01T00:00:00Z",
        opening_balance=1_000_000,
        status="closed",
        closing_balance=1_550_000,
    )
    assert d_closed.expected_balance() == 1_550_000


# ---------------------------------------------------------------------------
# DG-341 Phase 3 — tien rut delivery lifecycle (FR3, NFR3, AC2, AC7)
# ---------------------------------------------------------------------------


def _create_order_with_tien_rut(client, cash_amount=200000):
    """Create an order with a tien_rut work item and return the response."""
    resp = client.post("/api/orders", json={
        "customerName": "Khách Rút Tiền",
        "dueDate": "2026-08-10",
        "items": [{
            "productName": "Bánh kem",
            "quantity": 1,
            "unitPrice": 350000,
            "attributes": {
                "rut_tien": "true",
                "cash_amount": str(cash_amount),
                "cash_fee": "20000",
            },
        }],
    })
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _advance_to_delivered(client, ref):
    """Walk the order through status transitions up to ``delivered``."""
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        resp = client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": "Tiến độ bình thường"},
        )
        assert resp.status_code == 200, resp.text



@_PHASE3_SKIP
def test_tien_rut_out_increases_on_delivery_ac2(api_client):
    """AC2: Given an open drawer with ``tienRutIn`` = 500,000, when the order
    is delivered, then ``tienRutOut`` = 500,000 and ``expectedBalance``
    decreases by 500,000.
    """
    # Open a drawer with a known opening balance.
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    # Create an order with a tien rut item.
    order = _create_order_with_tien_rut(api_client, cash_amount=500000)
    ref = order["orderRef"]
    # Customer gives 500,000 cash for safekeeping (tien_rut deposit inflow).
    _create_txn(api_client, ref, amount=500000, type="tien_rut", method="cash")

    status_before = api_client.get("/api/cash-drawer/status").json()
    assert status_before["tienRutIn"] == 500000
    assert status_before["tienRutOut"] == 0
    expected_before = status_before["expectedBalance"]
    # expected_balance = 1,000,000 + 0 + 500,000 + 0 - 0 - 0 - 0 = 1,500,000
    assert expected_before == 1_500_000

    # Advance the order to delivered.
    _advance_to_delivered(api_client, ref)

    status_after = api_client.get("/api/cash-drawer/status").json()
    assert status_after["tienRutIn"] == 500000  # in column preserved (audit trail)
    assert status_after["tienRutOut"] == 500000
    # expected_balance drops by 500,000
    assert status_after["expectedBalance"] == expected_before - 500000



@_PHASE3_SKIP
def test_tien_rut_delivery_skips_closed_drawer_ac7(api_client):
    """AC7: Given an order with tien rut is delivered and the linked drawer is
    already closed, the delivery does not modify the closed drawer (no crash,
    no error).
    """
    # Open a drawer and record a tien_rut payment against it.
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    order = _create_order_with_tien_rut(api_client, cash_amount=200000)
    ref = order["orderRef"]
    _create_txn(api_client, ref, amount=200000, type="tien_rut", method="cash")
    # Close the drawer (freeze its totals).
    close_resp = api_client.post(
        "/api/cash-drawer/close", json={"countedAmount": 1_200_000}
    )
    assert close_resp.status_code == 200
    closed_drawer = close_resp.json()
    assert closed_drawer["status"] == "closed"
    assert closed_drawer["tienRutOut"] == 0
    closed_expected = closed_drawer["expectedBalance"]

    # Advance the order to delivered after the drawer is closed.
    _advance_to_delivered(api_client, ref)

    # No crash; closed drawer totals are unchanged (frozen).
    with get_db() as conn:
        drawer = CashDrawer.get_by_id(conn, int(closed_drawer["id"]))
    assert drawer.status == "closed"
    assert drawer.tien_rut_out == 0
    assert drawer.expected_balance() == closed_expected


def test_tien_rut_delivery_no_active_drawer_no_error(api_client):
    """Delivery of an order with tien rut when no drawer was ever opened must
    not crash (no cash_drawer_id link → no drawer to update)."""
    order = _create_order_with_tien_rut(api_client, cash_amount=200000)
    ref = order["orderRef"]
    # Non-cash tien_rut (transfer) leaves no drawer link and must not error.
    resp = api_client.post(
        f"/api/orders/{ref}/transactions",
        json={"amount": 200000, "type": "tien_rut", "method": "transfer"},
    )
    assert resp.status_code == 201
    _advance_to_delivered(api_client, ref)
    # No drawer exists; the status endpoint reports no active drawer.
    status = api_client.get("/api/cash-drawer/status").json()
    assert status["activeDrawer"] is None



@_PHASE3_SKIP
def test_tien_rut_delivery_invalidated_payment_skipped(api_client):
    """An invalidated tien_rut payment must not contribute to tien_rut_out at
    delivery (the inflow was already reversed from tien_rut_in on invalidate).
    """
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    order = _create_order_with_tien_rut(api_client, cash_amount=200000)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=200000, type="tien_rut", method="cash")
    # Invalidate the payment (reverses tien_rut_in).
    inv = api_client.post(f"/api/orders/{ref}/transactions/{txn['id']}/invalidate",
                          json={"invalidatedBy": "test"})
    assert inv.status_code == 200
    # tien_rut_in has been reversed back to 0.
    status = api_client.get("/api/cash-drawer/status").json()
    assert status["tienRutIn"] == 0

    _advance_to_delivered(api_client, ref)

    status_after = api_client.get("/api/cash-drawer/status").json()
    # The invalidated payment is excluded → tien_rut_out stays 0.
    assert status_after["tienRutOut"] == 0


# ---------------------------------------------------------------------------
# DG-347 Phase 1 — Schema migration verification (AC3, AC4, AC5)
# ---------------------------------------------------------------------------


def _cash_drawer_columns(conn):
    return {r[1] for r in conn.execute("PRAGMA table_info(cash_drawer)").fetchall()}


def _payment_transactions_columns(conn):
    return {r[1] for r in conn.execute("PRAGMA table_info(payment_transactions)").fetchall()}


def _events_columns(conn):
    return {r[1] for r in conn.execute("PRAGMA table_info(events)").fetchall()}


def test_v095_closing_balance_column_exists(api_client):
    """AC3: closing_balance column exists on cash_drawer after migration."""
    with get_db() as conn:
        cols = _cash_drawer_columns(conn)
    assert "closing_balance" in cols, f"closing_balance missing; got {sorted(cols)}"


def test_v095_accumulator_columns_dropped(api_client):
    """AC3: accumulator columns do not exist on cash_drawer after migration."""
    with get_db() as conn:
        cols = _cash_drawer_columns(conn)
    for col in ("cash_sales", "tien_rut_in", "tien_rut_out",
                "owner_in", "owner_out", "cash_expenses"):
        assert col not in cols, f"{col} should have been dropped; got {sorted(cols)}"


def test_v095_join_table_exists_with_unique_constraint(api_client):
    """AC4: cash_drawer_journal_entries table exists with both columns and a
    unique constraint on the pair."""
    with get_db() as conn:
        # Table exists.
        row = conn.execute(
            "SELECT name, sql FROM sqlite_master WHERE type='table' "
            "AND name='cash_drawer_journal_entries'"
        ).fetchone()
        assert row is not None, "cash_drawer_journal_entries table missing"
        # Both columns exist.
        cols = {
            r[1] for r in conn.execute(
                "PRAGMA table_info(cash_drawer_journal_entries)"
            ).fetchall()
        }
        assert "cash_drawer_id" in cols, f"cash_drawer_id missing; got {sorted(cols)}"
        assert "journal_entry_id" in cols, f"journal_entry_id missing; got {sorted(cols)}"
        # Unique constraint on the pair exists. The table-level UNIQUE(...) is
        # declared in the CREATE TABLE sql and backed by an auto-index whose
        # sql is NULL — so check the table sql text and the auto-index name.
        table_sql = row["sql"] or ""
        assert "UNIQUE(cash_drawer_id, journal_entry_id)" in table_sql, (
            f"UNIQUE(cash_drawer_id, journal_entry_id) not in table sql: {table_sql}"
        )
        # The auto-index for a table-level UNIQUE has a name like
        # sqlite_autoindex_cash_drawer_journal_entries_1.
        auto_idx = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name='cash_drawer_journal_entries' "
            "AND name LIKE 'sqlite_autoindex_%'"
        ).fetchone()
        assert auto_idx is not None, "no sqlite_autoindex for the UNIQUE constraint"


def test_v095_cash_drawer_id_dropped_from_payment_transactions(api_client):
    """AC5: cash_drawer_id column does not exist on payment_transactions."""
    with get_db() as conn:
        cols = _payment_transactions_columns(conn)
    assert "cash_drawer_id" not in cols, (
        f"cash_drawer_id should have been dropped; got {sorted(cols)}"
    )


def test_v095_cash_drawer_id_dropped_from_events(api_client):
    """AC5: cash_drawer_id column does not exist on events."""
    with get_db() as conn:
        cols = _events_columns(conn)
    assert "cash_drawer_id" not in cols, (
        f"cash_drawer_id should have been dropped; got {sorted(cols)}"
    )


def test_v095_migration_idempotent_on_rerun(api_client):
    """NFR2: re-running v095 on an already-migrated DB is a no-op.

    Applies ensure_schema again on the same connection and verifies the
    schema is unchanged (no error, same columns).
    """
    with get_db() as conn:
        before_cd = _cash_drawer_columns(conn)
        before_pt = _payment_transactions_columns(conn)
        before_ev = _events_columns(conn)
        # Re-applying should be a no-op (schema_version already at 95).
        ensure_schema(conn)
        after_cd = _cash_drawer_columns(conn)
        after_pt = _payment_transactions_columns(conn)
        after_ev = _events_columns(conn)
    assert before_cd == after_cd
    assert before_pt == after_pt
    assert before_ev == after_ev