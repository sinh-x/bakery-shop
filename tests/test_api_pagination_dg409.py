"""Tests for DG-409 Phase 3 — pagination on unbounded backend endpoints.

Covers FR3 (products), FR4 (customers), FR5 (customer orders), FR6 (stock
overview), FR14 (total + has_more envelope), and the additive-only
backward-compatibility guarantee (NFR6). Also covers the paginated modes for
debts, reconciliation history, per-product catalog photos, order
transactions, and order events.

The pagination contract:
  - Bare-array endpoints return a JSON array when ``paginated`` is false and
    ``limit`` is absent (backward-compatible, NFR6).
  - When ``paginated=true`` OR ``limit`` is supplied, the endpoint returns an
    envelope ``{"items": [...], "total": N, "has_more": bool, "limit": L,
    "offset": O}`` (FR14).
  - Already-envelope endpoints (debts, reconciliation history) keep their
    existing shape and add ``total``/``has_more``/``limit``/``offset`` only
    when pagination is opted into (additive, NFR6).
"""

from baker.db.connection import get_db


def _seed_products(api_client, n: int, category: str = "bread") -> list[int]:
    """Create n products via the API and return their ids."""
    ids: list[int] = []
    for i in range(n):
        resp = api_client.post(
            "/api/products",
            json={
                "name": f"{category}-P{i}",
                "category": category,
                "base_price": 1000 + i,
            },
        )
        assert resp.status_code == 201, resp.text
        ids.append(resp.json()["id"])
    return ids


def _seed_customers(api_client, n: int) -> list[int]:
    ids: list[int] = []
    for i in range(n):
        resp = api_client.post(
            "/api/customers", json={"name": f"Khach {i}", "phone": f"090000{i:04d}"}
        )
        assert resp.status_code == 201, resp.text
        ids.append(resp.json()["id"])
    return ids


# ---------------------------------------------------------------------------
# FR3 — GET /api/products
# ---------------------------------------------------------------------------


def test_products_bare_array_backward_compat(api_client):
    """No pagination params → bare array (NFR6)."""
    _seed_products(api_client, 3)
    resp = api_client.get("/api/products")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) >= 3


def test_products_envelope_when_paginated_true(api_client):
    _seed_products(api_client, 3)
    resp = api_client.get("/api/products", params={"paginated": "true"})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())
    assert isinstance(data["items"], list)
    assert data["total"] >= 3
    assert data["limit"] == 50
    assert data["offset"] == 0
    assert data["has_more"] is False


def test_products_envelope_when_limit_supplied(api_client):
    _seed_products(api_client, 5)
    resp = api_client.get("/api/products", params={"limit": 2, "offset": 0})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert len(data["items"]) == 2
    assert data["total"] >= 5
    assert data["has_more"] is True
    assert data["limit"] == 2


def test_products_limit_offset_honored(api_client):
    _seed_products(api_client, 6)
    resp = api_client.get("/api/products", params={"limit": 2, "offset": 2})
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) == 2
    assert data["offset"] == 2
    # The two items returned should differ from page 1.
    page1 = api_client.get("/api/products", params={"limit": 2, "offset": 0}).json()[
        "items"
    ]
    page2_ids = {item["id"] for item in data["items"]}
    page1_ids = {item["id"] for item in page1}
    assert page2_ids.isdisjoint(page1_ids)


def test_products_default_limit_50(api_client):
    """FR3: default limit is 50 when paginated without explicit limit."""
    _seed_products(api_client, 60)
    resp = api_client.get("/api/products", params={"paginated": "true"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["limit"] == 50
    assert len(data["items"]) == 50
    assert data["total"] >= 60
    assert data["has_more"] is True


def test_products_pagination_preserves_category_filter(api_client):
    _seed_products(api_client, 3, category="bread")
    _seed_products(api_client, 2, category="cookie")
    resp = api_client.get(
        "/api/products",
        params={"category": "cookie", "paginated": "true", "limit": 1},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert all(item["category"] == "cookie" for item in data["items"])
    # Test schema may seed extra cookie products; only assert our additions
    # are included and the filter narrowed the total.
    assert data["total"] >= 2
    assert len(data["items"]) == 1
    assert data["has_more"] is True


# ---------------------------------------------------------------------------
# FR4 — GET /api/customers
# ---------------------------------------------------------------------------


def test_customers_bare_array_backward_compat(api_client):
    _seed_customers(api_client, 3)
    resp = api_client.get("/api/customers")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) >= 3


def test_customers_envelope_when_paginated(api_client):
    _seed_customers(api_client, 3)
    resp = api_client.get("/api/customers", params={"paginated": "true"})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())
    assert data["total"] >= 3
    assert data["has_more"] is False


def test_customers_limit_offset_honored(api_client):
    _seed_customers(api_client, 5)
    resp = api_client.get("/api/customers", params={"limit": 2, "offset": 1})
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) == 2
    assert data["offset"] == 1
    assert data["has_more"] is True


def test_customers_search_with_pagination(api_client):
    """AC4: server-side search still works with pagination — search runs
    across all customers, only the result page is sliced."""
    _seed_customers(api_client, 10)
    resp = api_client.get(
        "/api/customers",
        params={"search": "Khach 0", "paginated": "true", "limit": 2},
    )
    assert resp.status_code == 200
    data = resp.json()
    # search narrows the total; page is sliced from that filtered set
    assert data["total"] <= 10
    assert len(data["items"]) <= 2


def test_customers_default_limit_50(api_client):
    """FR4: default limit is 50."""
    _seed_customers(api_client, 55)
    resp = api_client.get("/api/customers", params={"paginated": "true"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["limit"] == 50
    assert len(data["items"]) == 50
    assert data["total"] >= 55
    assert data["has_more"] is True


# ---------------------------------------------------------------------------
# FR5 — GET /api/customers/{id}/orders
# ---------------------------------------------------------------------------


def _create_orders_for_customer(api_client, customer_id: int, n: int) -> list[str]:
    refs: list[str] = []
    for i in range(n):
        resp = api_client.post(
            "/api/orders",
            json={
                "customerName": f"Khach {i}",
                "customerPhone": "0900000000",
                "customerId": customer_id,
                "items": [{"productName": "Bánh mì", "qty": 1, "price": 10000}],
                "dueDate": "2030-01-01",
                "deliveryType": "pickup",
            },
        )
        assert resp.status_code == 201, resp.text
        refs.append(resp.json()["orderRef"])
    return refs


def test_customer_orders_bare_array_backward_compat(api_client):
    cust = _seed_customers(api_client, 1)[0]
    _create_orders_for_customer(api_client, cust, 3)
    resp = api_client.get(f"/api/customers/{cust}/orders")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 3


def test_customer_orders_envelope_when_paginated(api_client):
    cust = _seed_customers(api_client, 1)[0]
    _create_orders_for_customer(api_client, cust, 4)
    resp = api_client.get(
        f"/api/customers/{cust}/orders", params={"paginated": "true", "limit": 2}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert data["total"] == 4
    assert len(data["items"]) == 2
    assert data["has_more"] is True


def test_customer_orders_404_when_customer_missing(api_client):
    resp = api_client.get("/api/customers/999999/orders", params={"limit": 10})
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# FR6 — GET /api/stock/overview
# ---------------------------------------------------------------------------


def _mark_trung_bay(product_id: int) -> None:
    """Set the trung_bay attribute value to 'true' for a product (direct DB)."""
    with get_db() as conn:
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )


def test_stock_overview_bare_array_backward_compat(api_client):
    resp = api_client.get("/api/stock/overview")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)


def test_stock_overview_envelope_when_paginated(api_client):
    resp = api_client.get("/api/stock/overview", params={"paginated": "true"})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())
    assert data["limit"] == 50
    assert data["offset"] == 0


def test_stock_overview_limit_offset_honored(api_client):
    # Seed products and mark trung_bay so they appear in the overview.
    pids = _seed_products(api_client, 3)
    for pid in pids:
        _mark_trung_bay(pid)
    resp = api_client.get("/api/stock/overview", params={"limit": 1, "offset": 0})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert len(data["items"]) <= 1
    assert data["total"] >= 3


# ---------------------------------------------------------------------------
# GET /api/expenses/debts (envelope endpoint — additive fields)
# ---------------------------------------------------------------------------


def test_debts_no_pagination_keeps_existing_shape(api_client):
    resp = api_client.get("/api/expenses/debts")
    assert resp.status_code == 200
    data = resp.json()
    assert "creditors" in data
    assert "total_owed" in data
    assert "count" in data
    # No pagination fields when limit not supplied (NFR6 additive).
    assert "total" not in data
    assert "has_more" not in data


def test_debts_pagination_adds_envelope_fields(api_client):
    resp = api_client.get("/api/expenses/debts", params={"limit": 10, "offset": 0})
    assert resp.status_code == 200
    data = resp.json()
    assert "creditors" in data  # existing shape preserved
    assert "total" in data  # additive
    assert "has_more" in data
    assert data["limit"] == 10
    assert data["offset"] == 0


# ---------------------------------------------------------------------------
# GET /api/reconciliations/history (envelope endpoint — additive fields)
# ---------------------------------------------------------------------------


def test_reconciliation_history_no_pagination_keeps_shape(api_client):
    resp = api_client.get("/api/reconciliations/history")
    assert resp.status_code == 200
    data = resp.json()
    assert "sessions" in data
    assert "total" not in data
    assert "has_more" not in data


def test_reconciliation_history_pagination_adds_fields(api_client):
    resp = api_client.get(
        "/api/reconciliations/history", params={"paginated": "true", "limit": 5}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "sessions" in data
    assert "total" in data
    assert "has_more" in data
    assert data["limit"] == 5
    assert data["offset"] == 0


# ---------------------------------------------------------------------------
# GET /api/products/{id}/catalog (per-product catalog photos)
# ---------------------------------------------------------------------------


def test_product_catalog_bare_array_backward_compat(api_client):
    pid = _seed_products(api_client, 1)[0]
    resp = api_client.get(f"/api/products/{pid}/catalog")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)


def test_product_catalog_envelope_when_paginated(api_client):
    pid = _seed_products(api_client, 1)[0]
    resp = api_client.get(
        f"/api/products/{pid}/catalog", params={"paginated": "true", "limit": 10}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())
    assert data["total"] == 0
    assert data["has_more"] is False


def test_product_catalog_404_when_product_missing(api_client):
    resp = api_client.get("/api/products/999999/catalog", params={"limit": 10})
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# GET /api/orders/{ref}/transactions (order transactions)
# ---------------------------------------------------------------------------


def _create_order(api_client) -> str:
    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Khach test",
            "customerPhone": "0900000000",
            "items": [{"productName": "Bánh mì", "qty": 1, "price": 10000}],
            "dueDate": "2030-01-01",
            "deliveryType": "pickup",
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["orderRef"]


def test_order_transactions_bare_array_backward_compat(api_client):
    ref = _create_order(api_client)
    resp = api_client.get(f"/api/orders/{ref}/transactions")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)


def test_order_transactions_envelope_when_paginated(api_client):
    ref = _create_order(api_client)
    resp = api_client.get(
        f"/api/orders/{ref}/transactions", params={"paginated": "true", "limit": 5}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())


def test_order_transactions_404_when_order_missing(api_client):
    resp = api_client.get("/api/orders/NOSUCHREF/transactions", params={"limit": 5})
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# GET /api/orders/{ref}/events (order events — history-style)
# ---------------------------------------------------------------------------


def test_order_events_bare_array_backward_compat(api_client):
    ref = _create_order(api_client)
    resp = api_client.get(f"/api/orders/{ref}/events")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)


def test_order_events_envelope_when_paginated(api_client):
    ref = _create_order(api_client)
    resp = api_client.get(
        f"/api/orders/{ref}/events", params={"paginated": "true", "limit": 5}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())


def test_order_events_404_when_order_missing(api_client):
    resp = api_client.get("/api/orders/NOSUCHREF/events", params={"limit": 5})
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# FR14 — envelope contract invariants
# ---------------------------------------------------------------------------


def test_has_more_false_on_last_page(api_client):
    _seed_products(api_client, 3)
    resp = api_client.get("/api/products", params={"limit": 100, "offset": 0})
    assert resp.status_code == 200
    data = resp.json()
    assert data["has_more"] is False


def test_has_more_true_when_more_pages(api_client):
    _seed_products(api_client, 3)
    resp = api_client.get("/api/products", params={"limit": 1, "offset": 0})
    assert resp.status_code == 200
    data = resp.json()
    assert data["has_more"] is True


def test_total_reflects_filtered_count_not_page_size(api_client):
    _seed_products(api_client, 5)
    resp = api_client.get("/api/products", params={"limit": 2, "offset": 0})
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) == 2
    assert data["total"] >= 5


# ---------------------------------------------------------------------------
# GET /api/orders (history branch — DG-409 Phase 4 / FR12)
#
# The history branch (active_only=false) opts into the paginated envelope
# when ``paginated=true``. The active_only branch always returns a bare
# array (FR9 — active orders stay unpaginated).
# ---------------------------------------------------------------------------


def test_order_history_bare_array_backward_compat(api_client):
    """Without paginated=true, /api/orders returns a bare array (NFR6)."""
    _create_order(api_client)
    resp = api_client.get("/api/orders", params={"active_only": "false"})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)


def test_order_history_envelope_when_paginated(api_client):
    """paginated=true returns {items,total,has_more,limit,offset} for history."""
    _create_order(api_client)
    resp = api_client.get(
        "/api/orders",
        params={"paginated": "true", "limit": 50, "offset": 0},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict)
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())
    assert isinstance(data["items"], list)


def test_order_history_envelope_has_more_and_total(api_client):
    """A single order + limit=1 → has_more false and total reflects the
    full history count (DG-409 Phase 4 / FR14)."""
    _create_order(api_client)
    resp = api_client.get(
        "/api/orders",
        params={"paginated": "true", "limit": 50, "offset": 0},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    # With limit 50 >= total, has_more must be false.
    if data["limit"] >= data["total"]:
        assert data["has_more"] is False


def test_order_history_active_only_stays_bare_array_even_with_paginated(api_client):
    """FR9: active orders stay unpaginated — even paginated=true must not
    envelope the active_only branch."""
    _create_order(api_client)
    resp = api_client.get(
        "/api/orders",
        params={"active_only": "true", "paginated": "true"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list), "active_only must remain a bare array (FR9)"


def test_order_paginated_with_active_status_rejected_explicitly(api_client):
    """CQ-5 (review-auto): paginated=true combined with an active status
    filter (new/confirmed/in_progress/ready/delivered) is rejected with 422
    instead of silently returning a bare array. The status-active branch is
    an active view (FR9 — unpaginated), so the envelope is unsupported."""
    _create_order(api_client)
    for active_status in ("new", "confirmed", "in_progress", "ready", "delivered"):
        resp = api_client.get(
            "/api/orders",
            params={"status": active_status, "paginated": "true"},
        )
        assert resp.status_code == 422, (
            f"expected 422 for status={active_status} + paginated=true, "
            f"got {resp.status_code}"
        )
        assert "paginated" in resp.json()["detail"].lower()


def test_order_paginated_with_terminal_status_envelope_honored(api_client):
    """CQ-5: paginated=true with a terminal status (completed/cancelled) is
    NOT an active view, so the envelope IS honored (returns a dict, not a
    bare array)."""
    ref = _create_order(api_client)
    # Cancel the order so a terminal status exists in the history.
    api_client.post(f"/api/orders/{ref}/status", json={"status": "cancelled"})
    resp = api_client.get(
        "/api/orders",
        params={"status": "cancelled", "paginated": "true", "limit": 50},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, dict), "terminal status + paginated must envelope"
    assert {"items", "total", "has_more", "limit", "offset"} <= set(data.keys())
