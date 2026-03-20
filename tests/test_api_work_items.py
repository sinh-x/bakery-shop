"""Tests for Baker API — work items endpoints."""

import pytest


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A"):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000}],
    })
    assert resp.status_code == 201
    return resp.json()


def _create_item(client, ref, **kwargs):
    payload = {"productName": "Bánh kem 16cm", **kwargs}
    resp = client.post(f"/api/orders/{ref}/items", json=payload)
    assert resp.status_code == 201
    return resp.json()


# --- List work items ---


def test_list_work_items_empty(api_client):
    order = _create_order(api_client)
    resp = api_client.get(f"/api/orders/{order['orderRef']}/items")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_work_items_returns_created(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    _create_item(api_client, ref)
    resp = api_client.get(f"/api/orders/{ref}/items")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


def test_list_work_items_order_not_found(api_client):
    resp = api_client.get("/api/orders/ORD-NOTEXIST/items")
    assert resp.status_code == 404


# --- Create work item ---


def test_create_work_item_minimal(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/items", json={"productName": "Bánh mì"})
    assert resp.status_code == 201
    item = resp.json()
    assert item["productName"] == "Bánh mì"
    assert item["quantity"] == 1
    assert item["unitPrice"] == 0.0
    assert item["status"] == "pending"
    assert item["orderId"] == order["id"]


def test_create_work_item_with_all_fields(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/items", json={
        "productName": "Bánh kem 20cm",
        "productId": "BKS-20",
        "quantity": 2,
        "unitPrice": 350000,
        "notes": "Không đường",
        "position": 1,
    })
    assert resp.status_code == 201
    item = resp.json()
    assert item["productId"] == "BKS-20"
    assert item["quantity"] == 2
    assert item["unitPrice"] == 350000
    assert item["notes"] == "Không đường"
    assert item["position"] == 1


def test_create_work_item_id_is_string(api_client):
    order = _create_order(api_client)
    item = _create_item(api_client, order["orderRef"])
    assert isinstance(item["id"], str)


def test_create_work_item_order_not_found(api_client):
    resp = api_client.post("/api/orders/ORD-NOTEXIST/items", json={"productName": "x"})
    assert resp.status_code == 404


# --- Update work item ---


def test_update_work_item_notes(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.patch(f"/api/orders/{ref}/items/{item_id}", json={"notes": "Ghi chú mới"})
    assert resp.status_code == 200
    assert resp.json()["notes"] == "Ghi chú mới"


def test_update_work_item_quantity(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.patch(f"/api/orders/{ref}/items/{item_id}", json={"quantity": 3})
    assert resp.status_code == 200
    assert resp.json()["quantity"] == 3


def test_update_work_item_empty_body(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.patch(f"/api/orders/{ref}/items/{item_id}", json={})
    assert resp.status_code == 400
    assert "Không có gì" in resp.json()["detail"]


def test_update_work_item_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/items/9999", json={"notes": "x"})
    assert resp.status_code == 404


def test_update_work_item_wrong_order(api_client):
    order1 = _create_order(api_client, customer="A")
    order2 = _create_order(api_client, customer="B")
    item = _create_item(api_client, order1["orderRef"])
    # Try to update item from order1 via order2's ref
    resp = api_client.patch(
        f"/api/orders/{order2['orderRef']}/items/{item['id']}",
        json={"notes": "hack"},
    )
    assert resp.status_code == 404


# --- Delete work item ---


def test_delete_work_item(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.delete(f"/api/orders/{ref}/items/{item_id}")
    assert resp.status_code == 204
    # Confirm gone
    list_resp = api_client.get(f"/api/orders/{ref}/items")
    assert list_resp.json() == []


def test_delete_work_item_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.delete(f"/api/orders/{ref}/items/9999")
    assert resp.status_code == 404


def test_delete_work_item_wrong_order(api_client):
    order1 = _create_order(api_client, customer="A")
    order2 = _create_order(api_client, customer="B")
    item = _create_item(api_client, order1["orderRef"])
    resp = api_client.delete(f"/api/orders/{order2['orderRef']}/items/{item['id']}")
    assert resp.status_code == 404


# --- Work item status transition ---


def test_work_item_status_transition(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "working", "reason": "Bắt đầu làm"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "working"


def test_work_item_status_full_flow(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    for status in ["working", "ready", "delivered"]:
        resp = api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": status, "reason": "Tiến độ"},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == status


def test_work_item_forward_without_reason_ok(api_client):
    """Forward transitions (pending -> working) do not require a reason."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "working", "reason": ""},
    )
    assert resp.status_code == 200


def test_work_item_backward_requires_reason(api_client):
    """Backward transitions require a reason."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    # Move forward: pending -> working
    api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "working", "reason": ""},
    )
    # Backward without reason: working -> pending -> 422
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "pending", "reason": ""},
    )
    assert resp.status_code == 422
    assert "Lý do" in resp.json()["detail"]
    # With reason -> ok
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "pending", "reason": "Cần làm lại"},
    )
    assert resp.status_code == 200


def test_work_item_status_invalid_value(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "invalid_status", "reason": "test"},
    )
    assert resp.status_code == 422


def test_work_item_status_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/items/9999/status",
        json={"status": "working", "reason": "test"},
    )
    assert resp.status_code == 404


# --- Migration: order_items table populated from orders.items JSON ---


def test_migration_v12_order_items_created(api_client):
    """Order created via old-style items JSON is accessible via work items endpoint."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        # Manually insert an order (simulating pre-v12 data)
        import json
        items_json = json.dumps([{"product": "Bánh mì", "qty": 2, "price": 10000, "notes": "", "product_id": ""}])
        cursor = conn.execute(
            """INSERT INTO orders (order_ref, customer_name, items, total_price, status)
               VALUES ('ORD-MIGRATION-001', 'Test', ?, 20000, 'new')""",
            (items_json,),
        )
        order_id = cursor.lastrowid
        # Populate order_items as migration would
        conn.execute(
            """INSERT INTO order_items (order_id, product_id, product_name, quantity, unit_price, notes, position)
               VALUES (?, '', 'Bánh mì', 2, 10000, '', 0)""",
            (order_id,),
        )

    resp = api_client.get("/api/orders/ORD-MIGRATION-001/items")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) == 1
    assert items[0]["productName"] == "Bánh mì"
    assert items[0]["quantity"] == 2
