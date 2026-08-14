"""Tests for GET /api/reports/product-breakdown (DG-386 Phase 2).

Covers:
- Response structure validation (all required keys present, correct types)
- Top 10 products + Others row, sorted by revenue descending (F2 / AC3)
- Per-product quantity and revenue aggregation
- Percentage of total revenue per product (F2)
- Revenue reconciliation with period-summary revenue total (FR3 / Risk R-2)
- Period-aware date filtering (week / month)
- Gift items (is_gift=1) excluded from attribution
- Multiple products in one order prorated by line value
- Empty period returns empty products + zero-total Others
- Default date is today
- Invalid period / date validation (NF4 — Vietnamese error messages)
"""

import pytest

from baker.db.connection import get_db
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _today() -> str:
    return now_utc()[:10]


def _create_order(client, customer="Nguyễn Văn A", items=None, **kwargs):
    if items is None:
        items = [
            {"productName": "Bánh kem", "quantity": 1, "unitPrice": 300000, "productId": "8"}
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


def _deliver(client, ref):
    resp = client.post(f"/api/orders/{ref}/status", json={"status": "delivered"})
    assert resp.status_code == 200


def _mark_gift(conn, order_id: int, product_name: str):
    """Mark the first order_item matching product_name as a gift."""
    conn.execute(
        "UPDATE order_items SET is_gift = 1 WHERE order_id = ? AND product_name = ?",
        (order_id, product_name),
    )


# ---------------------------------------------------------------------------
# Response structure validation (F1, F3)
# ---------------------------------------------------------------------------


def test_product_breakdown_response_structure_week(api_client):
    """F1: GET /api/reports/product-breakdown?period=week returns all
    required keys with correct types."""
    resp = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    for key in ("period", "startDate", "endDate", "date", "totalRevenue", "products", "others"):
        assert key in body, f"Missing key: {key}"
    assert body["period"] == "week"
    assert body["date"] == _today()
    assert isinstance(body["totalRevenue"], (int, float))
    assert isinstance(body["products"], list)
    assert isinstance(body["others"], dict)
    # others row shape
    for key in ("name", "quantity", "revenue", "percentage"):
        assert key in body["others"]
    assert body["others"]["name"] == "Khác"


def test_product_breakdown_default_date_is_today(api_client):
    """When no date param is passed, the API defaults to today's date."""
    resp = api_client.get(
        "/api/reports/product-breakdown", params={"period": "week"}
    )
    assert resp.status_code == 200
    assert resp.json()["date"] == _today()


# ---------------------------------------------------------------------------
# Empty period (F1)
# ---------------------------------------------------------------------------


def test_product_breakdown_empty_period(api_client):
    """No orders and no journal entries → empty products list and zero
    Others row, totalRevenue 0."""
    resp = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["products"] == []
    assert body["others"]["quantity"] == 0
    assert body["others"]["revenue"] == 0
    assert body["others"]["percentage"] == 0
    assert body["totalRevenue"] == 0


# ---------------------------------------------------------------------------
# Single-product attribution (F1 — quantity, revenue, percentage)
# ---------------------------------------------------------------------------


def test_product_breakdown_single_product_full_revenue(api_client):
    """F1: one order, one product, fully paid → that product receives 100%
    of the order's recognized revenue, percentage == 100."""
    order = _create_order(
        api_client,
        items=[{"productName": "Bánh kem sinh nhật size S", "quantity": 1, "unitPrice": 200000, "productId": "8"}],
    )
    _create_txn(api_client, order["orderRef"], amount=200000, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    assert len(body["products"]) == 1
    p = body["products"][0]
    assert p["name"] == "Bánh kem sinh nhật size S"
    assert p["quantity"] == 1
    assert p["revenue"] == pytest.approx(200000.0)
    assert p["percentage"] == pytest.approx(100.0)
    # Others row is zero (only one product, within top 10)
    assert body["others"]["revenue"] == 0
    assert body["others"]["percentage"] == 0
    # Total reconciles
    assert body["totalRevenue"] == pytest.approx(200000.0)


def test_product_breakdown_quantity_aggregates_across_orders(api_client):
    """F1: two orders for the same product → quantity sums, revenue sums."""
    o1 = _create_order(
        api_client,
        items=[{"productName": "Bánh mì trắng", "quantity": 2, "unitPrice": 10000, "productId": "1"}],
        total=20000,
    )
    _create_txn(api_client, o1["orderRef"], amount=20000, type="payment", method="cash")
    _deliver(api_client, o1["orderRef"])

    o2 = _create_order(
        api_client,
        items=[{"productName": "Bánh mì trắng", "quantity": 3, "unitPrice": 10000, "productId": "1"}],
        total=30000,
    )
    _create_txn(api_client, o2["orderRef"], amount=30000, type="payment", method="cash")
    _deliver(api_client, o2["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    p = body["products"][0]
    assert p["name"] == "Bánh mì trắng"
    assert p["quantity"] == 5
    assert p["revenue"] == pytest.approx(50000.0)


# ---------------------------------------------------------------------------
# Multi-product order: revenue prorated by line value (F1)
# ---------------------------------------------------------------------------


def test_product_breakdown_prorates_revenue_by_line_value(api_client):
    """F1: one order with two products (line values 200k + 100k) paid
    300k → revenue prorated 2/3 and 1/3 respectively."""
    order = _create_order(
        api_client,
        items=[
            {"productName": "Bánh kem sinh nhật size S", "quantity": 1, "unitPrice": 200000, "productId": "8"},
            {"productName": "Bánh mì trắng", "quantity": 10, "unitPrice": 10000, "productId": "1"},
        ],
        total=300000,
    )
    _create_txn(api_client, order["orderRef"], amount=300000, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    by_name = {p["name"]: p for p in body["products"]}
    assert by_name["Bánh kem sinh nhật size S"]["revenue"] == pytest.approx(200000.0)
    assert by_name["Bánh mì trắng"]["revenue"] == pytest.approx(100000.0)


# ---------------------------------------------------------------------------
# Top 10 + Others, sorted by revenue descending (F2 / AC3)
# ---------------------------------------------------------------------------


def test_product_breakdown_top_10_plus_others_sorted_desc(api_client):
    """F2/AC3: with 12 distinct products, the API returns 10 in `products`
    and the remaining 2 aggregated into `others`. Both lists sorted by
    revenue descending."""
    # 12 products, descending revenue 120k → 10k. Product ids 1..12.
    items = [
        {"productName": f"PROD-{i}", "quantity": 1, "unitPrice": (13 - i) * 10000, "productId": str(i)}
        for i in range(1, 13)
    ]
    order = _create_order(api_client, items=items, total=sum((13 - i) * 10000 for i in range(1, 13)))
    total = sum((13 - i) * 10000 for i in range(1, 13))
    _create_txn(api_client, order["orderRef"], amount=total, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    assert len(body["products"]) == 10
    # products sorted descending by revenue
    revs = [p["revenue"] for p in body["products"]]
    assert revs == sorted(revs, reverse=True)
    # Others aggregates the 2 lowest-revenue products (PROD-11, PROD-12)
    assert body["others"]["name"] == "Khác"
    assert body["others"]["quantity"] == 2
    # 11 → 20k, 12 → 10k, total 30k
    assert body["others"]["revenue"] == pytest.approx(30000.0)
    # total reconciles: sum of products + others == totalRevenue
    prod_sum = sum(p["revenue"] for p in body["products"])
    assert prod_sum + body["others"]["revenue"] == pytest.approx(body["totalRevenue"])


def test_product_breakdown_fewer_than_10_products_no_others(api_client):
    """F2: with 3 distinct products, `products` has 3 entries and the
    Others row is present but zero (stable layout)."""
    order = _create_order(
        api_client,
        items=[
            {"productName": "Bánh mì trắng", "quantity": 1, "unitPrice": 10000, "productId": "1"},
            {"productName": "Bánh mì ngọt", "quantity": 1, "unitPrice": 12000, "productId": "2"},
            {"productName": "Bánh mì bơ tỏi", "quantity": 1, "unitPrice": 15000, "productId": "3"},
        ],
        total=37000,
    )
    _create_txn(api_client, order["orderRef"], amount=37000, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    assert len(body["products"]) == 3
    assert body["others"]["quantity"] == 0
    assert body["others"]["revenue"] == 0
    assert body["others"]["percentage"] == 0


def test_product_breakdown_percentages_sum_to_100(api_client):
    """F2: top 10 + Others percentages sum to ~100% of total revenue."""
    items = [
        {"productName": f"PROD-{i}", "quantity": 1, "unitPrice": (13 - i) * 10000, "productId": str(i)}
        for i in range(1, 13)
    ]
    order = _create_order(api_client, items=items, total=sum((13 - i) * 10000 for i in range(1, 13)))
    total = sum((13 - i) * 10000 for i in range(1, 13))
    _create_txn(api_client, order["orderRef"], amount=total, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    pct_sum = sum(p["percentage"] for p in body["products"]) + body["others"]["percentage"]
    assert pct_sum == pytest.approx(100.0, abs=0.05)


# ---------------------------------------------------------------------------
# Revenue reconciliation with period-summary (FR3 / Risk R-2)
# ---------------------------------------------------------------------------


def test_product_breakdown_total_matches_period_summary_revenue(api_client):
    """FR3 / Risk R-2: the product-breakdown totalRevenue reconciles with
    the period-summary `revenue` total for the same period."""
    o1 = _create_order(
        api_client,
        items=[{"productName": "Bánh kem sinh nhật size S", "quantity": 1, "unitPrice": 200000, "productId": "8"}],
        total=200000,
    )
    _create_txn(api_client, o1["orderRef"], amount=200000, type="payment", method="cash")
    _deliver(api_client, o1["orderRef"])

    o2 = _create_order(
        api_client,
        items=[{"productName": "Bánh mì trắng", "quantity": 5, "unitPrice": 10000, "productId": "1"}],
        total=50000,
    )
    _create_txn(api_client, o2["orderRef"], amount=50000, type="payment", method="transfer")
    _deliver(api_client, o2["orderRef"])

    period_body = api_client.get(
        "/api/reports/period-summary", params={"period": "week", "date": _today()}
    ).json()
    breakdown_body = api_client.get(
        "/api/reports/product-breakdown", params={"period": "week", "date": _today()}
    ).json()
    assert breakdown_body["totalRevenue"] == pytest.approx(period_body["revenue"], rel=1e-6)


# ---------------------------------------------------------------------------
# Gift items excluded (F1 — is_gift=1)
# ---------------------------------------------------------------------------


def test_product_breakdown_excludes_gift_items(api_client):
    """F1: gift items (is_gift=1) do not receive revenue attribution. An
    order with one paid product + one gift → only the paid product
    receives 100% of revenue."""
    order = _create_order(
        api_client,
        items=[
            {"productName": "Bánh kem sinh nhật size S", "quantity": 1, "unitPrice": 200000, "productId": "8"},
            {"productName": "Bánh mì trắng", "quantity": 2, "unitPrice": 10000, "productId": "1"},
        ],
        total=220000,
    )
    _create_txn(api_client, order["orderRef"], amount=220000, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    # Mark the Bánh mì trắng line as a gift post-delivery
    with get_db() as conn:
        _mark_gift(conn, order["id"], "Bánh mì trắng")

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    by_name = {p["name"]: p for p in body["products"]}
    # The paid product receives 100% of the order revenue (220000), since
    # the gift line is excluded from the line-value denominator.
    assert by_name["Bánh kem sinh nhật size S"]["revenue"] == pytest.approx(220000.0)
    # The gift product does not appear with attributed revenue.
    assert "Bánh mì trắng" not in by_name or by_name["Bánh mì trắng"]["revenue"] == 0


# ---------------------------------------------------------------------------
# Period-aware date filtering (F1)
# ---------------------------------------------------------------------------


def test_product_breakdown_period_aware_excludes_other_weeks(api_client):
    """F1: orders recognized (delivered) in a far-future week do not
    appear in the current week's breakdown."""
    # Create revenue in the current week
    order = _create_order(
        api_client,
        items=[{"productName": "Bánh kem sinh nhật size S", "quantity": 1, "unitPrice": 200000, "productId": "8"}],
        total=200000,
    )
    _create_txn(api_client, order["orderRef"], amount=200000, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    # Query a far-future week — no revenue recognized there
    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": "2099-06-15"},
    ).json()
    assert body["products"] == []
    assert body["totalRevenue"] == 0


def test_product_breakdown_month_period_aggregates_full_month(api_client):
    """F1: month period aggregates revenue across the full month."""
    order = _create_order(
        api_client,
        items=[{"productName": "Bánh kem sinh nhật size S", "quantity": 1, "unitPrice": 200000, "productId": "8"}],
        total=200000,
    )
    _create_txn(api_client, order["orderRef"], amount=200000, type="payment", method="cash")
    _deliver(api_client, order["orderRef"])

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "month", "date": _today()},
    ).json()
    assert body["period"] == "month"
    assert len(body["products"]) == 1
    assert body["products"][0]["revenue"] == pytest.approx(200000.0)


# ---------------------------------------------------------------------------
# Chunked batch query for periods with > 500 orders (Mn5)
# ---------------------------------------------------------------------------


def test_product_breakdown_chunked_query_handles_many_orders(api_client):
    """Mn5 (DG-386 cycle 5): the per-order line-item query is chunked into
    batches of 500 order ids to avoid exceeding SQLite's 32766 host
    variable limit. A period with more than 500 revenue-recognized orders
    must still aggregate correctly across all batches.
    """
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema, _account_id_by_code

    # Seed 600 delivered orders directly via SQL so we cross the 500-id
    # batch boundary without paying the cost of the full orders API flow
    # for each one. Each order gets a 4100 credit journal entry (source_type
    # 'order') so it shows up in the revenue query, and one order_items row
    # so the chunked item query has something to attribute.
    revenue_per_order = 10000.0
    n_orders = 600
    with get_db() as conn:
        ensure_schema(conn)
        revenue_acc_id = _account_id_by_code(conn, "4100")
        for oid in range(1, n_orders + 1):
            conn.execute(
                "INSERT INTO orders (id, order_ref, customer_name, due_date, total_price, status, items) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (oid, f"REF-{oid}", "Test", _today(), revenue_per_order, "delivered", "[]"),
            )
            conn.execute(
                "INSERT INTO order_items (order_id, product_name, product_id, quantity, unit_price, is_gift) "
                "VALUES (?, ?, ?, ?, ?, 0)",
                (oid, "Bánh mì trắng", 1, 1, revenue_per_order),
            )
            conn.execute(
                "INSERT INTO journal_entries (description, source_type, source_id, transaction_date) "
                "VALUES (?, 'order', ?, ?)",
                (f"Order {oid}", oid, f"{_today()}T10:00:00"),
            )
            je_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            conn.execute(
                "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
                "VALUES (?, ?, 0, ?, ?)",
                (je_id, revenue_acc_id, revenue_per_order, "revenue"),
            )

    body = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": _today()},
    ).json()
    # All 600 orders attributed to the single product.
    by_name = {p["name"]: p for p in body["products"]}
    assert "Bánh mì trắng" in by_name
    assert by_name["Bánh mì trắng"]["quantity"] == n_orders
    assert by_name["Bánh mì trắng"]["revenue"] == pytest.approx(
        n_orders * revenue_per_order
    )
    assert body["totalRevenue"] == pytest.approx(n_orders * revenue_per_order)


# ---------------------------------------------------------------------------
# Validation (F1, NF4 — Vietnamese error messages)
# ---------------------------------------------------------------------------


def test_product_breakdown_invalid_period_returns_422(api_client):
    """F1: an invalid period value is rejected by the pattern validator."""
    resp = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "year", "date": _today()},
    )
    assert resp.status_code == 422


def test_product_breakdown_invalid_date_format_returns_422(api_client):
    """NF4: a malformed date is rejected with a 422."""
    resp = api_client.get(
        "/api/reports/product-breakdown",
        params={"period": "week", "date": "2026/08/12"},
    )
    assert resp.status_code == 422


def test_product_breakdown_missing_period_returns_422(api_client):
    """F1: period is required — omitting it returns 422."""
    resp = api_client.get(
        "/api/reports/product-breakdown",
        params={"date": _today()},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Non-regression — period-summary still works alongside the new endpoint
# ---------------------------------------------------------------------------


def test_product_breakdown_does_not_break_period_summary(api_client):
    """Adding the product-breakdown endpoint does not affect period-summary."""
    _create_order(
        api_client,
        items=[{"productName": "Bánh mì trắng", "quantity": 1, "unitPrice": 10000, "productId": "1"}],
        total=10000,
    )
    body = api_client.get(
        "/api/reports/period-summary", params={"period": "week", "date": _today()}
    ).json()
    assert body["period"] == "week"
    assert body["orderCount"] >= 1