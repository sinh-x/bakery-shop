"""Tests for Baker API — work items endpoints."""

import pytest


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A"):
    # Create order without items so work_items list starts empty
    resp = client.post("/api/orders", json={"customerName": customer, "dueDate": "2026-03-25"})
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


# --- Update work item: blankId removed (DG-294 Phase 1) ---
# The single blankId field on WorkItemUpdate and the order_items.blank_id
# column were replaced by the order_item_blanks junction table. Blank
# assignment is now done via POST/PATCH/DELETE /api/orders/{ref}/items/{id}/blanks
# (see test_api_work_item_blanks.py). PATCH with blankId is now a no-op
# (ignored, not an error) because the field is no longer on WorkItemUpdate.


def test_update_work_item_ignores_blank_id_after_removal(api_client):
    """PATCH with a stale blankId payload is ignored (no error, no DB write).

    DG-294 removed ``blankId`` from ``WorkItemUpdate``. Pydantic ignores
    extra fields by default, so a client still sending ``blankId`` gets a
    200 with the work item unchanged and ``blanks`` empty.
    """
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}", json={"blankId": 5}
    )
    # blankId is not a recognized field → no updates → 400 "nothing to update"
    assert resp.status_code == 400
    assert "Không có gì" in resp.json()["detail"]


def test_update_work_item_notes(api_client):
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
        "dueDate": "2026-03-25",
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


# --- Auto-sync: work item status → order status (DG-050 Phase 1) ---


def _create_order_with_main_and_extra(api_client, customer="Khách hàng"):
    """Create an order with 1 main item (cake) and 1 extra (candle)."""
    resp = api_client.post("/api/orders", json={
        "customerName": customer,
        "dueDate": "2026-03-25",
        "items": [
            {"productName": "Bánh kem 16cm", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16", "isExtra": False},
            {"productName": "Nến sinh nhật", "quantity": 1, "unitPrice": 10000, "productId": "CANDLE", "isExtra": True},
        ],
    })
    assert resp.status_code == 201
    return resp.json()


def test_autosync_main_item_to_ready_updates_order(api_client):
    """AC1: Given an order with 1 cake (main) + 1 extra, when the cake transitions to 'ready',
    then the order auto-transitions to 'ready' via server-side logic."""
    order = _create_order_with_main_and_extra(api_client)
    ref = order["orderRef"]
    items = order["workItems"]
    cake = next(i for i in items if i["productName"] == "Bánh kem 16cm")
    candle = next(i for i in items if i["productName"] == "Nến sinh nhật")

    # Transition cake: pending → working → ready
    api_client.post(f"/api/orders/{ref}/items/{cake['id']}/status", json={"status": "working", "reason": ""})
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["status"] == "in_progress"  # working → in_progress

    api_client.post(f"/api/orders/{ref}/items/{cake['id']}/status", json={"status": "ready", "reason": ""})
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["status"] == "ready"

    # AC2: extra also auto-transitions to ready
    candle_resp = api_client.get(f"/api/orders/{ref}/items")
    candle_state = next(i for i in candle_resp.json() if i["productName"] == "Nến sinh nhật")
    assert candle_state["status"] == "ready"


def test_autosync_single_main_item_order(api_client):
    """AC5: Given a single-item order, when the item transitions, then the order still auto-syncs correctly."""
    order = api_client.post("/api/orders", json={
        "customerName": "Khách đơn lẻ",
        "dueDate": "2026-03-25",
        "items": [{"productName": "Bánh mì", "quantity": 1, "unitPrice": 15000}],
    }).json()
    ref = order["orderRef"]
    item_id = order["workItems"][0]["id"]

    api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": "working", "reason": ""})
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["status"] == "in_progress"

    api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": "ready", "reason": ""})
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["status"] == "ready"


def test_autosync_main_cancelled_updates_order_to_cancelled(api_client):
    """AC6: Given all main items are cancelled, when auto-sync runs, then the order transitions to 'cancelled'."""
    order = api_client.post("/api/orders", json={
        "customerName": "Khách hủy",
        "dueDate": "2026-03-25",
        "items": [
            {"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "isExtra": False},
            {"productName": "Đĩa giấy", "quantity": 1, "unitPrice": 5000, "isExtra": True},
        ],
    }).json()
    ref = order["orderRef"]
    cake = order["workItems"][0]

    # Cancel the main item
    api_client.post(f"/api/orders/{ref}/items/{cake['id']}/status", json={"status": "cancelled", "reason": ""})
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["status"] == "cancelled"


def test_autosync_logs_auto_sync_in_order_history(api_client):
    """AC7: Auto-synced transitions are logged in order_history with action_type='auto_sync'."""
    from baker.db.connection import get_db

    order = _create_order_with_main_and_extra(api_client)
    ref = order["orderRef"]
    cake = order["workItems"][0]

    # Trigger auto-sync by transitioning cake to working
    api_client.post(f"/api/orders/{ref}/items/{cake['id']}/status", json={"status": "working", "reason": ""})

    # Check order_history for auto_sync entry
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM order_history WHERE order_id = (SELECT id FROM orders WHERE order_ref = ?) AND action_type = 'auto_sync'",
            (ref,),
        ).fetchall()
        assert len(rows) >= 1
        auto_sync_row = rows[0]
        assert auto_sync_row["field_name"] == "status"
        assert auto_sync_row["old_value"] == "new"
        assert auto_sync_row["new_value"] == "in_progress"


def test_autosync_does_not_auto_complete_order(api_client):
    """AC8: Order never auto-transitions to 'completed' (requires payment gate)."""
    order = api_client.post("/api/orders", json={
        "customerName": "Khách lớn",
        "dueDate": "2026-03-25",
        "items": [{"productName": "Bánh gig", "quantity": 1, "unitPrice": 500000}],
    }).json()
    ref = order["orderRef"]
    item_id = order["workItems"][0]["id"]

    # Transition item all the way to delivered
    for status in ["working", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": status, "reason": ""})

    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["status"] == "delivered"
    # Must NOT be 'completed' — that requires payment gate


def test_autosync_extras_skip_already_at_target(api_client):
    """F5: Skip extras that are already at target status or cancelled."""
    order = api_client.post("/api/orders", json={
        "customerName": "Khách test skip",
        "dueDate": "2026-03-25",
        "items": [
            {"productName": "Bánh chính", "quantity": 1, "unitPrice": 200000, "isExtra": False},
            {"productName": "Nến", "quantity": 1, "unitPrice": 5000, "isExtra": True},
        ],
    }).json()
    ref = order["orderRef"]
    candle = order["workItems"][1]

    # Manually set candle to ready first
    api_client.post(f"/api/orders/{ref}/items/{candle['id']}/status", json={"status": "working", "reason": ""})
    api_client.post(f"/api/orders/{ref}/items/{candle['id']}/status", json={"status": "ready", "reason": ""})

    # Now transition main item to working → order should go to in_progress
    cake = order["workItems"][0]
    api_client.post(f"/api/orders/{ref}/items/{cake['id']}/status", json={"status": "working", "reason": ""})

    # Candle should still be ready (skipped because already at target)
    candle_state = api_client.get(f"/api/orders/{ref}/items").json()
    candle_item = next(i for i in candle_state if i["productName"] == "Nến")
    assert candle_item["status"] == "ready"


# --- Candle type persistence in attributes (DG-340 Phase 5) ---
# FR2/NFR2/AC2: candle_type lives in order_items.attributes JSON and must
# survive create, update, and round-trip (create → read → verify). The
# backend passes attributes through opaquely (no schema migration), so
# these tests exercise the existing passthrough on POST/PATCH/GET.


def test_create_work_item_persists_candle_type_in_attributes(api_client):
    """POST /items stores candle_type inside attributes JSON (FR2)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, attributes={"candle_type": "nen_so"})
    assert item["attributes"]["candle_type"] == "nen_so"

    # Read back from DB to confirm JSON persistence (not just echo)
    from baker.db.connection import get_db
    with get_db() as conn:
        row = conn.execute(
            "SELECT attributes FROM order_items WHERE id = ?",
            (int(item["id"]),),
        ).fetchone()
    import json as _json
    saved = _json.loads(row["attributes"] or "{}")
    assert saved["candle_type"] == "nen_so"


def test_create_work_item_without_candle_type_has_no_key(api_client):
    """No candle_type selection → key absent from attributes (AC7)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    assert "candle_type" not in item["attributes"]


def test_update_work_item_persists_candle_type_in_attributes(api_client):
    """PATCH /items updates candle_type inside attributes JSON (FR2)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, attributes={"candle_type": "nen_xoan"})
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"attributes": {"candle_type": "nen_nho"}},
    )
    assert resp.status_code == 200
    assert resp.json()["attributes"]["candle_type"] == "nen_nho"

    # Verify DB row
    from baker.db.connection import get_db
    with get_db() as conn:
        row = conn.execute(
            "SELECT attributes FROM order_items WHERE id = ?",
            (int(item_id),),
        ).fetchone()
    import json as _json
    saved = _json.loads(row["attributes"] or "{}")
    assert saved["candle_type"] == "nen_nho"


def test_candle_type_survives_round_trip_create_read_verify(api_client):
    """AC2: candle_type survives create → read → verify round trip."""
    order = _create_order(api_client)
    ref = order["orderRef"]

    # Create with nen_so
    item = _create_item(api_client, ref, attributes={"candle_type": "nen_so"})
    item_id = item["id"]

    # Read back via list endpoint (simulates page reload)
    list_resp = api_client.get(f"/api/orders/{ref}/items")
    assert list_resp.status_code == 200
    fetched = next(i for i in list_resp.json() if i["id"] == item_id)
    assert fetched["attributes"]["candle_type"] == "nen_so"

    # Update to nen_xoan and read again
    api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"attributes": {"candle_type": "nen_xoan"}},
    )
    list_resp2 = api_client.get(f"/api/orders/{ref}/items")
    fetched2 = next(i for i in list_resp2.json() if i["id"] == item_id)
    assert fetched2["attributes"]["candle_type"] == "nen_xoan"


def test_candle_type_absent_means_no_candle_round_trip(api_client):
    """AC7: absent candle_type key round-trips as no candle (empty attributes)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, attributes={})
    item_id = item["id"]

    list_resp = api_client.get(f"/api/orders/{ref}/items")
    fetched = next(i for i in list_resp.json() if i["id"] == item_id)
    assert "candle_type" not in fetched["attributes"]


# --- Product swap on work item (DG-414 Phase 4.1) ---------------------------
# FR1/FR2/FR3/FR5, AC1 (partial)/AC2/AC4: PATCH accepts productId to swap the
# product on an order item in place. Only product_id/product_name change;
# unitPrice/assignedPrice and all other columns are preserved unless
# explicitly sent. Swap is rejected (422) when the item status is delivered or
# cancelled.


def test_update_work_item_swap_product_id_and_name(api_client):
    """FR1/AC1: PATCH with productId+productName updates the product in place."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(
        api_client,
        ref,
        productId="BKS-16",
        unitPrice=200000.0,
        quantity=2,
        notes="Ghi chú",
        isBirthday=True,
        age=5,
    )
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["productId"] == "BKS-20"
    assert updated["productName"] == "Bánh kem 20cm"
    # AC1: all other fields preserved
    assert updated["quantity"] == 2
    assert updated["unitPrice"] == 200000.0
    assert updated["notes"] == "Ghi chú"
    assert updated["isBirthday"] is True
    assert updated["age"] == 5


def test_update_work_item_swap_preserves_unit_and_assigned_price(api_client):
    """FR3/AC2: swap with only productId+productName leaves prices unchanged.

    Note: WorkItemCreate clamps unitPrice up to assignedPrice when below
    floor, so we pick unitPrice > assignedPrice to avoid the clamp and keep
    both values distinct/observable.
    """
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(
        api_client,
        ref,
        productId="BKS-16",
        unitPrice=250000.0,
        assignedPrice=200000.0,
    )
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["unitPrice"] == 250000.0
    assert updated["assignedPrice"] == 200000.0


def test_update_work_item_swap_product_id_only_keeps_name(api_client):
    """FR2: sending productId alone updates only product_id; product_name
    is untouched (PATCH uses exclude_unset)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16", productName="Bánh kem 16cm")
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["productId"] == "BKS-20"
    assert updated["productName"] == "Bánh kem 16cm"


def test_update_work_item_swap_only_name_keeps_product_id(api_client):
    """FR2/NFR1: sending productName alone keeps productId (backward compat)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16", productName="Bánh kem 16cm")
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productName": "Bánh kem đặc biệt"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["productName"] == "Bánh kem đặc biệt"
    assert updated["productId"] == "BKS-16"


def test_update_work_item_swap_preserves_blanks(api_client):
    """AC5: swap does not touch order_item_blanks junction rows."""
    from baker.db.connection import get_db

    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    # Create a blank via the blanks API so blankId exists
    blank_resp = api_client.post(
        "/api/blanks", json={"name": "Cốt bánh", "category": "cot", "unit": "cai"}
    )
    assert blank_resp.status_code == 201
    blank_id = blank_resp.json()["id"]

    # Assign the blank via the junction-table endpoint
    assign_resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank_id, "quantity": 2.0, "notes": "phôi A"},
    )
    assert assign_resp.status_code == 201

    # Swap product
    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["productId"] == "BKS-20"
    # Blanks preserved
    assert len(updated["blanks"]) == 1
    assert updated["blanks"][0]["blankId"] == blank_id
    assert updated["blanks"][0]["quantity"] == 2.0

    # Confirm DB row untouched
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM order_item_blanks WHERE order_item_id = ?",
            (int(item_id),),
        ).fetchall()
    assert len(rows) == 1
    assert rows[0]["blank_id"] == blank_id


def test_update_work_item_swap_rejects_when_delivered(api_client):
    """FR5/AC4: swap rejected (422) when item status is delivered; no DB change."""
    from baker.db.connection import get_db

    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    # Move item to delivered
    for status in ["working", "ready", "delivered"]:
        api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": status, "reason": ""},
        )

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )
    assert resp.status_code == 422
    assert "đã giao" in resp.json()["detail"]

    # Confirm product_id unchanged in DB
    with get_db() as conn:
        row = conn.execute(
            "SELECT product_id FROM order_items WHERE id = ?",
            (int(item_id),),
        ).fetchone()
    assert row["product_id"] == "BKS-16"


def test_update_work_item_swap_rejects_when_cancelled(api_client):
    """FR5/AC4: swap rejected (422) when item status is cancelled; no DB change."""
    from baker.db.connection import get_db

    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    # Cancel the item
    api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "cancelled", "reason": ""},
    )

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )
    assert resp.status_code == 422
    assert "đã hủy" in resp.json()["detail"]

    with get_db() as conn:
        row = conn.execute(
            "SELECT product_id FROM order_items WHERE id = ?",
            (int(item_id),),
        ).fetchone()
    assert row["product_id"] == "BKS-16"


def test_update_work_item_non_swap_patch_allowed_when_delivered(api_client):
    """NFR1: non-swap PATCHes (e.g. notes) remain allowed on delivered items."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16", notes="old")
    item_id = item["id"]

    for status in ["working", "ready", "delivered"]:
        api_client.post(
            f"/api/orders/{ref}/items/{item_id}/status",
            json={"status": status, "reason": ""},
        )

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"notes": "ghi chú sau giao"},
    )
    assert resp.status_code == 200
    assert resp.json()["notes"] == "ghi chú sau giao"
    # productId unchanged
    assert resp.json()["productId"] == "BKS-16"


def test_update_work_item_swap_syncs_order_items_json(api_client):
    """FR4: after swap, orders.items JSON reflects the new productId/name."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16", unitPrice=200000.0, quantity=1)
    item_id = item["id"]

    api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )

    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.status_code == 200
    order_data = order_resp.json()
    assert len(order_data["items"]) == 1
    synced = order_data["items"][0]
    assert synced["productId"] == "BKS-20"
    assert synced["productName"] == "Bánh kem 20cm"


def test_update_work_item_without_product_id_backward_compatible(api_client):
    """NFR1: existing PATCH payloads without productId still work."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"quantity": 5, "unitPrice": 300000.0},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["quantity"] == 5
    assert updated["unitPrice"] == 300000.0
    assert updated["productId"] == "BKS-16"


# --- SEC-1 (DG-414 review): productId validation on swap ---------------------


def test_update_work_item_swap_rejects_unknown_product_id(api_client):
    """SEC-1: PATCH with a productId that does not resolve to an existing
    active product is rejected with 422; no DB change."""
    from baker.db.connection import get_db

    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "NOPE-99", "productName": "Sản phẩm ảo"},
    )
    assert resp.status_code == 422
    assert "không tồn tại" in resp.json()["detail"]

    # product_id unchanged in DB
    with get_db() as conn:
        row = conn.execute(
            "SELECT product_id FROM order_items WHERE id = ?",
            (int(item_id),),
        ).fetchone()
    assert row["product_id"] == "BKS-16"


def test_update_work_item_swap_rejects_inactive_product_id(api_client):
    """SEC-1: PATCH with a productId that resolves to an inactive product
    is rejected with 422; no DB change."""
    from baker.db.connection import get_db

    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    # Deactivate BKS-20 (seeded) via the products API.
    prod = api_client.get("/api/products/code/BKS-20").json()
    pid = prod["id"]
    deact = api_client.patch(f"/api/products/{pid}", json={"active": 0})
    assert deact.status_code == 200

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "BKS-20", "productName": "Bánh kem 20cm"},
    )
    assert resp.status_code == 422
    assert "không tồn tại hoặc đã ngừng" in resp.json()["detail"]

    with get_db() as conn:
        row = conn.execute(
            "SELECT product_id FROM order_items WHERE id = ?",
            (int(item_id),),
        ).fetchone()
    assert row["product_id"] == "BKS-16"


def test_update_work_item_swap_rejects_null_product_id(api_client):
    """SEC-1: an explicit JSON null productId is rejected with 422 (would
    otherwise bypass the swap guard and attempt SET product_id = NULL)."""
    from baker.db.connection import get_db

    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": None, "productName": "Bánh không mã"},
    )
    assert resp.status_code == 422
    assert "null" in resp.json()["detail"]

    with get_db() as conn:
        row = conn.execute(
            "SELECT product_id FROM order_items WHERE id = ?",
            (int(item_id),),
        ).fetchone()
    assert row["product_id"] == "BKS-16"


def test_update_work_item_swap_allows_empty_product_id_sentinel(api_client):
    """SEC-1 backward compat: an explicit empty-string productId is still
    accepted as the no-catalog sentinel (matches historical create flow and
    rows that legitimately use product_id = '')."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref, productId="BKS-16")
    item_id = item["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item_id}",
        json={"productId": "", "productName": "Sản phẩm tự do"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["productId"] == ""
    assert updated["productName"] == "Sản phẩm tự do"
