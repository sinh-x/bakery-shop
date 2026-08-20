"""Tests for the ``day`` period across the DG-386 report endpoints
(DG-386 Phase 11 / FR1-FR5 / AC3-AC5).

The backend period endpoints (period-summary, product-breakdown,
expense-summary, cashflow-summary) originally accepted only ``week`` and
``month``. Phase 11 adds ``day`` so the Ngày tab can reuse the same
parallel-fetched report data as the Tuần/Tháng tabs (F1 — every tab shows
revenue + product breakdown + expenses + cashflow + orders).

These tests verify:
- ``period=day`` is accepted by all four endpoints (200, not 422).
- ``startDate == endDate == <date>`` for a day query.
- Day-period results reconcile with the existing today-summary endpoint
  for the same date (revenue, cashTotal, bankTransferTotal, orderCount).
- Day-period product-breakdown returns the same products as the day's
  delivered orders.
- Day-period expense-summary returns zeros when there are no expenses.
- Day-period cashflow-summary returns zeros when there is no operating
  activity.
"""

import pytest

from baker.db.connection import get_db
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers (mirror test_api_period_summary.py)
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


# ---------------------------------------------------------------------------
# period=day is accepted (FR1-FR5 / AC3-AC5)
# ---------------------------------------------------------------------------


def test_period_summary_day_returns_200_with_single_day_bounds(api_client):
    """period=day is accepted and startDate == endDate == date."""
    resp = api_client.get(
        "/api/reports/period-summary",
        params={"period": "day", "date": "2026-08-12"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["period"] == "day"
    assert body["startDate"] == "2026-08-12"
    assert body["endDate"] == "2026-08-12"


def test_product_breakdown_day_returns_200(api_client):
    """period=day is accepted by the product-breakdown endpoint."""
    resp = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "day", "date": "2026-08-12"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["period"] == "day"
    assert body["startDate"] == "2026-08-12"
    assert body["endDate"] == "2026-08-12"


def test_expense_summary_day_returns_200(api_client):
    """period=day is accepted by the expense-summary endpoint."""
    resp = api_client.get(
        "/api/reports/expense-summary",
        params={"period": "day", "date": "2026-08-12"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["period"] == "day"
    assert body["startDate"] == "2026-08-12"
    assert body["endDate"] == "2026-08-12"


def test_cashflow_summary_day_returns_200(api_client):
    """period=day is accepted by the cashflow-summary endpoint."""
    resp = api_client.get(
        "/api/reports/cashflow-summary",
        params={"period": "day", "date": "2026-08-12"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["period"] == "day"
    assert body["startDate"] == "2026-08-12"
    assert body["endDate"] == "2026-08-12"


# ---------------------------------------------------------------------------
# Day-period reconciles with today-summary (F1)
# ---------------------------------------------------------------------------


def test_day_period_summary_matches_today_summary_for_same_date(api_client):
    """period=day for today returns the same revenue/cash/bank/orderCount
    as the today-summary endpoint for the same date."""
    order = _create_order(api_client, total=250000)
    _create_txn(api_client, order["orderRef"], amount=250000, type="payment", method="cash")
    api_client.post(
        f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"}
    )

    today = _today()
    today_body = api_client.get(
        "/api/reports/today-summary", params={"date": today}
    ).json()
    day_body = api_client.get(
        "/api/reports/period-summary", params={"period": "day", "date": today}
    ).json()

    assert day_body["revenue"] == pytest.approx(today_body["revenue"])
    assert day_body["cashTotal"] == pytest.approx(today_body["cashTotal"])
    assert day_body["bankTransferTotal"] == pytest.approx(
        today_body["bankTransferTotal"]
    )
    assert day_body["orderCount"] == today_body["orderCount"]


# ---------------------------------------------------------------------------
# Day-period product breakdown (AC3)
# ---------------------------------------------------------------------------


def test_day_product_breakdown_returns_top_product_for_delivered_order(api_client):
    """period=day product-breakdown includes the product from a delivered
    order placed today."""
    order = _create_order(
        api_client,
        total=200000,
        items=[
            {"productName": "Bánh kem sô cô la", "quantity": 1, "unitPrice": 200000,
             "productId": "BKS-16"},
        ],
    )
    _create_txn(api_client, order["orderRef"], amount=200000, type="payment", method="cash")
    api_client.post(
        f"/api/orders/{order['orderRef']}/status", json={"status": "delivered"}
    )

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "day", "date": _today()},
    ).json()
    names = [p["name"] for p in body["products"]]
    assert "Bánh kem sô cô la" in names
    assert body["totalRevenue"] == pytest.approx(200000.0)


# ---------------------------------------------------------------------------
# Day-period empty states (AC4, AC5)
# ---------------------------------------------------------------------------


def test_day_expense_summary_empty_when_no_expenses(api_client):
    """period=day expense-summary returns zeros when there are no expenses."""
    body = api_client.get(
        "/api/reports/expense-summary",
        params={"period": "day", "date": _today()},
    ).json()
    assert body["totalExpenses"] == 0
    assert body["categories"] == []
    assert body["uncategorized"] == 0


def test_day_cashflow_summary_empty_when_no_activity(api_client):
    """period=day cashflow-summary returns zeros when there is no operating
    activity."""
    body = api_client.get(
        "/api/reports/cashflow-summary",
        params={"period": "day", "date": _today()},
    ).json()
    assert body["operatingInflow"] == 0
    assert body["operatingOutflow"] == 0
    assert body["netOperatingCashFlow"] == 0


# ---------------------------------------------------------------------------
# Day-period orders list matches today-summary orders (F1)
# ---------------------------------------------------------------------------


def test_day_period_orders_match_today_summary_orders(api_client):
    """period=day for today returns the same orderCount as the today-summary
    endpoint for the same date (DG-409 Phase 1: the orders list is no longer
    embedded in either response — verify via orderCount + statusBreakdown
    instead of comparing orderRef sets)."""
    _create_order(api_client, total=120000)
    today = _today()
    today_body = api_client.get(
        "/api/reports/today-summary", params={"date": today}
    ).json()
    day_body = api_client.get(
        "/api/reports/period-summary", params={"period": "day", "date": today}
    ).json()
    # Both endpoints aggregate over the same day, so orderCount and the
    # statusBreakdown 'new' bucket must match exactly.
    assert day_body["orderCount"] == today_body["orderCount"], (
        f"day-period orderCount {day_body['orderCount']} != "
        f"today-summary orderCount {today_body['orderCount']}"
    )
    assert (
        day_body["statusBreakdown"].get("new", 0)
        == today_body["statusBreakdown"].get("new", 0)
    )