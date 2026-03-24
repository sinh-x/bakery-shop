"""Tests for Baker API — work items endpoints."""

import pytest


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A"):
    # Create order without items so work_items list starts empty
    resp = client.post("/api/orders", json={"customerName": customer})
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


def test_update_work_item_birthday_and_age(api_client):
    """PATCH can update isBirthday and age fields."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.patch(f"/api/orders/{ref}/items/{item_id}", json={
        "isBirthday": True,
        "age": 5,
    })
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["isBirthday"] is True
    assert updated["age"] == 5
    # Can clear age by setting isBirthday to false
    resp2 = api_client.patch(f"/api/orders/{ref}/items/{item_id}", json={
        "isBirthday": False,
    })
    assert resp2.status_code == 200
    assert resp2.json()["isBirthday"] is False


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


# --- Cancelled status ---


def test_cancel_work_item_from_pending(api_client):
    """Transitioning from pending to cancelled succeeds (no reason required — forward transition)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "cancelled", "reason": ""},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


def test_cancel_work_item_from_working(api_client):
    """Transitioning from working to cancelled succeeds."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": "working", "reason": ""})
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "cancelled", "reason": ""},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


def test_cancel_work_item_from_ready(api_client):
    """Transitioning from ready to cancelled succeeds."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    for status in ["working", "ready"]:
        api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": status, "reason": ""})
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "cancelled", "reason": ""},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


def test_cancel_work_item_from_delivered(api_client):
    """Transitioning from delivered to cancelled succeeds."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    for status in ["working", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": status, "reason": ""})
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "cancelled", "reason": ""},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


def test_cancelled_is_terminal(api_client):
    """Cannot transition FROM cancelled to any other status — cancelled is terminal."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": "cancelled", "reason": ""})
    for target in ["pending", "working", "ready", "delivered"]:
        resp = api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": target, "reason": "Thử lại"},
        )
        assert resp.status_code == 422, f"Expected 422 transitioning from cancelled to {target}"


def test_cancelled_is_valid_status_value(api_client):
    """The API accepts 'cancelled' as a valid work item status string (not rejected as invalid)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "cancelled", "reason": ""},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


# --- Migration: order_items table populated from orders.items JSON ---


# --- Birthday / age fields (v13) ---


def test_create_work_item_with_birthday(api_client):
    """Work item created with isBirthday=True and age is stored and returned."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/items", json={
        "productName": "Bánh kem sinh nhật",
        "unitPrice": 300000,
        "isBirthday": True,
        "age": 7,
    })
    assert resp.status_code == 201
    item = resp.json()
    assert item["isBirthday"] is True
    assert item["age"] == 7


def test_create_work_item_without_birthday_defaults(api_client):
    """Work item created without birthday fields defaults to isBirthday=False, age=None."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/items", json={"productName": "Bánh mì"})
    assert resp.status_code == 201
    item = resp.json()
    assert item["isBirthday"] is False
    assert item["age"] is None


def test_order_creation_creates_work_items_with_birthday(api_client):
    """Creating an order with items including birthday fields creates order_items rows."""
    resp = api_client.post("/api/orders", json={
        "customerName": "Khách hàng",
        "items": [
            {"productName": "Bánh kem 20cm", "unitPrice": 350000, "isBirthday": True, "age": 5},
            {"productName": "Bánh mì", "unitPrice": 10000},
        ],
    })
    assert resp.status_code == 201
    order = resp.json()
    work_items = order["workItems"]
    assert len(work_items) == 2
    assert work_items[0]["isBirthday"] is True
    assert work_items[0]["age"] == 5
    assert work_items[1]["isBirthday"] is False
    assert work_items[1]["age"] is None


def test_patch_work_item_syncs_order_items_json(api_client):
    """PATCH work item must regenerate orders.items JSON and recalculate total_price."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, unitPrice=200000.0, quantity=1)
    item_id = item["id"]

    # Patch quantity and price
    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"quantity": 2, "unitPrice": 250000.0},
    )
    assert resp.status_code == 200

    # GET order and verify items JSON and total_price are synced
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.status_code == 200
    order_data = order_resp.json()

    assert len(order_data["items"]) == 1
    synced_item = order_data["items"][0]
    assert synced_item["quantity"] == 2
    assert synced_item["unitPrice"] == 250000.0
    assert order_data["totalPrice"] == 500000.0


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
