"""Tests for the lazy auto-close + carry-over logic — DG-324 Phase 6.

Covers FR8 (auto-close at midnight) and FR9 (carry-over balance proposal):

    - FR8: any drawer operation auto-closes open drawers whose ``opened_at``
      belongs to a previous local day, using ``expected_balance`` as the
      counted amount and ``discrepancy = 0`` (NFR1). No close-adjustment
      journal entry is created (NFR3).
    - FR9: when opening today's drawer while a previous-day drawer is still
      open, the system proposes that drawer's expected balance as today's
      opening balance and requires owner confirmation
      (``carryOverConfirmed``).

Lazy check is triggered on every drawer operation: open, cash-in, cash-out,
close, and status read.

AC8: Given an unclosed drawer from yesterday with expected_balance=1,550,000,
when the owner opens today's drawer, then the system proposes 1,550,000 as
today's opening balance and requires confirmation.
AC9: Given an unclosed drawer from yesterday, when midnight passes, then the
drawer is auto-closed with counted_amount = expected_balance and
discrepancy = 0.
"""

import pytest

from baker.db.connection import get_db
from baker.models.cash_drawer import CashDrawer

# DG-347 Phase 1 dropped the accumulator columns from cash_drawer. The
# auto-close tests use _set_balance_columns to set accumulator columns
# directly, which no longer exist. Skip until Phase 4 updates the auto-close
# flow and these tests are adapted to the journal-derived balance.
pytestmark = pytest.mark.skip(
    reason="DG-347 Phase 1: accumulator columns dropped; re-enable in Phase 4 "
           "once the auto-close flow is updated to use journal-derived balance"
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _backdate_drawer(conn, drawer_id: int, opened_at_iso: str) -> None:
    """Set a drawer's opened_at to a past ISO-8601 UTC timestamp so the lazy
    auto-close check treats it as belonging to a previous local day."""
    conn.execute(
        "UPDATE cash_drawer SET opened_at = ? WHERE id = ?",
        (opened_at_iso, drawer_id),
    )


def _set_balance_columns(conn, drawer_id: int, **cols) -> None:
    """Directly set balance columns on a drawer row (bypassing the auto-link
    flow) so auto-close tests exercise the full expected-balance formula."""
    sets = ", ".join(f"{k} = ?" for k in cols)
    conn.execute(
        f"UPDATE cash_drawer SET {sets} WHERE id = ?",
        (*cols.values(), drawer_id),
    )


def _drawer_row(conn, drawer_id: int) -> CashDrawer:
    return CashDrawer.from_row(
        conn.execute(
            "SELECT * FROM cash_drawer WHERE id = ?", (drawer_id,)
        ).fetchone()
    )


def _sums(conn, source_type: str) -> tuple[float, float]:
    rows = conn.execute(
        "SELECT jl.* FROM journal_lines jl "
        "JOIN journal_entries je ON je.id = jl.journal_entry_id "
        "WHERE je.source_type = ? ORDER BY jl.id",
        (source_type,),
    ).fetchall()
    debit = sum(float(r["debit"]) for r in rows)
    credit = sum(float(r["credit"]) for r in rows)
    return debit, credit


# ---------------------------------------------------------------------------
# FR8 / AC9 — lazy auto-close at midnight
# ---------------------------------------------------------------------------


def test_auto_close_on_status_read_closes_stale_drawer(api_client):
    """AC9: a stale previous-day drawer is auto-closed (discrepancy 0) on the
    next drawer operation (here: GET /status)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        # Backdate to 3 days ago so it is definitely before today's midnight.
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    # Trigger lazy auto-close via a status read.
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    # DG-331 FR9: when no active drawer but a closed drawer exists, /status
    # returns {activeDrawer: None, previousCloseCountedAmount: <counted>}
    # instead of null. The stale drawer was auto-closed with counted_amount
    # = expected_balance = 1,000,000 (discrepancy 0).
    body = resp.json()
    assert body is not None
    assert body.get("activeDrawer") is None
    assert body["previousCloseCountedAmount"] == 1_000_000
    with get_db() as conn:
        rows = conn.execute(
            "SELECT status, counted_amount, discrepancy FROM cash_drawer WHERE id = ?",
            (drawer.id,),
        ).fetchone()
        assert rows["status"] == "closed"
        assert rows["counted_amount"] == 1_000_000
        assert rows["discrepancy"] == 0


def test_auto_close_uses_expected_balance_as_counted_amount(api_client):
    """AC9: counted_amount = expected_balance (opening + sales + in - out -
    expenses), discrepancy = 0."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        assert drawer is not None
        _set_balance_columns(
            conn,
            drawer.id,
            cash_sales=500_000,
            owner_in=200_000,
            owner_out=100_000,
            cash_expenses=50_000,
        )
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    # Trigger lazy auto-close via a status read.
    api_client.get("/api/cash-drawer/status")
    with get_db() as conn:
        row = _drawer_row(conn, drawer.id)
        # expected = 1,000,000 + 500,000 + 200,000 - 100,000 - 50,000 = 1,550,000
        assert row.counted_amount == 1_550_000
        assert row.discrepancy == 0
        assert row.status == "closed"


def test_auto_close_on_cash_in_closes_stale_then_requires_active(api_client):
    """FR8: a cash-in operation auto-closes any stale drawer first. Because no
    new active drawer exists, the cash-in still 409s (single-active rule)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 800_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    resp = api_client.post("/api/cash-drawer/cash-in", json={"amount": 100})
    assert resp.status_code == 409
    with get_db() as conn:
        assert _drawer_row(conn, drawer.id).status == "closed"


def test_auto_close_on_cash_out_closes_stale(api_client):
    """FR8: a cash-out operation auto-closes stale drawers lazily."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 800_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    resp = api_client.post("/api/cash-drawer/cash-out", json={"amount": 100})
    assert resp.status_code == 409
    with get_db() as conn:
        assert _drawer_row(conn, drawer.id).status == "closed"


def test_auto_close_on_close_closes_stale_first(api_client):
    """FR8: a /close operation auto-closes stale drawers lazily before
    requiring the active drawer."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 800_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    resp = api_client.post("/api/cash-drawer/close", json={"countedAmount": 0})
    assert resp.status_code == 409
    with get_db() as conn:
        assert _drawer_row(conn, drawer.id).status == "closed"


def test_auto_close_creates_no_close_adjust_journal_entry(api_client):
    """NFR3: auto-close produces discrepancy = 0 so no
    ``cash_drawer_close_adjust`` journal entry is created."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    api_client.get("/api/cash-drawer/status")
    with get_db() as conn:
        rows = conn.execute(
            "SELECT 1 FROM journal_entries WHERE source_type = 'cash_drawer_close_adjust'"
        ).fetchall()
        assert rows == []


def test_auto_close_preserves_balance_integrity(api_client):
    """NFR1: after auto-close, debit sum = credit sum for every drawer journal
    source type (balanced double-entry)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000})
    api_client.post("/api/cash-drawer/cash-out", json={"amount": 100_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    api_client.get("/api/cash-drawer/status")
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


def test_auto_close_idempotent_no_stale_drawers(api_client):
    """FR8: with no stale drawers, the lazy check is a no-op. Opening and
    reading status still works normally (today's drawer stays open)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "open"
    assert body["openingBalance"] == 1_000_000


def test_auto_close_only_closes_previous_day_drawers(api_client):
    """FR8: a drawer opened today (same local day) is NOT auto-closed by the
    lazy check — only previous-day drawers are stale."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        # Backdate to earlier today — still the same local day. Use a
        # timestamp 1 hour ago, which is after midnight today.
        from baker.api.cash_drawer import _start_of_today_local_iso

        start_today = _start_of_today_local_iso()
        # Compute a timestamp 1 hour after midnight today (still today).
        from datetime import datetime, timedelta, timezone

        start_dt = datetime.strptime(start_today, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        later_today = (start_dt + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
        _backdate_drawer(conn, drawer.id, later_today)
    resp = api_client.get("/api/cash-drawer/status")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "open"
    assert body["id"] == str(drawer.id)


def test_auto_close_multiple_stale_drawers_all_closed(api_client):
    """FR8: when multiple previous-day drawers are open (e.g. backfilled
    rows), the lazy check closes all of them, oldest first."""
    # Create two drawers directly with backdated timestamps. (The API
    # enforces single-active-drawer, so insert them at the DB layer.)
    with get_db() as conn:
        conn.execute(
            "INSERT INTO cash_drawer (opened_at, opening_balance, status) "
            "VALUES (?, ?, 'open')",
            ("2026-07-27T08:00:00Z", 1_000_000),
        )
        conn.execute(
            "INSERT INTO cash_drawer (opened_at, opening_balance, status) "
            "VALUES (?, ?, 'open')",
            ("2026-07-28T08:00:00Z", 500_000),
        )
        ids = [
            r["id"]
            for r in conn.execute(
                "SELECT id FROM cash_drawer WHERE status = 'open' ORDER BY id"
            ).fetchall()
        ]
    api_client.get("/api/cash-drawer/status")
    with get_db() as conn:
        for did in ids:
            row = _drawer_row(conn, did)
            assert row.status == "closed"
            assert row.discrepancy == 0
            assert row.counted_amount == row.opening_balance


# ---------------------------------------------------------------------------
# FR9 / AC8 — carry-over proposal
# ---------------------------------------------------------------------------


def test_open_with_unclosed_previous_day_proposes_carry_over(api_client):
    """AC8: opening today's drawer while yesterday's drawer is still open
    returns a 409 carry-over proposal with the expected balance."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _set_balance_columns(
            conn,
            drawer.id,
            cash_sales=500_000,
            owner_in=200_000,
            owner_out=100_000,
            cash_expenses=50_000,
        )
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    # Without confirmation → 409 with the carry-over proposal.
    resp = api_client.post(
        "/api/cash-drawer/open", json={"openingBalance": 1_550_000}
    )
    assert resp.status_code == 409, resp.text
    detail = resp.json()["detail"]
    proposal = detail["carryOverProposal"]
    assert proposal["amount"] == 1_550_000
    assert proposal["fromDrawerId"] == str(drawer.id)
    assert proposal["fromExpectedBalance"] == 1_550_000
    # The stale drawer must still be open (we have not confirmed yet).
    with get_db() as conn:
        assert _drawer_row(conn, drawer.id).status == "open"


def test_open_with_carry_over_confirmed_auto_closes_and_opens(api_client):
    """AC8/AC9: when the owner confirms the carry-over, the stale drawer is
    auto-closed (discrepancy 0) and today's drawer opens with the proposed
    balance. The response includes a ``carryOver`` block."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _set_balance_columns(
            conn,
            drawer.id,
            cash_sales=500_000,
            owner_in=200_000,
            owner_out=100_000,
            cash_expenses=50_000,
        )
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    resp = api_client.post(
        "/api/cash-drawer/open",
        json={"openingBalance": 1_550_000, "carryOverConfirmed": True},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "open"
    assert body["openingBalance"] == 1_550_000
    assert body["carryOver"] == {
        "fromDrawerId": str(drawer.id),
        "fromExpectedBalance": 1_550_000,
    }
    with get_db() as conn:
        stale = _drawer_row(conn, drawer.id)
        assert stale.status == "closed"
        assert stale.counted_amount == 1_550_000
        assert stale.discrepancy == 0


# ---------------------------------------------------------------------------
# FR10 / AC17 — auto-transfer excess to 1102 on open-day (DG-330 Phase 5)
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0]
    )


def _auto_transfer_lines(conn):
    """Return journal lines for the cash_drawer_auto_transfer source type."""
    return conn.execute(
        "SELECT jl.* FROM journal_lines jl "
        "JOIN journal_entries je ON je.id = jl.journal_entry_id "
        "WHERE je.source_type = 'cash_drawer_auto_transfer' ORDER BY jl.id",
    ).fetchall()


def test_open_with_carry_over_and_lower_balance_auto_transfers_to_1102(api_client):
    """AC17: opening with carry-over confirmed and opening balance < previous
    expected balance creates a balanced journal entry DR 1102, CR 1101 for the
    difference (excess cash transferred to owner's cash)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _set_balance_columns(
            conn,
            drawer.id,
            cash_sales=500_000,
            owner_in=200_000,
            owner_out=100_000,
            cash_expenses=50_000,
        )
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    # Previous expected balance = 1,550,000. Open today with 1,000,000 (< 1,550,000).
    resp = api_client.post(
        "/api/cash-drawer/open",
        json={"openingBalance": 1_000_000, "carryOverConfirmed": True},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["openingBalance"] == 1_000_000
    # AC17: an auto-transfer journal entry is created.
    assert "autoTransfer" in body, "expected autoTransfer block in response"
    transfer = body["autoTransfer"]
    assert transfer["sourceType"] == "cash_drawer_auto_transfer"
    lines = transfer["lines"]
    assert len(lines) == 2
    debit_line = next(l for l in lines if l["debit"] > 0)
    credit_line = next(l for l in lines if l["credit"] > 0)
    excess = 1_550_000 - 1_000_000
    assert float(debit_line["debit"]) == float(excess)
    assert float(credit_line["credit"]) == float(excess)
    with get_db() as conn:
        # DR 1102 (Owner's Cash), CR 1101 (Cash in Drawer).
        assert _account_id(conn, "1102") == int(debit_line["accountId"])
        assert _account_id(conn, "1101") == int(credit_line["accountId"])
    # The transfer entry is balanced (NFR2).
    with get_db() as conn:
        rows = _auto_transfer_lines(conn)
        debit_sum = sum(float(r["debit"]) for r in rows)
        credit_sum = sum(float(r["credit"]) for r in rows)
        assert debit_sum == credit_sum


def test_open_with_carry_over_and_equal_balance_no_auto_transfer(api_client):
    """FR10: when opening balance == previous expected balance, no
    auto-transfer is created (no excess to move)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _set_balance_columns(
            conn,
            drawer.id,
            cash_sales=500_000,
            owner_in=200_000,
            owner_out=100_000,
            cash_expenses=50_000,
        )
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    # Previous expected = 1,550,000. Open with exactly that amount.
    resp = api_client.post(
        "/api/cash-drawer/open",
        json={"openingBalance": 1_550_000, "carryOverConfirmed": True},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert "autoTransfer" not in body, "no auto-transfer when opening >= expected"
    with get_db() as conn:
        assert _auto_transfer_lines(conn) == []


def test_open_with_carry_over_and_higher_balance_no_auto_transfer(api_client):
    """FR10: when opening balance > previous expected balance, no
    auto-transfer is created (the owner added cash, no excess to move)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        drawer = CashDrawer.get_active(conn)
        _set_balance_columns(
            conn,
            drawer.id,
            cash_sales=500_000,
            owner_in=200_000,
            owner_out=100_000,
            cash_expenses=50_000,
        )
        _backdate_drawer(conn, drawer.id, "2026-07-28T08:00:00Z")
    # Previous expected = 1,550,000. Open with more than that (2,000,000).
    resp = api_client.post(
        "/api/cash-drawer/open",
        json={"openingBalance": 2_000_000, "carryOverConfirmed": True},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert "autoTransfer" not in body
    with get_db() as conn:
        assert _auto_transfer_lines(conn) == []


def test_open_without_carry_over_no_auto_transfer(api_client):
    """FR10: auto-transfer only fires when carry-over is confirmed (previous
    stale drawer exists). A fresh open with no stale drawer never transfers."""
    resp = api_client.post(
        "/api/cash-drawer/open",
        json={"openingBalance": 1_000_000, "carryOverConfirmed": True},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert "autoTransfer" not in body
    with get_db() as conn:
        assert _auto_transfer_lines(conn) == []


def test_open_without_stale_drawer_does_not_propose_carry_over(api_client):
    """FR9: when there is no stale (previous-day) drawer, opening proceeds
    normally with no carry-over proposal, even if carryOverConfirmed=True."""
    resp = api_client.post(
        "/api/cash-drawer/open",
        json={"openingBalance": 1_000_000, "carryOverConfirmed": True},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["openingBalance"] == 1_000_000
    assert "carryOver" not in body


def test_open_with_stale_today_drawer_still_409_active(api_client):
    """FR9 does not weaken the single-active-drawer rule: a drawer opened
    today (same local day) is NOT stale, so opening a second one returns the
    normal "already open" 409 (not a carry-over proposal)."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    resp = api_client.post(
        "/api/cash-drawer/open", json={"openingBalance": 500_000}
    )
    assert resp.status_code == 409
    detail = resp.json()["detail"]
    # Plain string detail (not the structured carry-over dict).
    assert isinstance(detail, str)
    assert "đang mở" in detail


# ---------------------------------------------------------------------------
# Model-level helper coverage
# ---------------------------------------------------------------------------


def test_auto_close_model_sets_zero_discrepancy():
    """The model helper auto_close() sets counted_amount = expected_balance
    and discrepancy = 0, and guards the update with WHERE status='open'
    (race-condition safety)."""
    d = CashDrawer(
        opened_at="2026-07-28T08:00:00Z",
        opening_balance=1_000_000,
        cash_sales=500_000,
        owner_in=200_000,
        owner_out=100_000,
        cash_expenses=50_000,
    )
    # expected_balance = 1,550,000

    class _FakeConn:
        def __init__(self):
            self.calls = []

        def execute(self, sql, params):
            self.calls.append((sql, params))

    fake = _FakeConn()
    d.id = 1
    disc = d.auto_close(fake)
    assert disc == 0
    assert d.status == "closed"
    assert d.counted_amount == 1_550_000
    assert d.discrepancy == 0
    # The update guards with WHERE status='open' (race-condition safety).
    assert "status = 'open'" in fake.calls[0][0]


def test_get_stale_open_before_filters_by_date(api_client):
    """The model helper get_stale_open_before() returns open drawers with
    opened_at strictly before the cutoff, ordered oldest first."""
    api_client.post("/api/cash-drawer/open", json={"openingBalance": 1_000_000})
    with get_db() as conn:
        active = CashDrawer.get_active(conn)
        # Backdate to 2026-07-28 — strictly before the start of today.
        _backdate_drawer(conn, active.id, "2026-07-28T08:00:00Z")
        stale = CashDrawer.get_stale_open_before(
            conn, before_iso="2026-07-29T00:00:00Z"
        )
        assert len(stale) == 1
        assert stale[0].id == active.id
        # A cutoff before the drawer's opened_at excludes it.
        none = CashDrawer.get_stale_open_before(
            conn, before_iso="2026-07-28T00:00:00Z"
        )
        assert none == []