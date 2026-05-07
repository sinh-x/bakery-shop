"""Tests for Baker API — orders endpoints."""

import pytest

from baker.db.connection import get_db


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A", items=None, **kwargs):
    if items is None:
        items = [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}]
    payload = {"customerName": customer, "items": items, **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _ensure_trung_bay(product_id: int) -> None:
    with get_db() as conn:
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )


def _create_chip(client, product_id: int, label: str, price: float) -> int:
    resp = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price},
    )
    assert resp.status_code == 201
    return int(resp.json()["id"])


# --- List orders ---


def test_list_orders_empty(api_client):
    resp = api_client.get("/api/orders")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_orders_returns_created(api_client):
    _create_order(api_client)
    resp = api_client.get("/api/orders")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


def test_list_orders_filter_by_status(api_client):
    _create_order(api_client, customer="A")
    _create_order(api_client, customer="B")
    resp = api_client.get("/api/orders", params={"status": "new"})
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_list_orders_filter_by_status_no_match(api_client):
    _create_order(api_client)
    resp = api_client.get("/api/orders", params={"status": "delivered"})
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_orders_filter_by_due_date(api_client):
    _create_order(api_client, customer="Due today", dueDate="2026-03-20")
    _create_order(api_client, customer="Due tomorrow", dueDate="2026-03-21")
    resp = api_client.get("/api/orders", params={"due_date": "2026-03-20"})
    assert resp.status_code == 200
    orders = resp.json()
    assert len(orders) == 1
    assert orders[0]["customerName"] == "Due today"


def test_list_orders_pagination(api_client):
    for i in range(5):
        _create_order(api_client, customer=f"Customer {i}")
    resp = api_client.get("/api/orders", params={"limit": 3, "offset": 0})
    assert resp.status_code == 200
    assert len(resp.json()) == 3


# --- Create order ---


def test_create_order_minimal(api_client):
    resp = api_client.post("/api/orders", json={"customerName": "Trần Thị B"})
    assert resp.status_code == 201
    order = resp.json()
    assert order["customerName"] == "Trần Thị B"
    assert order["status"] == "new"
    assert order["deliveryType"] == "pickup"
    assert order["amountPaid"] == 0.0
    assert order["isPaid"] is False


def test_create_order_with_items(api_client):
    order = _create_order(api_client)
    assert len(order["items"]) == 1
    assert order["items"][0]["productName"] == "Bánh kem"
    assert order["items"][0]["quantity"] == 1
    assert order["items"][0]["unitPrice"] == 200000
    assert order["totalPrice"] == 200000


def test_create_order_calculates_total(api_client):
    items = [
        {"productName": "Bánh kem", "quantity": 2, "unitPrice": 200000},
        {"productName": "Bánh mì", "quantity": 3, "unitPrice": 10000},
    ]
    resp = api_client.post("/api/orders", json={"customerName": "Test", "items": items})
    assert resp.status_code == 201
    assert resp.json()["totalPrice"] == 430000


def test_create_order_returns_camel_case_fields(api_client):
    order = _create_order(api_client, dueDate="2026-03-25", dueTime="14:00")
    assert "orderRef" in order
    assert "customerName" in order
    assert "totalPrice" in order
    assert "dueDate" in order
    assert "dueTime" in order
    assert "deliveryType" in order
    assert "deliveryAddress" in order
    assert "createdAt" in order
    assert "updatedAt" in order
    assert "amountPaid" in order
    assert "isPaid" in order


def test_create_order_generates_order_ref(api_client):
    order = _create_order(api_client)
    assert order["orderRef"].startswith("ORD-")


def test_create_order_id_is_string(api_client):
    order = _create_order(api_client)
    assert isinstance(order["id"], str)


def test_create_order_with_all_fields(api_client):
    resp = api_client.post("/api/orders", json={
        "customerName": "Lê Văn C",
        "customerPhone": "0901234567",
        "items": [{"productName": "Bánh kem 20cm", "quantity": 1, "unitPrice": 350000, "productId": "BKS-20"}],
        "dueDate": "2026-03-25",
        "dueTime": "10:00",
        "deliveryType": "delivery",
        "deliveryAddress": "123 Nguyễn Huệ, Q1",
        "notes": "Thêm nến sinh nhật",
    })
    assert resp.status_code == 201
    order = resp.json()
    assert order["customerPhone"] == "0901234567"
    assert order["dueDate"] == "2026-03-25"
    assert order["deliveryType"] == "delivery"
    assert order["notes"] == "Thêm nến sinh nhật"


def test_create_order_with_deposit(api_client):
    resp = api_client.post("/api/orders", json={
        "customerName": "Test deposit",
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 300000}],
        "deposit": {"amount": 100000, "method": "transfer"},
    })
    assert resp.status_code == 201
    order = resp.json()
    assert order["amountPaid"] == 100000
    assert len(order["paymentTransactions"]) == 1
    txn = order["paymentTransactions"][0]
    assert txn["amount"] == 100000
    assert txn["type"] == "deposit"
    assert txn["method"] == "transfer"


def test_create_order_includes_work_items_and_transactions(api_client):
    order = _create_order(api_client)
    assert "workItems" in order
    assert "paymentTransactions" in order
    assert isinstance(order["workItems"], list)
    assert isinstance(order["paymentTransactions"], list)


# --- Get order ---


def test_get_order_by_ref(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.get(f"/api/orders/{ref}")
    assert resp.status_code == 200
    assert resp.json()["orderRef"] == ref


def test_get_order_by_id(api_client):
    created = _create_order(api_client)
    order_id = created["id"]
    resp = api_client.get(f"/api/orders/{order_id}")
    assert resp.status_code == 200
    assert resp.json()["id"] == order_id


def test_get_order_not_found(api_client):
    resp = api_client.get("/api/orders/ORD-NOTEXIST")
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


def test_get_order_includes_work_items_and_transactions(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.get(f"/api/orders/{ref}")
    assert resp.status_code == 200
    detail = resp.json()
    assert "workItems" in detail
    assert "paymentTransactions" in detail


# --- Edit order ---


def test_edit_order_customer_name(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}", json={"customerName": "Tên mới"})
    assert resp.status_code == 200
    assert resp.json()["customerName"] == "Tên mới"


def test_edit_order_notes(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}", json={"notes": "Ghi chú mới"})
    assert resp.status_code == 200
    assert resp.json()["notes"] == "Ghi chú mới"


def test_edit_order_due_date(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}", json={"dueDate": "2026-04-01"})
    assert resp.status_code == 200
    assert resp.json()["dueDate"] == "2026-04-01"


def test_edit_order_items_recalculates_total(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    new_items = [{"productName": "Bánh mì", "quantity": 5, "unitPrice": 15000}]
    resp = api_client.patch(f"/api/orders/{ref}", json={"items": new_items})
    assert resp.status_code == 200
    assert resp.json()["totalPrice"] == 75000
    assert len(resp.json()["items"]) == 1


def test_edit_order_empty_body(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}", json={})
    assert resp.status_code == 400
    assert "Không có gì" in resp.json()["detail"]


def test_edit_order_not_found(api_client):
    resp = api_client.patch("/api/orders/ORD-NOTEXIST", json={"notes": "x"})
    assert resp.status_code == 404


# --- Status transition ---


def test_status_transition_new_to_confirmed(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/status", json={"status": "confirmed", "reason": "Khách xác nhận"}
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "confirmed"


def test_status_full_flow(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        resp = api_client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": "Tiến độ bình thường"},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == status
    # Pay full amount before completing
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "completed", "reason": "Tiến độ bình thường"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "completed"


def test_status_cancel(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "Khách hủy"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"


def test_status_forward_without_reason_ok(api_client):
    """Forward transitions (new -> confirmed) do not require a reason."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "confirmed"})
    assert resp.status_code == 200


def test_status_backward_requires_reason(api_client):
    """Backward transitions require a reason."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    # Move forward: new -> confirmed -> in_progress
    api_client.post(f"/api/orders/{ref}/status", json={"status": "confirmed"})
    api_client.post(f"/api/orders/{ref}/status", json={"status": "in_progress"})
    # Backward without reason: in_progress -> confirmed -> 422
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "confirmed", "reason": ""})
    assert resp.status_code == 422
    assert "Lý do" in resp.json()["detail"]
    # With reason -> ok
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "confirmed", "reason": "Cần xem lại"},
    )
    assert resp.status_code == 200


def test_status_bad_value(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "invalid_status", "reason": "test"},
    )
    assert resp.status_code == 422


def test_status_transition_not_found(api_client):
    resp = api_client.post(
        "/api/orders/ORD-NOTEXIST/status",
        json={"status": "confirmed", "reason": "test"},
    )
    assert resp.status_code == 404


# --- Backward status transitions ---


def test_status_backward_transition_allowed_with_reason(api_client):
    """Non-standard (backward) transitions are allowed when a reason is provided."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    # Forward to completed first
    for status in ["confirmed", "in_progress", "ready", "delivered", "completed"]:
        api_client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": "Tiến độ"},
        )
    # Backward: completed → in_progress
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "in_progress", "reason": "Cần chỉnh sửa thêm"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "in_progress"


def test_status_backward_from_cancelled_allowed_with_reason(api_client):
    """Can reopen a cancelled order with a reason."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "Khách hủy"},
    )
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "confirmed", "reason": "Khách đặt lại"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "confirmed"


def test_status_backward_requires_reason(api_client):
    """Backward transitions without a reason are rejected."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "confirmed", "reason": "OK"},
    )
    # Try backward without reason
    resp = api_client.post(
        f"/api/orders/{ref}/status", json={"status": "new", "reason": ""}
    )
    assert resp.status_code == 422


# --- Payment ---


def test_update_payment(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": 200000})
    assert resp.status_code == 200
    assert resp.json()["amountPaid"] == 200000


def test_update_payment_full_marks_is_paid(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    resp = api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})
    assert resp.status_code == 200
    assert resp.json()["isPaid"] is True


def test_update_payment_partial_not_paid(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    resp = api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total / 2})
    assert resp.status_code == 200
    assert resp.json()["isPaid"] is False


def test_update_payment_zero(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": 0})
    assert resp.status_code == 200
    assert resp.json()["amountPaid"] == 0
    assert resp.json()["isPaid"] is False


def test_update_payment_negative_rejected(api_client):
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": -1000})
    assert resp.status_code == 422
    assert "âm" in resp.json()["detail"]


def test_update_payment_not_found(api_client):
    resp = api_client.patch("/api/orders/ORD-NOTEXIST/payment", json={"amountPaid": 100})
    assert resp.status_code == 404


# --- Order item productId ---


def test_create_order_item_preserves_product_id(api_client):
    items = [{"productName": "Bánh kem 16cm", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}]
    resp = api_client.post("/api/orders", json={"customerName": "Test", "items": items})
    assert resp.status_code == 201
    assert resp.json()["items"][0]["productId"] == "BKS-16"


def test_create_order_with_created_by(api_client):
    resp = api_client.post("/api/orders", json={
        "customerName": "Test Created By",
        "createdBy": "Ngân",
    })
    assert resp.status_code == 201
    order = resp.json()
    assert order["createdBy"] == "Ngân"


def test_create_order_created_by_defaults_empty(api_client):
    resp = api_client.post("/api/orders", json={"customerName": "Test Default"})
    assert resp.status_code == 201
    order = resp.json()
    assert order["createdBy"] == ""


# --- Payment block on completion ---


def test_complete_blocked_when_underpaid(api_client):
    """Completing an underpaid order returns 422."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    # Advance to delivered (one step before completed)
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    # Attempt to complete without full payment
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})
    assert resp.status_code == 422
    assert "Chưa thanh toán đủ" in resp.json()["detail"]


def test_complete_succeeds_when_fully_paid(api_client):
    """Completing a fully paid order succeeds."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "completed"


def test_complete_succeeds_when_overpaid(api_client):
    """Completing an overpaid order is allowed."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    # Pay more than total
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total + 50000})
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "completed"


def test_complete_free_order_no_payment_needed(api_client):
    """An order with 0 total price can complete without payment."""
    created = _create_order(api_client, items=[{"productName": "Miễn phí", "quantity": 1, "unitPrice": 0}])
    ref = created["orderRef"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "completed"


def test_complete_blocked_with_partial_payment(api_client):
    """Completing with partial payment returns 422."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    # Pay half
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total / 2})
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})
    assert resp.status_code == 422
    assert "còn thiếu" in resp.json()["detail"]


# --- Bidirectional sync scenarios (DG-022) ---
# These tests verify the backend supports all transitions that client-side
# auto-sync will attempt. Sync is client-side Flutter logic; these ensure
# the API allows the required transitions.


def test_sync_order_backward_ready_to_in_progress(api_client):
    """Backend supports order backward: ready → in_progress (with reason)."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    for status in ["confirmed", "in_progress", "ready"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "in_progress", "reason": "Tự động đồng bộ theo trạng thái sản phẩm"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "in_progress"


def test_sync_order_non_adjacent_forward(api_client):
    """Backend supports non-adjacent forward: new → in_progress."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "in_progress"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "in_progress"


def test_sync_work_item_backward_ready_to_working(api_client):
    """Backend supports WI backward: ready → working (with reason)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    # Order has items from creation — get the work item
    wi_resp = api_client.get(f"/api/orders/{ref}/items")
    items = wi_resp.json()
    assert len(items) >= 1
    item_id = items[0]["id"]
    # Forward: pending → working → ready
    api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": "working"})
    api_client.post(f"/api/orders/{ref}/items/{item_id}/status", json={"status": "ready"})
    # Backward: ready → working
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "working", "reason": "Tự động đồng bộ theo trạng thái đơn hàng"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "working"


def test_sync_work_item_non_adjacent_forward(api_client):
    """Backend supports WI non-adjacent forward: pending → ready."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    wi_resp = api_client.get(f"/api/orders/{ref}/items")
    items = wi_resp.json()
    assert len(items) >= 1
    item_id = items[0]["id"]
    # Non-adjacent: pending → ready (forward, no reason needed)
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/status",
        json={"status": "ready", "reason": ""},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_sync_order_backward_auto_reason_required(api_client):
    """Auto-sync backward transition requires a non-empty reason."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    for status in ["confirmed", "in_progress", "ready"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    # Backward without reason → rejected
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "in_progress", "reason": ""},
    )
    assert resp.status_code == 422


# --- Auto-sync: order status → extras/gifts (DG-050 Phase 1) ---


def test_autosync_order_status_changes_extra_to_ready(api_client):
    """AC2: Given an order whose status changes to 'ready', when extras exist,
    then each non-cancelled extra auto-transitions to 'ready'."""
    resp = api_client.post("/api/orders", json={
        "customerName": "Khách test",
        "items": [
            {"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "isExtra": False},
            {"productName": "Nến", "quantity": 1, "unitPrice": 10000, "isExtra": True},
        ],
    })
    assert resp.status_code == 201
    order = resp.json()
    ref = order["orderRef"]
    candle = next(i for i in order["workItems"] if i["productName"] == "Nến")

    # Transition order: new → confirmed → in_progress → ready
    for status in ["confirmed", "in_progress", "ready"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})

    # Extra should now be at ready
    candle_state = api_client.get(f"/api/orders/{ref}/items").json()
    candle_item = next(i for i in candle_state if i["productName"] == "Nến")
    assert candle_item["status"] == "ready"


def test_autosync_extras_follow_order_when_order_transitions(api_client):
    """When order status transitions, extras follow to matching work item status."""
    resp = api_client.post("/api/orders", json={
        "customerName": "Khách theo dõi",
        "items": [
            {"productName": "Bánh chính", "quantity": 1, "unitPrice": 200000},
            {"productName": "Đĩa", "quantity": 1, "unitPrice": 5000, "isExtra": True},
        ],
    })
    order = resp.json()
    ref = order["orderRef"]

    # Transition order to in_progress
    api_client.post(f"/api/orders/{ref}/status", json={"status": "confirmed"})
    api_client.post(f"/api/orders/{ref}/status", json={"status": "in_progress"})

    plate = api_client.get(f"/api/orders/{ref}/items").json()
    plate_item = next(i for i in plate if i["productName"] == "Đĩa")
    assert plate_item["status"] == "working"


def test_autosync_extras_not_affected_when_order_goes_to_cancelled(api_client):
    """Extras already cancelled are not re-transitioned when order goes to cancelled."""
    resp = api_client.post("/api/orders", json={
        "customerName": "Khách hủy extras",
        "items": [
            {"productName": "Bánh", "quantity": 1, "unitPrice": 200000},
            {"productName": "Nến", "quantity": 1, "unitPrice": 10000, "isExtra": True},
        ],
    })
    order = resp.json()
    ref = order["orderRef"]
    candle = next(i for i in order["workItems"] if i["productName"] == "Nến")

    # Cancel the extra first
    api_client.post(f"/api/orders/{ref}/items/{candle['id']}/status", json={"status": "cancelled", "reason": ""})

    # Transition order to confirmed → in_progress → ready → cancelled
    for status in ["confirmed", "in_progress", "ready"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    api_client.post(f"/api/orders/{ref}/status", json={"status": "cancelled", "reason": "Khách hủy"})

    # Candle should still be cancelled (not re-transitioned)
    candle_state = api_client.get(f"/api/orders/{ref}/items").json()
    candle_item = next(i for i in candle_state if i["productName"] == "Nến")
    assert candle_item["status"] == "cancelled"


def test_autosync_extras_skip_already_matching(api_client):
    """Extras that are already at target status are not updated unnecessarily."""
    resp = api_client.post("/api/orders", json={
        "customerName": "Khách skip",
        "items": [
            {"productName": "Bánh", "quantity": 1, "unitPrice": 200000},
            {"productName": "Nến", "quantity": 1, "unitPrice": 10000, "isExtra": True},
        ],
    })
    order = resp.json()
    ref = order["orderRef"]
    candle = next(i for i in order["workItems"] if i["productName"] == "Nến")

    # Set candle to ready manually first (simulate it was already done)
    api_client.post(f"/api/orders/{ref}/items/{candle['id']}/status", json={"status": "working", "reason": ""})
    api_client.post(f"/api/orders/{ref}/items/{candle['id']}/status", json={"status": "ready", "reason": ""})

    # Now transition order to ready — candle should stay at ready
    for status in ["confirmed", "in_progress", "ready"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})

    candle_state = api_client.get(f"/api/orders/{ref}/items").json()
    candle_item = next(i for i in candle_state if i["productName"] == "Nến")
    assert candle_item["status"] == "ready"


# --- PATCH payment-method ---


def test_update_payment_method_cash_to_transfer(api_client):
    """Valid update: cash → transfer."""
    order = _create_order(api_client, paymentMethod="cash", status="delivered")
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment-method", json={"method": "transfer"})
    assert resp.status_code == 200


def test_update_payment_method_transfer_to_cash(api_client):
    """Valid update: transfer → cash."""
    order = _create_order(api_client, paymentMethod="transfer", status="delivered")
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment-method", json={"method": "cash"})
    assert resp.status_code == 200


def test_update_payment_method_invalid_method(api_client):
    """Invalid method value returns 422."""
    order = _create_order(api_client, paymentMethod="cash", status="delivered")
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment-method", json={"method": "bitcoin"})
    assert resp.status_code == 422


def test_update_payment_method_nonexistent_order(api_client):
    """Non-existent order returns 404."""
    resp = api_client.patch("/api/orders/FAKE-999/payment-method", json={"method": "cash"})
    assert resp.status_code == 404


def test_update_payment_method_no_transaction(api_client):
    """Order without payment transaction returns 404."""
    order = _create_order(api_client)  # no paymentMethod → no txn
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}/payment-method", json={"method": "cash"})
    assert resp.status_code == 404


# --- Fresh payment status in list orders (DG-089) ---


def test_list_orders_returns_fresh_is_paid_after_full_payment(api_client):
    """list_orders returns isPaid=True and correct amountPaid after full payment."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]

    # Patch full payment
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})

    # GET /api/orders must reflect fresh payment data
    resp = api_client.get("/api/orders")
    assert resp.status_code == 200
    orders = resp.json()
    found = next((o for o in orders if o["orderRef"] == ref), None)
    assert found is not None, f"Order {ref} not found in list"
    assert found["isPaid"] is True
    assert found["amountPaid"] == total


def test_list_orders_returns_partial_is_paid_false(api_client):
    """list_orders returns isPaid=False for partially-paid orders."""
    created = _create_order(api_client)
    ref = created["orderRef"]
    total = created["totalPrice"]
    partial = total / 2

    # Patch partial payment
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": partial})

    # GET /api/orders must show isPaid=False and correct amountPaid
    resp = api_client.get("/api/orders")
    assert resp.status_code == 200
    orders = resp.json()
    found = next((o for o in orders if o["orderRef"] == ref), None)
    assert found is not None, f"Order {ref} not found in list"
    assert found["isPaid"] is False
    assert found["amountPaid"] == partial


def test_pos_order_with_chip_persists_price_chip_and_fifo_consumes(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "POS-Nhỏ", 12000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_order(
        api_client,
        items=[
            {
                "productId": "1",
                "productName": "Bánh kem",
                "quantity": 1,
                "unitPrice": 12000,
                "priceChipId": chip_id,
            }
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    assert order["status"] == "delivered"

    with get_db() as conn:
        saved_item = conn.execute(
            "SELECT price_chip_id FROM order_items WHERE order_id = ? ORDER BY id ASC LIMIT 1",
            (int(order["id"]),),
        ).fetchone()
        assert saved_item["price_chip_id"] == chip_id

        movement = conn.execute(
            """SELECT id, lot_id, price_chip_id
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (order["orderRef"],),
        ).fetchone()
        assert movement["price_chip_id"] == chip_id
        assert movement["lot_id"] is not None

        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement["id"],),
        ).fetchone()
        assert consumed["c"] == 1


def test_pos_order_without_chip_uses_base_option_and_still_works(api_client):
    _ensure_trung_bay(1)
    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2},
    )
    assert restock.status_code == 200

    order = _create_order(
        api_client,
        items=[
            {
                "productId": "1",
                "productName": "Bánh kem",
                "quantity": 1,
                "unitPrice": 10000,
            }
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )

    with get_db() as conn:
        saved_item = conn.execute(
            "SELECT price_chip_id FROM order_items WHERE order_id = ? ORDER BY id ASC LIMIT 1",
            (int(order["id"]),),
        ).fetchone()
        assert saved_item["price_chip_id"] is None

        movement = conn.execute(
            "SELECT id, price_chip_id FROM stock_movements WHERE movement_type = 'sale' AND reference_id = ? ORDER BY id DESC LIMIT 1",
            (order["orderRef"],),
        ).fetchone()
        assert movement["price_chip_id"] is None
