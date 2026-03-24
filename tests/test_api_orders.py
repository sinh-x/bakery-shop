"""Tests for Baker API — orders endpoints."""

import pytest


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A", items=None, **kwargs):
    if items is None:
        items = [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}]
    payload = {"customerName": customer, "items": items, **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


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
    for status in ["confirmed", "in_progress", "ready", "delivered", "completed"]:
        resp = api_client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": "Tiến độ bình thường"},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == status


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
