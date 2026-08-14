"""Tests for GET /api/reports/order-breakdown (DG-391 Phase 1 / FR1 / AC5).

Covers:
- Response structure: JSON array of cells with source, deliveryType,
  orderCount, revenue
- Grouping by source × delivery_type
- Period-aware date filtering (week / month / day)
- Revenue per cell = sum of journal_lines.credit for account 4100
  (Doanh thu bán hàng), bucketed by due_date for order-sourced entries
  — FR3 / AC3. Revenue is recognised when the order is delivered (the
  journal sync creates the 4100 credit at delivery time), preserving the
  DG-376 partial-payment invariant.
- Default date is today
- Invalid period / date validation (422)
"""

from datetime import datetime, timedelta

import pytest

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


def _deliver_order(client, ref):
    """Mark an order delivered — triggers the journal sync that creates the
    4100 revenue credit (deposit→revenue or AR→revenue entry)."""
    resp = client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200


def _insert_delivered_order_on_date(
    client,
    due_date: str,
    total=100000,
    source="manual",
    delivery_type="pickup",
):
    """Create an order via the API with the given due_date/source/
    delivery_type, pay the full amount, then deliver it. Delivering a
    paid order creates the revenue entry (DR 2100 / CR 4100 for the
    deposit balance = total) so its 4100 credit is bucketed by
    due_date. Returns the orderRef."""
    payload = {
        "customerName": "Khách test breakdown",
        "dueDate": due_date,
        "source": source,
        "deliveryType": delivery_type,
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": total, "productId": "BKS-16"}],
    }
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text
    ref = resp.json()["orderRef"]
    # Pay the full amount so the revenue entry debits 2100 (deposits) and
    # credits 4100 for the deposit balance — exactly total. This keeps the
    # recognised revenue equal to total for deterministic assertions while
    # still exercising the journal-based revenue path.
    _create_txn(client, ref, amount=total, type="payment", method="cash")
    _deliver_order(client, ref)
    return ref


def _monday_of(date_str: str) -> str:
    d = datetime.strptime(date_str, "%Y-%m-%d")
    monday = d - timedelta(days=d.weekday())
    return monday.strftime("%Y-%m-%d")


def _sunday_of(date_str: str) -> str:
    monday = datetime.strptime(_monday_of(date_str), "%Y-%m-%d")
    return (monday + timedelta(days=6)).strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# Response structure (FR1 / AC5)
# ---------------------------------------------------------------------------


def test_order_breakdown_returns_json_array(api_client):
    """AC5: the endpoint returns a JSON array (not an object)."""
    resp = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body, list)


def test_order_breakdown_cell_shape(api_client):
    """AC5: each cell has source, deliveryType, orderCount, revenue."""
    today = _today()
    monday = _monday_of(today)
    _insert_delivered_order_on_date(
        api_client, monday, total=120000, source="Facebook", delivery_type="delivery",
    )

    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": today},
    ).json()
    assert len(body) >= 1
    cell = body[0]
    for key in ("source", "deliveryType", "orderCount", "revenue"):
        assert key in cell, f"Missing key: {key}"
    assert isinstance(cell["orderCount"], int)
    assert isinstance(cell["revenue"], (int, float))


# ---------------------------------------------------------------------------
# Grouping by source × delivery_type (FR1)
# ---------------------------------------------------------------------------


def test_order_breakdown_groups_by_source_and_delivery_type(api_client):
    """FR1: orders with the same source × delivery_type are aggregated into
    one cell with summed orderCount and revenue."""
    today = _today()
    monday = _monday_of(today)
    _insert_delivered_order_on_date(
        api_client, monday, total=100000, source="Facebook", delivery_type="delivery",
    )
    _insert_delivered_order_on_date(
        api_client, monday, total=200000, source="Facebook", delivery_type="delivery",
    )
    _insert_delivered_order_on_date(
        api_client, monday, total=150000, source="Zalo", delivery_type="pickup",
    )

    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": today},
    ).json()
    cells = {(c["source"], c["deliveryType"]): c for c in body}
    assert ("Facebook", "delivery") in cells
    assert cells[("Facebook", "delivery")]["orderCount"] == 2
    assert cells[("Facebook", "delivery")]["revenue"] == pytest.approx(300000.0)
    assert ("Zalo", "pickup") in cells
    assert cells[("Zalo", "pickup")]["orderCount"] == 1
    assert cells[("Zalo", "pickup")]["revenue"] == pytest.approx(150000.0)


# ---------------------------------------------------------------------------
# Period-aware date filtering (FR1)
# ---------------------------------------------------------------------------


def test_order_breakdown_excludes_orders_outside_period(api_client):
    """FR1: orders with due_date outside the queried period are excluded."""
    today = _today()
    # Insert an order in a far-future week.
    far_monday = _monday_of("2099-06-15")
    _insert_delivered_order_on_date(
        api_client, far_monday, total=999999, source="Zalo", delivery_type="pickup",
    )

    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": today},
    ).json()
    for cell in body:
        assert cell["revenue"] != pytest.approx(999999.0)


def test_order_breakdown_month_includes_orders_across_month(api_client):
    """FR1: month period includes orders due on any day of the month."""
    today = _today()
    d = datetime.strptime(today, "%Y-%m-%d")
    first = d.replace(day=1).strftime("%Y-%m-%d")
    _insert_delivered_order_on_date(
        api_client, first, total=80000, source="Zalo", delivery_type="door",
    )

    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "month", "date": today},
    ).json()
    cells = {(c["source"], c["deliveryType"]): c for c in body}
    assert ("Zalo", "door") in cells
    assert cells[("Zalo", "door")]["revenue"] == pytest.approx(80000.0)


# ---------------------------------------------------------------------------
# Revenue = sum of journal 4100 credit for delivered orders (FR3 / AC3)
# ---------------------------------------------------------------------------


def test_order_breakdown_revenue_matches_period_summary_total(api_client):
    """FR3/AC3: the sum of revenue across all breakdown cells equals the
    period-summary revenue (both use journal 4100 credit bucketed by
    due_date)."""
    today = _today()
    monday = _monday_of(today)
    _insert_delivered_order_on_date(
        api_client, monday, total=130000, source="Facebook", delivery_type="delivery",
    )
    _insert_delivered_order_on_date(
        api_client, monday, total=70000, source="Zalo", delivery_type="pickup",
    )

    breakdown = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": today},
    ).json()
    period = api_client.get(
        "/api/reports/period-summary",
        params={"period": "week", "date": today},
    ).json()

    breakdown_total = sum(c["revenue"] for c in breakdown)
    assert breakdown_total == pytest.approx(period["revenue"], rel=0.01)


def test_order_breakdown_revenue_only_recognised_on_delivery(api_client):
    """FR3 / DG-376 invariant: revenue is the journal 4100 credit created
    at delivery — an order created but NOT delivered contributes NO
    breakdown revenue (no 4100 credit exists yet)."""
    # Create an order (due today) but do NOT deliver it — no 4100 credit.
    order = _create_order(api_client, total=250000, source="Facebook")
    # Do not deliver, do not create a payment transaction.

    today = _today()
    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": today},
    ).json()
    total = sum(c["revenue"] for c in body)
    # The undelivered order's total_price must NOT appear in revenue.
    for cell in body:
        assert cell["revenue"] < 250000.0 or cell["source"] != "Facebook"


# ---------------------------------------------------------------------------
# Default date is today
# ---------------------------------------------------------------------------


def test_order_breakdown_default_date_is_today(api_client):
    """When no date param is passed, the API defaults to today and returns
    200 (no 422)."""
    resp = api_client.get("/api/reports/order-breakdown", params={"period": "week"})
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# Validation (NF4)
# ---------------------------------------------------------------------------


def test_order_breakdown_invalid_period_returns_422(api_client):
    resp = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "year", "date": _today()},
    )
    assert resp.status_code == 422


def test_order_breakdown_invalid_date_format_returns_422(api_client):
    resp = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": "2026/08/12"},
    )
    assert resp.status_code == 422


def test_order_breakdown_missing_period_returns_422(api_client):
    resp = api_client.get(
        "/api/reports/order-breakdown",
        params={"date": _today()},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# day period accepted
# ---------------------------------------------------------------------------


def test_order_breakdown_day_period_returns_200(api_client):
    """period=day is accepted by the order-breakdown endpoint."""
    resp = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "day", "date": "2026-08-12"},
    )
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)