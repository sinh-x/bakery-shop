"""Tests for GET /api/reports/period-summary (DG-386 Phase 1).

Covers:
- Response structure validation (all required keys present, correct types)
- Week range computation (Monday-anchored, Sun end)
- Month range computation (1st–last day)
- Revenue aggregation over the period (journal 4100 credits)
- Cash/bank/cash-in/cash-out totals reuse the today-summary filters
- Order count aggregates all orders due within the period (all statuses)
- Period-aware: orders outside the period are excluded
- Invalid period / date validation
- Empty period (no data) returns zeros
- Default date is today
"""

from datetime import datetime, timedelta

import pytest

from baker.db.connection import get_db
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _today() -> str:
    return now_utc()[:10]


def _create_order(client, customer="Nguyễn Văn A", total=300000, items=None, **kwargs):
    if items is None:
        items = [
            {"productName": "Bánh kem", "quantity": 1, "unitPrice": total, "productId": "BKS-16"}
        ]
    payload = {"customerName": customer, "dueDate": _today(), "items": items, **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _open_drawer(client, opening_balance=1_000_000):
    resp = client.post(
        "/api/cash-drawer/open", json={"openingBalance": opening_balance}
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _insert_order_on_date(conn, due_date: str, total=100000):
    """Insert a minimal order directly with a specific due_date.

    Used to place orders on known dates inside a week/month range so the
    period aggregation can be tested deterministically without depending
    on ``today``.
    """
    conn.execute(
        """INSERT INTO orders
             (order_ref, customer_name, status, source, due_date,
              public_order_code, total_price, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            f"TEST-{due_date}-{total}-{abs(hash(due_date + str(total))) % 100000}",
            "Khách test kỳ",
            "new",
            "manual",
            due_date,
            "",
            total,
            f"{due_date}T08:00:00",
            f"{due_date}T08:00:00",
        ),
    )


# ---------------------------------------------------------------------------
# Date-range helpers — derive anchor dates from "today" so the tests
# remain deterministic regardless of when CI runs.
# ---------------------------------------------------------------------------


def _monday_of(date_str: str) -> str:
    d = datetime.strptime(date_str, "%Y-%m-%d")
    monday = d - timedelta(days=d.weekday())
    return monday.strftime("%Y-%m-%d")


def _sunday_of(date_str: str) -> str:
    monday = datetime.strptime(_monday_of(date_str), "%Y-%m-%d")
    return (monday + timedelta(days=6)).strftime("%Y-%m-%d")


def _first_of_month(date_str: str) -> str:
    d = datetime.strptime(date_str, "%Y-%m-%d")
    return d.replace(day=1).strftime("%Y-%m-%d")


def _last_of_month(date_str: str) -> str:
    import calendar
    d = datetime.strptime(date_str, "%Y-%m-%d")
    last = calendar.monthrange(d.year, d.month)[1]
    return d.replace(day=last).strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# Response structure validation (F1)
# ---------------------------------------------------------------------------


def test_period_summary_response_structure_week(api_client):
    """F1: GET /api/reports/period-summary?period=week returns all required
    keys with correct types."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    for key in (
        "period",
        "startDate",
        "endDate",
        "date",
        "revenue",
        "orderCount",
        "cashTotal",
        "bankTransferTotal",
        "cashInTotal",
        "cashOutTotal",
        "orders",
    ):
        assert key in body, f"Missing key: {key}"
    assert body["period"] == "week"
    assert body["date"] == _today()
    assert body["startDate"] == _monday_of(_today())
    assert body["endDate"] == _sunday_of(_today())
    assert isinstance(body["revenue"], (int, float))
    assert isinstance(body["orderCount"], int)
    assert isinstance(body["cashTotal"], (int, float))
    assert isinstance(body["bankTransferTotal"], (int, float))
    assert isinstance(body["cashInTotal"], (int, float))
    assert isinstance(body["cashOutTotal"], (int, float))
    assert isinstance(body["orders"], list)


def test_period_summary_response_structure_month(api_client):
    """F1: month period returns month-bounded startDate/endDate."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["period"] == "month"
    assert body["startDate"] == _first_of_month(_today())
    assert body["endDate"] == _last_of_month(_today())


def test_period_summary_default_date_is_today(api_client):
    """When no date param is passed, the API defaults to today's date."""
    resp = api_client.get("/api/reports/period-summary", params={"period": "week"})
    assert resp.status_code == 200
    assert resp.json()["date"] == _today()


# ---------------------------------------------------------------------------
# Week range computation (F2 — Monday-anchored)
# ---------------------------------------------------------------------------


def test_period_summary_week_monday_anchored_midweek(api_client):
    """F2: querying a Wednesday returns the Monday–Sunday of that week."""
    # 2026-08-12 is a Wednesday
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": "2026-08-12"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["startDate"] == "2026-08-10"  # Monday
    assert body["endDate"] == "2026-08-16"  # Sunday


def test_period_summary_week_monday_anchored_sunday(api_client):
    """F2: querying a Sunday returns the Monday of that same week (not the
    next Monday)."""
    # 2026-08-16 is a Sunday
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": "2026-08-16"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["startDate"] == "2026-08-10"
    assert body["endDate"] == "2026-08-16"


def test_period_summary_week_monday_anchored_monday(api_client):
    """F2: querying a Monday returns that same Monday as startDate."""
    # 2026-08-10 is a Monday
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": "2026-08-10"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["startDate"] == "2026-08-10"
    assert body["endDate"] == "2026-08-16"


# ---------------------------------------------------------------------------
# Month range computation (F2)
# ---------------------------------------------------------------------------


def test_period_summary_month_range_mid_month(api_client):
    """F2: querying mid-month returns 1st–last day of that month."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": "2026-02-15"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["startDate"] == "2026-02-01"
    assert body["endDate"] == "2026-02-28"  # 2026 is not a leap year


def test_period_summary_month_range_leap_year(api_client):
    """F2: February of a leap year returns 29 days."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": "2024-02-15"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["startDate"] == "2024-02-01"
    assert body["endDate"] == "2024-02-29"


def test_period_summary_month_range_31_day_month(api_client):
    """F2: a 31-day month (e.g. January) returns the 31st as endDate."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": "2026-01-15"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["startDate"] == "2026-01-01"
    assert body["endDate"] == "2026-01-31"


# ---------------------------------------------------------------------------
# Empty period (F1)
# ---------------------------------------------------------------------------


def test_period_summary_empty_period(api_client):
    """No orders and no journal entries → all metrics zero."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["revenue"] == 0
    assert body["orderCount"] == 0
    assert body["cashTotal"] == 0
    assert body["bankTransferTotal"] == 0
    assert body["cashInTotal"] == 0
    assert body["cashOutTotal"] == 0
    assert body["orders"] == []


# ---------------------------------------------------------------------------
# Order aggregation (F1 — orderCount, orders list)
# ---------------------------------------------------------------------------


def test_period_summary_includes_orders_due_in_period(api_client):
    """F1: orders with due_date within the period are included in the
    orders list and counted in orderCount."""
    today = _today()
    monday = _monday_of(today)
    with get_db() as conn:
        _insert_order_on_date(conn, monday, total=120000)
        _insert_order_on_date(conn, _sunday_of(today), total=80000)

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": today},
    ).json()
    refs = {o["orderRef"] for o in body["orders"]}
    # Both inserted orders fall within this week's Monday–Sunday bounds.
    assert any(r.startswith(f"TEST-{monday}-") for r in refs)
    assert any(r.startswith(f"TEST-{_sunday_of(today)}-") for r in refs)
    assert body["orderCount"] >= 2


def test_period_summary_excludes_orders_outside_period(api_client):
    """F1: orders with due_date outside the period are NOT included."""
    today = _today()
    # Use a fixed far-future anchor whose week clearly does not contain today.
    anchor = "2099-06-15"  # Monday of that week = 2099-06-14 (Mon)
    monday = _monday_of(anchor)
    sunday = _sunday_of(anchor)
    with get_db() as conn:
        _insert_order_on_date(conn, monday, total=100000)
        _insert_order_on_date(conn, sunday, total=100000)

    # Query this week — the 2099 orders must not appear.
    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": today},
    ).json()
    refs = {o["orderRef"] for o in body["orders"]}
    assert not any("2099-06" in r for r in refs), (
        "orders outside the queried week must not appear in period-summary"
    )


def test_period_summary_month_includes_orders_across_month(api_client):
    """F1: month period includes orders due on the 1st and last day."""
    today = _today()
    first = _first_of_month(today)
    last = _last_of_month(today)
    with get_db() as conn:
        _insert_order_on_date(conn, first, total=50000)
        _insert_order_on_date(conn, last, total=70000)

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": today},
    ).json()
    refs = {o["orderRef"] for o in body["orders"]}
    assert any(r.startswith(f"TEST-{first}-") for r in refs)
    assert any(r.startswith(f"TEST-{last}-") for r in refs)
    assert body["orderCount"] >= 2


def test_period_summary_month_excludes_orders_in_other_month(api_client):
    """F1: month period excludes orders due in a different month."""
    # Query February 2099 — orders in January 2099 must not appear.
    with get_db() as conn:
        _insert_order_on_date(conn, "2099-01-15", total=100000)

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": "2099-02-15"},
    ).json()
    refs = {o["orderRef"] for o in body["orders"]}
    assert not any("2099-01" in r for r in refs)


# ---------------------------------------------------------------------------
# Revenue aggregation (F1 — revenue from journal 4100 over period)
# ---------------------------------------------------------------------------


def test_period_summary_revenue_aggregates_journal_4100_over_week(api_client):
    """F1: revenue = sum of journal 4100 credits over the full week."""
    order = _create_order(api_client, total=300000)
    _create_txn(api_client, order["orderRef"], amount=300000, type="payment", method="cash")
    resp = api_client.post(f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"})
    assert resp.status_code == 200

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert body["revenue"] == pytest.approx(300000.0)


def test_period_summary_revenue_aggregates_multiple_orders_over_month(api_client):
    """F1: revenue sums multiple delivered orders within the month."""
    o1 = _create_order(api_client, total=100000)
    _create_txn(api_client, o1["orderRef"], amount=100000, type="payment", method="cash")
    api_client.post(f"/api/orders/{o1['orderRef']}/status", json={"status": "delivered"})

    o2 = _create_order(api_client, total=250000)
    _create_txn(api_client, o2["orderRef"], amount=250000, type="payment", method="transfer")
    api_client.post(f"/api/orders/{o2['orderRef']}/status", json={"status": "delivered"})

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": _today()},
    ).json()
    assert body["revenue"] == pytest.approx(350000.0)


# ---------------------------------------------------------------------------
# Cash / bank / cash-in / cash-out totals reuse today-summary filters (F1)
# ---------------------------------------------------------------------------


def test_period_summary_cash_and_bank_totals_aggregate_over_week(api_client):
    """F1: cashTotal and bankTransferTotal sum payment_transaction debits
    over the full week."""
    o1 = _create_order(api_client, total=100000)
    _create_txn(api_client, o1["orderRef"], amount=100000, type="payment", method="cash")

    o2 = _create_order(api_client, total=200000)
    _create_txn(api_client, o2["orderRef"], amount=200000, type="payment", method="transfer")

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert body["cashTotal"] == pytest.approx(100000.0)
    assert body["bankTransferTotal"] == pytest.approx(200000.0)


def test_period_summary_cash_in_out_aggregate_over_period(api_client):
    """F1: cashInTotal/cashOutTotal sum cash_drawer_cash_in/out over period."""
    _open_drawer(api_client, opening_balance=1_000_000)
    api_client.post("/api/cash-drawer/cash-in", json={"amount": 200_000})
    api_client.post("/api/cash-drawer/cash-out", json={"amount": 50_000})

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert body["cashInTotal"] == pytest.approx(200000.0)
    assert body["cashOutTotal"] == pytest.approx(50000.0)


def test_period_summary_cash_total_excludes_non_payment_entries(api_client):
    """F1: non-payment journal entries (e.g. owner_capital) debiting 1101
    must NOT be counted in cashTotal over the period."""
    resp = api_client.post(
        "/api/accounts/owner-capital",
        json={"amount": 5000000, "method": "cash"},
    )
    assert resp.status_code == 201

    order = _create_order(api_client, total=100000)
    _create_txn(api_client, order["orderRef"], amount=100000, type="deposit", method="cash")

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert body["cashTotal"] == pytest.approx(100000.0)


# ---------------------------------------------------------------------------
# Validation (F1, NF4 — Vietnamese error messages)
# ---------------------------------------------------------------------------


def test_period_summary_invalid_period_returns_422(api_client):
    """F1: an invalid period value is rejected by the pattern validator."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "year", "date": _today()},
    )
    assert resp.status_code == 422


def test_period_summary_invalid_date_format_returns_422(api_client):
    """NF4: a malformed date is rejected with a 422."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": "2026/08/12"},
    )
    assert resp.status_code == 422


def test_period_summary_missing_period_returns_422(api_client):
    """F1: period is required — omitting it returns 422."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"date": _today()},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Non-regression — today-summary still works (F1)
# ---------------------------------------------------------------------------


def test_period_summary_does_not_break_today_summary(api_client):
    """Adding the period-summary endpoint does not affect today-summary."""
    _create_order(api_client, total=100000)
    today = _today()
    body = api_client.get(
        "/api/reports/today-summary", params={"date": today}
    ).json()
    assert body["date"] == today
    assert body["orderCount"] >= 1


# ---------------------------------------------------------------------------
# Consistency — period-summary week containing today matches today-summary
# for the today slice (sanity check that filters align)
# ---------------------------------------------------------------------------


def test_period_summary_week_includes_today_summary_orders(api_client):
    """The week containing today must include at least every order that
    today-summary reports for today (subset relationship)."""
    _create_order(api_client, total=150000)
    today_body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    week_body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    today_refs = {o["orderRef"] for o in today_body["orders"]}
    week_refs = {o["orderRef"] for o in week_body["orders"]}
    assert today_refs.issubset(week_refs), (
        f"today-summary orders {today_refs} not all in week period {week_refs}"
    )


def test_period_summary_month_includes_today_summary_orders(api_client):
    """The month containing today must include every order that
    today-summary reports for today."""
    _create_order(api_client, total=150000)
    today_body = api_client.get(
        "/api/reports/today-summary", params={"date": _today()}
    ).json()
    month_body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "month", "date": _today()},
    ).json()
    today_refs = {o["orderRef"] for o in today_body["orders"]}
    month_refs = {o["orderRef"] for o in month_body["orders"]}
    assert today_refs.issubset(month_refs)


# ---------------------------------------------------------------------------
# accountsReceivable field (DG-391 Phase 1 / FR4 / AC4)
# ---------------------------------------------------------------------------


def test_period_summary_includes_accounts_receivable_field(api_client):
    """FR4/AC4: period-summary response includes the accountsReceivable
    field (revenue − (cashTotal + bankTransferTotal))."""
    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert "accountsReceivable" in body
    assert isinstance(body["accountsReceivable"], (int, float))


def test_period_summary_accounts_receivable_equals_revenue_minus_payments(api_client):
    """FR4/AC4: accountsReceivable = revenue − (cashTotal + bankTransferTotal).

    An order delivered with a cash payment: revenue = total_price,
    cashTotal = paid amount, bankTransferTotal = 0. AR = revenue − cash.
    """
    order = _create_order(api_client, total=200000)
    _create_txn(api_client, order["orderRef"], amount=200000, type="payment", method="cash")
    api_client.post(f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"})

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    expected_ar = body["revenue"] - (body["cashTotal"] + body["bankTransferTotal"])
    assert body["accountsReceivable"] == pytest.approx(expected_ar)


def test_period_summary_accounts_receivable_zero_when_fully_paid(api_client):
    """FR4/AC4: AR ≈ 0 when revenue equals cash + bank (fully paid in period)."""
    order = _create_order(api_client, total=150000)
    _create_txn(api_client, order["orderRef"], amount=150000, type="payment", method="cash")
    api_client.post(f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"})

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    assert body["accountsReceivable"] == pytest.approx(0.0, abs=0.01)


def test_period_summary_accounts_receivable_positive_when_unpaid_order_due(api_client):
    """FR4: AR > 0 when an order is due in the period and delivered but
    not yet paid (revenue = journal 4100 credit via AR entry,
    cashTotal/bankTotal = 0)."""
    today = _today()
    monday = _monday_of(today)
    # Create an order due on Monday and deliver it WITHOUT a payment —
    # the journal sync creates the AR revenue entry (DR 1500 / CR 4100
    # for total_price), so revenue = total_price but cashTotal = 0.
    payload = {
        "customerName": "Khách chưa trả tiền",
        "dueDate": monday,
        "source": "manual",
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 500000, "productId": "BKS-16"}],
    }
    resp = api_client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text
    ref = resp.json()["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": today},
    ).json()
    # The unpaid order contributes revenue but no cash/bank, so AR > 0.
    # Other tests may add paid orders, but the unpaid one pushes AR up.
    assert body["accountsReceivable"] > 0


def test_period_summary_accounts_receivable_can_be_negative(api_client):
    """FR4: AR can be negative when prepayment > revenue for the period
    (customer paid in advance, order due in a future period)."""
    # Create an order due today and deliver it with a cash payment so
    # revenue = 100000 and cashTotal includes 100000.
    order = _create_order(api_client, total=100000)
    _create_txn(api_client, order["orderRef"], amount=100000, type="payment", method="cash")
    api_client.post(f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"})

    # Create a second order due in a FUTURE week and pay a deposit (cash)
    # into it today. The deposit cash is collected this week (cashTotal),
    # but the order's revenue (total_price) is bucketed to the future week
    # (due_date outside this week), so this week's AR = revenue − cash < 0.
    future_monday = _monday_of("2099-12-15")
    future_order_payload = {
        "customerName": "Khách trả trước",
        "dueDate": future_monday,
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 300000, "productId": "BKS-16"}],
        "source": "manual",
    }
    future_order = api_client.post("/api/orders", json=future_order_payload).json()
    _create_txn(
        api_client,
        future_order["orderRef"],
        amount=300000,
        type="deposit",
        method="cash",
    )

    body = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": _today()},
    ).json()
    # This week: revenue = 100000 (delivered order due today). cashTotal =
    # 100000 (delivered payment) + 300000 (future-order deposit) = 400000.
    # AR = 100000 − 400000 = -300000. Other tests may add more, but the
    # prepayment pushes AR below zero.
    assert body["accountsReceivable"] < 0