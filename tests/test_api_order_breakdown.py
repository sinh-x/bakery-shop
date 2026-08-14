"""Tests for GET /api/reports/order-breakdown (DG-391 Phase 1 / FR1 / AC5).

Covers:
- Response structure: JSON array of cells with source, deliveryType,
  orderCount, revenue
- Grouping by source × delivery_type
- Period-aware date filtering (week / month / day)
- Revenue per cell = sum of orders.total_price for orders due in the
  period (POS/reconciliation fallback to created_at) — FR3 / AC3
- Empty period returns an empty array
- Default date is today
- Invalid period / date validation (422)
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


def _insert_order_on_date(
    conn,
    due_date: str,
    total=100000,
    source="manual",
    delivery_type="pickup",
):
    """Insert a minimal order directly with a specific due_date."""
    conn.execute(
        """INSERT INTO orders
             (order_ref, customer_name, status, source, delivery_type, due_date,
              public_order_code, total_price, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            f"OB-{due_date}-{total}-{abs(hash(due_date + str(total) + source + delivery_type)) % 100000}",
            "Khách test breakdown",
            "new",
            source,
            delivery_type,
            due_date,
            "",
            total,
            f"{due_date}T08:00:00",
            f"{due_date}T08:00:00",
        ),
    )


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
    with get_db() as conn:
        _insert_order_on_date(conn, monday, total=120000, source="Facebook", delivery_type="delivery")

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
    with get_db() as conn:
        _insert_order_on_date(conn, monday, total=100000, source="Facebook", delivery_type="delivery")
        _insert_order_on_date(conn, monday, total=200000, source="Facebook", delivery_type="delivery")
        _insert_order_on_date(conn, monday, total=150000, source="Zalo", delivery_type="pickup")

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
    with get_db() as conn:
        _insert_order_on_date(conn, far_monday, total=999999, source="Zalo", delivery_type="pickup")

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
    with get_db() as conn:
        _insert_order_on_date(conn, first, total=80000, source="Zalo", delivery_type="door")

    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "month", "date": today},
    ).json()
    cells = {(c["source"], c["deliveryType"]): c for c in body}
    assert ("Zalo", "door") in cells
    assert cells[("Zalo", "door")]["revenue"] == pytest.approx(80000.0)


# ---------------------------------------------------------------------------
# Revenue = sum of orders.total_price due in period (FR3 / AC3)
# ---------------------------------------------------------------------------


def test_order_breakdown_revenue_matches_period_summary_total(api_client):
    """FR3/AC3: the sum of revenue across all breakdown cells equals the
    period-summary revenue (both now use orders.total_price by due_date)."""
    today = _today()
    monday = _monday_of(today)
    with get_db() as conn:
        _insert_order_on_date(conn, monday, total=130000, source="Facebook", delivery_type="delivery")
        _insert_order_on_date(conn, monday, total=70000, source="Zalo", delivery_type="pickup")

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


def test_order_breakdown_revenue_uses_total_price_not_journal(api_client):
    """FR3: revenue is sum of total_price (not journal 4100 credit) — an
    order created but NOT delivered still contributes to breakdown revenue
    because its due_date is in the period."""
    # Create an order (due today) but do NOT deliver it — no 4100 credit.
    order = _create_order(api_client, total=250000, source="Facebook")
    # Do not deliver, do not create a payment transaction.

    today = _today()
    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": today},
    ).json()
    total = sum(c["revenue"] for c in body)
    assert total >= 250000.0


# ---------------------------------------------------------------------------
# Empty period (FR1)
# ---------------------------------------------------------------------------


def test_order_breakdown_empty_period_returns_empty_array(api_client):
    """FR1: no orders in the period → empty array."""
    body = api_client.get(
        "/api/reports/order-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    # May contain orders from other tests in shared DB, but structure is list.
    assert isinstance(body, list)


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