"""Tests for Baker API — GET /api/work-items (cake queue)."""

import pytest


# --- Helpers ---


def _create_order(client, customer="Nguyễn Văn A", due_date="2026-03-25", **kwargs):
    payload = {"customerName": customer, "dueDate": due_date}
    payload.update(kwargs)
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_order_with_items(client, items, customer="Test", due_date="2026-03-25"):
    payload = {"customerName": customer, "items": items, "dueDate": due_date}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


# --- Basic listing ---


def test_cake_queue_empty(api_client):
    resp = api_client.get("/api/work-items")
    assert resp.status_code == 200
    assert resp.json() == []


def test_cake_queue_returns_pending_items(api_client):
    _create_order_with_items(api_client, [
        {"productName": "Bánh kem 16cm", "unitPrice": 200000},
    ])
    resp = api_client.get("/api/work-items")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) == 1
    assert items[0]["productName"] == "Bánh kem 16cm"
    assert items[0]["status"] == "pending"


def test_cake_queue_item_has_required_fields(api_client):
    order = _create_order_with_items(api_client, [
        {"productName": "Bánh kem 20cm", "unitPrice": 350000, "isBirthday": True, "age": 3},
    ], customer="Khách hàng A", due_date="2026-03-25")
    resp = api_client.get("/api/work-items")
    assert resp.status_code == 200
    item = resp.json()[0]
    assert "id" in item
    assert "orderId" in item
    assert "orderRef" in item
    assert item["customerName"] == "Khách hàng A"
    assert item["productName"] == "Bánh kem 20cm"
    assert item["dueDate"] == "2026-03-25"
    assert item["status"] == "pending"
    assert item["isBirthday"] is True
    assert item["age"] == 3


def test_cake_queue_id_is_string(api_client):
    _create_order_with_items(api_client, [{"productName": "Bánh mì", "unitPrice": 10000}])
    items = api_client.get("/api/work-items").json()
    assert isinstance(items[0]["id"], str)
    assert isinstance(items[0]["orderId"], str)


# --- Status filtering ---


def test_cake_queue_excludes_delivered_by_default(api_client):
    order = _create_order_with_items(api_client, [
        {"productName": "Bánh kem", "unitPrice": 200000},
    ])
    ref = order["orderRef"]
    item_id = order["workItems"][0]["id"]
    # Advance to delivered
    for status in ["working", "ready", "delivered"]:
        api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": status, "reason": "test"},
        )
    resp = api_client.get("/api/work-items")
    assert resp.status_code == 200
    assert resp.json() == []


def test_cake_queue_excludes_ready_by_default(api_client):
    order = _create_order_with_items(api_client, [
        {"productName": "Bánh kem", "unitPrice": 200000},
    ])
    ref = order["orderRef"]
    item_id = order["workItems"][0]["id"]
    for status in ["working", "ready"]:
        api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": status, "reason": "test"},
        )
    resp = api_client.get("/api/work-items")
    assert resp.status_code == 200
    assert resp.json() == []


def test_cake_queue_include_ready(api_client):
    order = _create_order_with_items(api_client, [
        {"productName": "Bánh kem", "unitPrice": 200000},
    ])
    ref = order["orderRef"]
    item_id = order["workItems"][0]["id"]
    for status in ["working", "ready"]:
        api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": status, "reason": "test"},
        )
    resp = api_client.get("/api/work-items", params={"include_ready": "true"})
    assert resp.status_code == 200
    assert len(resp.json()) == 1
    assert resp.json()[0]["status"] == "ready"


# --- Sorting ---


def test_cake_queue_sorted_by_due_date_ascending(api_client):
    _create_order_with_items(
        api_client, [{"productName": "Bánh C", "unitPrice": 100000}],
        due_date="2026-03-27",
    )
    _create_order_with_items(
        api_client, [{"productName": "Bánh A", "unitPrice": 100000}],
        due_date="2026-03-25",
    )
    _create_order_with_items(
        api_client, [{"productName": "Bánh B", "unitPrice": 100000}],
        due_date="2026-03-26",
    )
    items = api_client.get("/api/work-items").json()
    names = [i["productName"] for i in items]
    assert names == ["Bánh A", "Bánh B", "Bánh C"]


def test_cake_queue_null_due_date_last(api_client):
    _create_order_with_items(
        api_client, [{"productName": "Không hạn", "unitPrice": 100000}],
        due_date="2026-03-26",
    )
    _create_order_with_items(
        api_client, [{"productName": "Có hạn", "unitPrice": 100000}],
        due_date="2026-03-25",
    )
    items = api_client.get("/api/work-items").json()
    assert items[0]["productName"] == "Có hạn"
    assert items[1]["productName"] == "Không hạn"


# --- Cross-order listing ---


def test_cake_queue_spans_multiple_orders(api_client):
    _create_order_with_items(
        api_client, [{"productName": "Bánh A", "unitPrice": 200000}], customer="A",
    )
    _create_order_with_items(
        api_client, [{"productName": "Bánh B", "unitPrice": 200000}], customer="B",
    )
    items = api_client.get("/api/work-items").json()
    assert len(items) == 2
    customers = {i["customerName"] for i in items}
    assert customers == {"A", "B"}


def test_cake_queue_multi_item_order(api_client):
    _create_order_with_items(api_client, [
        {"productName": "Bánh kem 16cm", "unitPrice": 200000},
        {"productName": "Bánh kem 20cm", "unitPrice": 350000},
    ])
    items = api_client.get("/api/work-items").json()
    assert len(items) == 2


# --- Pagination ---


def test_cake_queue_pagination(api_client):
    for i in range(5):
        _create_order_with_items(
            api_client, [{"productName": f"Bánh {i}", "unitPrice": 100000}]
        )
    resp = api_client.get("/api/work-items", params={"limit": 3, "offset": 0})
    assert resp.status_code == 200
    assert len(resp.json()) == 3

    resp2 = api_client.get("/api/work-items", params={"limit": 3, "offset": 3})
    assert resp2.status_code == 200
    assert len(resp2.json()) == 2
