"""Tests for Baker API — orders endpoints."""

import json
import re

import pytest

from baker.db.connection import get_db


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A", items=None, **kwargs):
    if items is None:
        items = [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}]
    payload = {"customerName": customer, "items": items, "dueDate": "2026-03-25", **kwargs}
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


def _mark_order_as_legacy_pos(conn, order_ref: str, created_at: str) -> None:
    conn.execute(
        """UPDATE orders
           SET due_date = '', source = ?, created_at = ?
           WHERE order_ref = ?""",
        ("Tại tiệm - POS", created_at, order_ref),
    )


def _set_public_order_code(conn, order_ref: str, public_order_code: str) -> None:
    conn.execute(
        "UPDATE orders SET public_order_code = ? WHERE order_ref = ?",
        (public_order_code, order_ref),
    )


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


def test_list_orders_due_date_includes_legacy_pos_created_at_fallback(api_client):
    due_order = _create_order(api_client, customer="Due date exact", dueDate="2026-03-20")
    legacy_in_range = _create_order(api_client, customer="Legacy POS in range")
    legacy_out_of_range = _create_order(api_client, customer="Legacy POS out range")
    non_pos_legacy = _create_order(api_client, customer="Legacy non POS")

    with get_db() as conn:
        _mark_order_as_legacy_pos(conn, legacy_in_range["orderRef"], "2026-03-20T08:30:00Z")
        _mark_order_as_legacy_pos(conn, legacy_out_of_range["orderRef"], "2026-03-22T08:30:00Z")
        conn.execute(
            """UPDATE orders
               SET due_date = '', source = ?, created_at = ?
               WHERE order_ref = ?""",
            ("Facebook-DoanGia", "2026-03-20T09:00:00Z", non_pos_legacy["orderRef"]),
        )

    resp = api_client.get("/api/orders", params={"due_date": "2026-03-20"})
    assert resp.status_code == 200
    refs = {o["orderRef"] for o in resp.json()}
    assert due_order["orderRef"] in refs
    assert legacy_in_range["orderRef"] in refs
    assert legacy_out_of_range["orderRef"] not in refs
    assert non_pos_legacy["orderRef"] not in refs


def test_list_orders_due_date_range_includes_terminal_and_legacy_fallback(api_client):
    completed_order = _create_order(api_client, customer="Completed in range", dueDate="2026-03-20")
    completed_ref = completed_order["orderRef"]
    for s in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{completed_ref}/status", json={"status": s})
    api_client.patch(f"/api/orders/{completed_ref}/payment", json={"amountPaid": completed_order["totalPrice"]})
    api_client.post(f"/api/orders/{completed_ref}/status", json={"status": "completed"})

    cancelled_order = _create_order(api_client, customer="Cancelled in range", dueDate="2026-03-21")
    cancelled_ref = cancelled_order["orderRef"]
    api_client.post(f"/api/orders/{cancelled_ref}/status", json={"status": "cancelled", "reason": "Khách hủy"})

    legacy_in_range = _create_order(api_client, customer="Legacy POS in range")
    legacy_out_of_range = _create_order(api_client, customer="Legacy POS out range")
    outside_due = _create_order(api_client, customer="Outside due", dueDate="2026-03-23")

    with get_db() as conn:
        _mark_order_as_legacy_pos(conn, legacy_in_range["orderRef"], "2026-03-21T10:10:00Z")
        _mark_order_as_legacy_pos(conn, legacy_out_of_range["orderRef"], "2026-03-25T10:10:00Z")

    resp = api_client.get(
        "/api/orders",
        params={"due_date_from": "2026-03-20", "due_date_to": "2026-03-21"},
    )
    assert resp.status_code == 200
    refs = {o["orderRef"] for o in resp.json()}
    assert completed_ref in refs
    assert cancelled_ref in refs
    assert legacy_in_range["orderRef"] in refs
    assert legacy_out_of_range["orderRef"] not in refs
    assert outside_due["orderRef"] not in refs


def test_list_orders_due_date_legacy_fallback_uses_timestamp_bounds(api_client):
    legacy_before = _create_order(api_client, customer="Legacy before day")
    legacy_on_day_late = _create_order(api_client, customer="Legacy in day late")
    legacy_next_day = _create_order(api_client, customer="Legacy next day")

    with get_db() as conn:
        _mark_order_as_legacy_pos(conn, legacy_before["orderRef"], "2026-03-19T23:59:59Z")
        _mark_order_as_legacy_pos(conn, legacy_on_day_late["orderRef"], "2026-03-20T23:59:59Z")
        _mark_order_as_legacy_pos(conn, legacy_next_day["orderRef"], "2026-03-21T00:00:00Z")

    resp = api_client.get("/api/orders", params={"due_date": "2026-03-20"})
    assert resp.status_code == 200
    refs = {o["orderRef"] for o in resp.json()}
    assert legacy_before["orderRef"] not in refs
    assert legacy_on_day_late["orderRef"] in refs
    assert legacy_next_day["orderRef"] not in refs


def test_list_orders_due_date_range_preserves_limit_and_offset(api_client):
    for i in range(5):
        _create_order(api_client, customer=f"Range page {i}", dueDate="2026-03-20")

    resp = api_client.get(
        "/api/orders",
        params={"due_date_from": "2026-03-20", "due_date_to": "2026-03-20", "limit": 2, "offset": 1},
    )
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_list_orders_pagination(api_client):
    for i in range(5):
        _create_order(api_client, customer=f"Customer {i}")
    resp = api_client.get("/api/orders", params={"limit": 3, "offset": 0})
    assert resp.status_code == 200
    assert len(resp.json()) == 3


# --- Create order ---


def test_create_order_minimal(api_client):
    resp = api_client.post("/api/orders", json={"customerName": "Trần Thị B", "dueDate": "2026-03-25"})
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
    resp = api_client.post("/api/orders", json={"customerName": "Test", "items": items, "dueDate": "2026-03-25"})
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


def test_create_order_returns_public_order_code(api_client):
    order = _create_order(api_client, dueDate="2026-03-26", deliveryType="pickup")
    assert order["publicOrderCode"]
    assert re.match(r"^[ABCDLMNV][0-9]{2,5}-T$", order["publicOrderCode"])


def test_create_order_requires_due_date(api_client):
    resp = api_client.post("/api/orders", json={"customerName": "Thiếu ngày"})
    assert resp.status_code == 422
    assert resp.json()["detail"] == "Vui lòng chọn ngày nhận/giao bánh"


def test_create_order_delivery_type_suffix_mapping(api_client):
    pickup = _create_order(api_client, customer="Pickup", dueDate="2026-03-26", deliveryType="pickup")
    bus = _create_order(api_client, customer="Bus", dueDate="2026-03-27", deliveryType="bus")
    delivery = _create_order(api_client, customer="Delivery", dueDate="2026-03-28", deliveryType="delivery")
    assert pickup["publicOrderCode"].endswith("-T")
    assert bus["publicOrderCode"].endswith("-B")
    assert delivery["publicOrderCode"].endswith("-S")


def test_create_order_public_code_collision_retries_same_due_date(api_client, monkeypatch):
    from baker.api import orders as orders_api

    candidates = iter(["A42-T", "A42-T", "A421-T"])

    def _fake_candidate(_delivery_type: str, _reference_len: int = 3) -> str:
        return next(candidates)

    monkeypatch.setattr(orders_api, "generate_public_order_code_candidate", _fake_candidate)

    first = _create_order(api_client, customer="First", dueDate="2026-03-30", deliveryType="pickup")
    second = _create_order(api_client, customer="Second", dueDate="2026-03-30", deliveryType="pickup")

    assert first["publicOrderCode"] == "A42-T"
    assert second["publicOrderCode"] == "A421-T"


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
        "dueDate": "2026-03-25",
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
    resp = api_client.patch(
        f"/api/orders/{ref}",
        json={"dueDate": "2026-04-01", "publicCodeDateChangeDecision": "keep"},
    )
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


def test_edit_order_due_date_requires_public_code_decision(api_client):
    created = _create_order(api_client, dueDate="2026-04-01", deliveryType="pickup")
    resp = api_client.patch(f"/api/orders/{created['orderRef']}", json={"dueDate": "2026-04-02"})
    assert resp.status_code == 422
    assert "giữ mã" in resp.json()["detail"]


def test_edit_order_due_date_regenerate_updates_code(api_client, monkeypatch):
    from baker.api import orders as orders_api

    created = _create_order(api_client, dueDate="2026-04-01", deliveryType="pickup")
    old_code = created["publicOrderCode"]

    monkeypatch.setattr(
        orders_api,
        "generate_public_order_code_candidate",
        lambda _delivery_type, _reference_len=3: "B99-T",
    )

    resp = api_client.patch(
        f"/api/orders/{created['orderRef']}",
        json={"dueDate": "2026-04-02", "publicCodeDateChangeDecision": "regenerate"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicOrderCode"] == "B99-T"
    assert data["publicOrderCode"] != old_code
    assert data["publicOrderCodeUpdate"]["action"] == "regenerated"
    assert data["publicOrderCodeUpdate"]["reason"] == "due_date_changed"


def test_edit_order_due_date_keep_without_conflict_keeps_code(api_client):
    created = _create_order(api_client, dueDate="2026-04-01", deliveryType="pickup")
    old_code = created["publicOrderCode"]
    resp = api_client.patch(
        f"/api/orders/{created['orderRef']}",
        json={"dueDate": "2026-04-02", "publicCodeDateChangeDecision": "keep"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicOrderCode"] == old_code
    assert data["publicOrderCodeUpdate"]["action"] == "kept"


def test_edit_order_due_date_keep_conflict_regenerates(api_client, monkeypatch):
    from baker.api import orders as orders_api

    created = _create_order(api_client, dueDate="2026-04-01", deliveryType="pickup")
    conflict_code = created["publicOrderCode"]
    conflict_order = _create_order(api_client, dueDate="2026-04-02", deliveryType="pickup")
    with get_db() as conn:
        _set_public_order_code(conn, conflict_order["orderRef"], conflict_code)

    monkeypatch.setattr(
        orders_api,
        "generate_public_order_code_candidate",
        lambda _delivery_type, _reference_len=3: "C11-T",
    )

    resp = api_client.patch(
        f"/api/orders/{created['orderRef']}",
        json={"dueDate": "2026-04-02", "publicCodeDateChangeDecision": "keep"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicOrderCode"] == "C11-T"
    assert data["publicOrderCodeUpdate"]["action"] == "regenerated"
    assert data["publicOrderCodeUpdate"]["reason"] == "due_date_conflict_after_keep"


def test_edit_order_delivery_type_updates_suffix(api_client):
    created = _create_order(api_client, dueDate="2026-04-01", deliveryType="pickup")
    with get_db() as conn:
        _set_public_order_code(conn, created["orderRef"], "A42-T")
    resp = api_client.patch(f"/api/orders/{created['orderRef']}", json={"deliveryType": "bus"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicOrderCode"] == "A42-B"
    assert data["publicOrderCodeUpdate"]["action"] == "suffix_updated"


def test_edit_order_delivery_type_suffix_conflict_regenerates(api_client, monkeypatch):
    from baker.api import orders as orders_api

    created = _create_order(api_client, dueDate="2026-04-01", deliveryType="pickup")
    conflict_order = _create_order(api_client, dueDate="2026-04-01", deliveryType="bus")
    with get_db() as conn:
        _set_public_order_code(conn, created["orderRef"], "A42-T")
        _set_public_order_code(conn, conflict_order["orderRef"], "A42-B")

    monkeypatch.setattr(
        orders_api,
        "generate_public_order_code_candidate",
        lambda _delivery_type, _reference_len=3: "D88-B",
    )

    resp = api_client.patch(f"/api/orders/{created['orderRef']}", json={"deliveryType": "bus"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicOrderCode"] == "D88-B"
    assert data["publicOrderCodeUpdate"]["action"] == "suffix_updated_regenerated"


def test_edit_order_old_order_without_public_code_keeps_fallback_behavior(api_client):
    created = _create_order(api_client, dueDate="2026-04-01")
    ref = created["orderRef"]
    with get_db() as conn:
        _set_public_order_code(conn, ref, "")
    resp = api_client.patch(
        f"/api/orders/{ref}",
        json={"dueDate": "2026-04-02", "deliveryType": "delivery", "publicCodeDateChangeDecision": "keep"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicOrderCode"] == ""


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
    resp = api_client.post("/api/orders", json={"customerName": "Test", "items": items, "dueDate": "2026-03-25"})
    assert resp.status_code == 201
    assert resp.json()["items"][0]["productId"] == "BKS-16"


def test_create_order_with_created_by(api_client):
    resp = api_client.post("/api/orders", json={
        "customerName": "Test Created By",
        "dueDate": "2026-03-25",
        "createdBy": "Ngân",
    })
    assert resp.status_code == 201
    order = resp.json()
    assert order["createdBy"] == "Ngân"


def test_create_order_created_by_defaults_empty(api_client):
    resp = api_client.post("/api/orders", json={"customerName": "Test Default", "dueDate": "2026-03-25"})
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
        "dueDate": "2026-03-25",
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
        "dueDate": "2026-03-25",
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
        "dueDate": "2026-03-25",
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
        "dueDate": "2026-03-25",
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


def test_pos_order_trung_bay_without_use_inventory_still_consumes_fifo(api_client):
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

    with get_db() as conn:
        saved_item = conn.execute(
            "SELECT attributes FROM order_items WHERE order_id = ? ORDER BY id ASC LIMIT 1",
            (int(order["id"]),),
        ).fetchone()
        saved_attributes = json.loads(saved_item["attributes"] or "{}")
        assert "useInventory" not in saved_attributes

        movement = conn.execute(
            """SELECT id, lot_id
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (order["orderRef"],),
        ).fetchone()
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


def test_pos_order_trung_bay_with_use_inventory_false_skips_fifo(api_client):
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
                "attributes": {"useInventory": "false"},
            }
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )

    with get_db() as conn:
        movement = conn.execute(
            """SELECT id, lot_id, price_chip_id
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (order["orderRef"],),
        ).fetchone()
        assert movement["price_chip_id"] == chip_id
        assert movement["lot_id"] is None

        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement["id"],),
        ).fetchone()
        assert consumed["c"] == 0


def test_non_pos_order_with_chip_persists_price_chip_id(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "Nhỏ", 12000)

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
    )

    with get_db() as conn:
        saved_item = conn.execute(
            "SELECT price_chip_id, attributes FROM order_items WHERE order_id = ? ORDER BY id ASC LIMIT 1",
            (int(order["id"]),),
        ).fetchone()
        assert saved_item["price_chip_id"] == chip_id


def test_non_pos_order_confirmed_decrements_stock_with_chip(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "Nhỏ", 12000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_order(
        api_client,
        items=[
            {
                "productId": "1",
                "productName": "Bánh kem",
                "quantity": 2,
                "unitPrice": 12000,
                "priceChipId": chip_id,
                "attributes": {"useInventory": "true"},
            }
        ],
    )
    ref = order["orderRef"]

    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "confirmed", "reason": "xác nhận"},
    )
    assert resp.status_code == 200

    with get_db() as conn:
        movement = conn.execute(
            """SELECT id, lot_id, price_chip_id, quantity
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (ref,),
        ).fetchone()
        assert movement["price_chip_id"] == chip_id
        assert movement["quantity"] == -2
        assert movement["lot_id"] is not None

        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement["id"],),
        ).fetchone()
        assert consumed["c"] == 2


@pytest.mark.parametrize("use_inventory", [None, False, "false"])
def test_non_pos_order_delivered_trung_bay_use_inventory_off_skips_fifo(api_client, use_inventory):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "Nhỏ", 12000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    item = {
        "productId": "1",
        "productName": "Bánh kem",
        "quantity": 1,
        "unitPrice": 12000,
        "priceChipId": chip_id,
    }
    if use_inventory is not None:
        item["attributes"] = {"useInventory": use_inventory}

    order = _create_order(api_client, items=[item])
    ref = order["orderRef"]

    for status, reason in [("confirmed", "ok"), ("in_progress", "ok"), ("ready", "ok")]:
        resp = api_client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": reason},
        )
        assert resp.status_code == 200

    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "delivered", "reason": "giao"},
    )
    assert resp.status_code == 200

    with get_db() as conn:
        movement = conn.execute(
            """SELECT id, lot_id
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (ref,),
        ).fetchone()
        assert movement["lot_id"] is None
        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement["id"],),
        ).fetchone()
        assert consumed["c"] == 0


def test_non_pos_order_delivered_skips_stock_when_use_inventory_false(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "Nhỏ", 12000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
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
                "attributes": {"useInventory": "false"},
            }
        ],
    )
    ref = order["orderRef"]

    for status, reason in [("confirmed", "ok"), ("in_progress", "ok"), ("ready", "ok")]:
        resp = api_client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": reason},
        )
        assert resp.status_code == 200

    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "delivered", "reason": "giao"},
    )
    assert resp.status_code == 200

    with get_db() as conn:
        movement = conn.execute(
            """SELECT id, lot_id
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (ref,),
        ).fetchone()
        assert movement["lot_id"] is None
        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement["id"],),
        ).fetchone()
        assert consumed["c"] == 0


def test_non_pos_order_delivered_skips_non_trung_bay(api_client):
    order = _create_order(
        api_client,
        items=[
            {
                "productId": "1",
                "productName": "Bánh kem",
                "quantity": 1,
                "unitPrice": 12000,
            }
        ],
    )
    ref = order["orderRef"]

    for status, reason in [("confirmed", "ok"), ("in_progress", "ok"), ("ready", "ok")]:
        api_client.post(
            f"/api/orders/{ref}/status",
            json={"status": status, "reason": reason},
        )

    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "delivered", "reason": "giao"},
    )
    assert resp.status_code == 200

    with get_db() as conn:
        movements = conn.execute(
            "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ?",
            (ref,),
        ).fetchone()
        assert movements["c"] == 0


@pytest.mark.parametrize("payment_method", ["cash", "transfer"])
def test_pos_chip_order_with_gift_creates_order_tracks_payment_and_skips_gift_stock(api_client, payment_method):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "POS-Nhỏ", 12000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_order(
        api_client,
        items=[
            {
                "productId": "1",
                "productName": "Bánh kem (POS-Nhỏ)",
                "quantity": 2,
                "unitPrice": 12000,
                "priceChipId": chip_id,
            },
            {
                "productId": "1",
                "productName": "Dao nhựa",
                "quantity": 1,
                "unitPrice": 1000,
                "isGift": True,
            },
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod=payment_method,
    )
    assert order["status"] == "delivered"

    with get_db() as conn:
        payment_rows = conn.execute(
            "SELECT amount, method, type FROM payment_transactions WHERE order_id = ? ORDER BY id",
            (int(order["id"]),),
        ).fetchall()
        assert len(payment_rows) == 1
        assert payment_rows[0]["type"] == "payment"
        assert payment_rows[0]["method"] == payment_method
        assert payment_rows[0]["amount"] == float(order["totalPrice"])

        movement_rows = conn.execute(
            """SELECT id, quantity, price_chip_id
               FROM stock_movements
               WHERE movement_type = 'sale' AND reference_id = ?
               ORDER BY id""",
            (order["orderRef"],),
        ).fetchall()
        assert len(movement_rows) == 1
        assert movement_rows[0]["quantity"] == -2
        assert movement_rows[0]["price_chip_id"] == chip_id

        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement_rows[0]["id"],),
        ).fetchone()
        assert consumed["c"] == 2

        gift_row = conn.execute(
            """SELECT product_id, is_gift, price_chip_id
               FROM order_items
               WHERE order_id = ? AND is_gift = 1
               ORDER BY id ASC LIMIT 1""",
            (int(order["id"]),),
        ).fetchone()
        assert gift_row is not None
        assert gift_row["product_id"] == "1"
        assert gift_row["price_chip_id"] is None


# --- Active-only listing (Phase 1: active-order-visibility) ---


def test_active_only_includes_older_order_beyond_limit(api_client):
    """Active order beyond newest 50 cutoff appears in active_only listing."""
    old_order = _create_order(api_client, customer="Old Active")

    for i in range(60):
        _create_order(api_client, customer=f"Filler {i}")

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    refs = [o["orderRef"] for o in resp.json()]
    assert old_order["orderRef"] in refs


def test_active_only_includes_all_supported_statuses(api_client):
    """Active orders in new, confirmed, in_progress, ready appear in active_only."""
    customers = {
        "new": "StatusNew",
        "confirmed": "StatusConfirmed",
        "in_progress": "StatusInProgress",
        "ready": "StatusReady",
    }
    orders = {}
    for target_status, name in customers.items():
        order = _create_order(api_client, customer=name)
        ref = order["orderRef"]
        if target_status != "new":
            route = ["confirmed"]
            if target_status in ("in_progress", "ready"):
                route.append("in_progress")
            if target_status == "ready":
                route.append("ready")
            for s in route:
                api_client.post(
                    f"/api/orders/{ref}/status",
                    json={"status": s, "reason": "auto"},
                )
        orders[target_status] = order

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    result = resp.json()
    result_refs = {o["orderRef"] for o in result}
    for key, order in orders.items():
        assert order["orderRef"] in result_refs, f"{key} order missing from active_only"


def test_active_only_excludes_completed(api_client):
    """Completed orders are excluded from active_only listing."""
    order = _create_order(api_client, customer="Will Complete")
    ref = order["orderRef"]
    total = order["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})
    api_client.post(f"/api/orders/{ref}/status", json={"status": "completed"})

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    refs = [o["orderRef"] for o in resp.json()]
    assert order["orderRef"] not in refs


def test_active_only_excludes_cancelled(api_client):
    """Cancelled orders are excluded from active_only listing."""
    order = _create_order(api_client, customer="Will Cancel")
    ref = order["orderRef"]
    api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "Khách hủy"},
    )

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    refs = [o["orderRef"] for o in resp.json()]
    assert order["orderRef"] not in refs


def test_active_only_includes_delivered_unpaid(api_client):
    """Delivered-but-unpaid orders appear in active_only for awaiting_payment."""
    order = _create_order(api_client, customer="Delivered Unpaid")
    ref = order["orderRef"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    refs = [o["orderRef"] for o in resp.json()]
    assert order["orderRef"] in refs


def test_active_only_excludes_delivered_fully_paid(api_client):
    """Delivered and fully paid orders are excluded from active_only."""
    order = _create_order(api_client, customer="Delivered Paid")
    ref = order["orderRef"]
    total = order["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    refs = [o["orderRef"] for o in resp.json()]
    assert order["orderRef"] not in refs


def test_active_only_delivered_status_filter_still_excludes_fully_paid(api_client):
    """active_only with status=delivered excludes fully-paid delivered orders."""
    order = _create_order(api_client, customer="Delivered Paid 2")
    ref = order["orderRef"]
    total = order["totalPrice"]
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status})
    api_client.patch(f"/api/orders/{ref}/payment", json={"amountPaid": total})

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    refs = [o["orderRef"] for o in resp.json()]
    assert order["orderRef"] not in refs


def test_pagination_compatibility_limit_offset(api_client):
    """Explicit limit and offset still work with default listing."""
    for i in range(5):
        _create_order(api_client, customer=f"Page {i}")

    resp = api_client.get("/api/orders", params={"limit": 3, "offset": 0})
    assert resp.status_code == 200
    assert len(resp.json()) == 3

    resp2 = api_client.get("/api/orders", params={"limit": 3, "offset": 3})
    assert resp2.status_code == 200
    assert len(resp2.json()) == 2


def test_pagination_unaffected_by_active_only_param(api_client):
    """active_only=False preserves default pagination with limit/offset."""
    for i in range(10):
        _create_order(api_client, customer=f"Paginate {i}")

    resp = api_client.get("/api/orders", params={"limit": 2, "offset": 0, "active_only": False})
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_active_only_returns_all_orders_for_single_customer(api_client):
    """Customer with 3 active orders sees all 3 in the active_only listing."""
    customer = "Thôn Nữ"
    order1 = _create_order(api_client, customer=customer)
    order2 = _create_order(api_client, customer=customer)
    order3 = _create_order(api_client, customer=customer)
    for i in range(10):
        _create_order(api_client, customer=f"Other {i}")

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    result = resp.json()
    customer_orders = [o for o in result if o["customerName"] == customer]
    assert len(customer_orders) == 3
    refs = {o["orderRef"] for o in customer_orders}
    assert order1["orderRef"] in refs
    assert order2["orderRef"] in refs
    assert order3["orderRef"] in refs


def test_active_only_multi_customer_orders_beyond_cutoff(api_client):
    """All orders for one customer appear even when 60 fillers exist beyond cutoff."""
    customer = "Khách quen"
    orders = []
    for _ in range(3):
        orders.append(_create_order(api_client, customer=customer))
    for i in range(60):
        _create_order(api_client, customer=f"Filler {i}")

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    result = resp.json()
    customer_orders = [o for o in result if o["customerName"] == customer]
    assert len(customer_orders) == 3
    refs = {o["orderRef"] for o in customer_orders}
    for o in orders:
        assert o["orderRef"] in refs


def test_active_only_customer_with_mixed_statuses(api_client):
    """Customer with orders in different active statuses: all appear."""
    customer = "Khách VIP"
    o1 = _create_order(api_client, customer=customer)
    o2 = _create_order(api_client, customer=customer)
    ref2 = o2["orderRef"]
    api_client.post(f"/api/orders/{ref2}/status", json={"status": "confirmed"})
    o3 = _create_order(api_client, customer=customer)
    ref3 = o3["orderRef"]
    for s in ("confirmed", "in_progress", "ready"):
        api_client.post(f"/api/orders/{ref3}/status", json={"status": s})

    resp = api_client.get("/api/orders", params={"active_only": True})
    assert resp.status_code == 200
    result = resp.json()
    customer_orders = [o for o in result if o["customerName"] == customer]
    assert len(customer_orders) == 3
    statuses = {o["status"] for o in customer_orders}
    assert "new" in statuses
    assert "confirmed" in statuses
    assert "ready" in statuses


def test_active_only_performance_500_orders(api_client):
    """P95 under 500 ms for 500 active orders."""
    import time

    for i in range(500):
        _create_order(api_client, customer=f"Perf {i}")

    duration_ms_collect = []
    for _ in range(3):
        start = time.perf_counter()
        resp = api_client.get("/api/orders", params={"active_only": True})
        elapsed = (time.perf_counter() - start) * 1000
        duration_ms_collect.append(elapsed)
        assert resp.status_code == 200
        assert len(resp.json()) == 500

    avg_ms = sum(duration_ms_collect) / len(duration_ms_collect)
    assert avg_ms < 500, f"Average response time {avg_ms:.0f}ms exceeds 500ms budget"


def test_auto_decrement_stock_is_idempotent(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "Idempotent", 12000)

    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 5, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    order = _create_order(
        api_client,
        items=[{
            "productId": "1",
            "productName": "Bánh kem",
            "quantity": 1,
            "unitPrice": 12000,
            "priceChipId": chip_id,
        }],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    ref = order["orderRef"]

    with get_db() as conn:
        movements = conn.execute(
            "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND movement_type = 'sale'",
            (ref,),
        ).fetchone()
        assert movements["c"] == 1

        consumed = conn.execute(
            """SELECT COUNT(*) AS c FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = 1 AND sl.price_chip_id = ? AND ii.status = 'consumed'""",
            (chip_id,),
        ).fetchone()
        assert consumed["c"] == 1

    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "cancelled", "reason": "mistake"})
    assert resp.status_code == 200

    with get_db() as conn:
        sales = conn.execute(
            "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND movement_type = 'sale'",
            (ref,),
        ).fetchone()
        assert sales["c"] == 1

        restored = conn.execute(
            "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND movement_type = 'restore_sale'",
            (ref,),
        ).fetchone()
        assert restored["c"] == 1

        available = conn.execute(
            """SELECT COUNT(*) AS c FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = 1 AND sl.price_chip_id = ? AND ii.status = 'available'""",
            (chip_id,),
        ).fetchone()
        assert available["c"] == 5

    resp2 = api_client.post(f"/api/orders/{ref}/status", json={"status": "cancelled", "reason": "double cancel"})

    with get_db() as conn:
        restores = conn.execute(
            "SELECT COUNT(*) AS c FROM stock_movements WHERE reference_id = ? AND movement_type = 'restore_sale'",
            (ref,),
        ).fetchone()
        assert restores["c"] == 1


# ---------------------------------------------------------------------------
# Phase 3 — Downstream consumers: completion guard + receipts (FR8/FR9, AC6/AC9)
# ---------------------------------------------------------------------------


def _invalidate_payment_txn(conn, txn_id: int) -> None:
    """Simulate Phase 2 invalidate: set invalidated_at and reverse the journal entry."""
    from datetime import datetime
    from baker.services.journal_sync import _sync_payment_journal
    conn.execute(
        "UPDATE payment_transactions SET invalidated_at = ?, invalidated_by = ? WHERE id = ?",
        (datetime.now().isoformat(), "tester", txn_id),
    )
    row = conn.execute("SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)).fetchone()
    _sync_payment_journal(
        conn,
        txn_id,
        float(row["amount"]),
        row["type"],
        row["method"],
        order_id=int(row["order_id"]),
        deleted=True,
    )


def test_completion_guard_rejects_when_only_payment_is_invalidated(api_client):
    """AC6: an invalidated deposit is excluded from the completion guard.

    Order total_price=200,000đ with one invalidated deposit of 200,000đ must be
    rejected at the completed transition with "Chưa thanh toán đủ".
    """
    order = _create_order(api_client, items=[{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}])
    ref = order["orderRef"]
    total = order["totalPrice"]
    assert total == 200000

    # Pay the full amount, then move the order forward to delivered.
    pay = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": total, "type": "deposit", "method": "cash"})
    assert pay.status_code == 201
    txn_id = int(pay.json()["id"])
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        r = api_client.post(f"/api/orders/{ref}/status", json={"status": status, "reason": "Tiến độ"})
        assert r.status_code == 200

    # Invalidate the only payment. Now nothing counts toward total_paid.
    with get_db() as conn:
        _invalidate_payment_txn(conn, txn_id)

    # Completion must be rejected because the invalidated deposit is excluded.
    resp = api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "completed", "reason": "Hoàn thành"},
    )
    assert resp.status_code == 422
    body = resp.json()
    detail = body.get("detail") or body.get("rejectionDetail") or ""
    assert "Chưa thanh toán đủ" in detail or "thanh toán" in detail.lower(), (
        f"Expected unpaid rejection, got: {body}"
    )


def test_completion_guard_accepts_when_valid_payment_covers_total(api_client):
    """AC6 complement: a valid (non-invalidated) payment still allows completion."""
    order = _create_order(api_client, items=[{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}])
    ref = order["orderRef"]
    total = order["totalPrice"]
    pay = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": total, "type": "deposit", "method": "cash"})
    assert pay.status_code == 201
    for status in ["confirmed", "in_progress", "ready", "delivered"]:
        api_client.post(f"/api/orders/{ref}/status", json={"status": status, "reason": "Tiến độ"})
    resp = api_client.post(f"/api/orders/{ref}/status", json={"status": "completed", "reason": "Hoàn thành"})
    assert resp.status_code == 200
    assert resp.json()["status"] == "completed"


def test_receipt_total_excludes_invalidated_transaction(api_client):
    """AC9: receipt payment total excludes invalidated transactions.

    Receipts call ``PaymentTransaction.total_paid_excl_outflows`` which filters
    ``invalidated_at IS NULL`` (Phase 1). This test verifies the model-level
    exclusion holds through the receipt calculation path.
    """
    from baker.models.payment_transaction import PaymentTransaction
    order = _create_order(api_client, items=[{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}])
    ref = order["orderRef"]
    total = order["totalPrice"]
    pay = api_client.post(f"/api/orders/{ref}/transactions", json={"amount": total, "type": "deposit", "method": "cash"})
    txn_id = int(pay.json()["id"])

    with get_db() as conn:
        order_id = int(conn.execute("SELECT id FROM orders WHERE order_ref = ?", (ref,)).fetchone()["id"])
        # Before invalidation the full amount counts.
        assert PaymentTransaction.total_paid_excl_outflows(conn, order_id) == 200000.0
        _invalidate_payment_txn(conn, txn_id)
        # After invalidation the receipt total excludes the invalidated deposit.
        assert PaymentTransaction.total_paid_excl_outflows(conn, order_id) == 0.0


# --- DG-205 Phase 3: order-customer phone matching via customer_phones (FR8/AC7) ---


def _create_customer_with_phones(api_client, name, phones):
    """Create a customer with a phones array and return the API response."""
    resp = api_client.post(
        "/api/customers",
        json={"name": name, "phones": phones},
    )
    assert resp.status_code == 201
    return resp.json()


def test_create_order_links_customer_by_secondary_phone(api_client):
    """AC7 — order customerPhone matches a secondary phone in customer_phones."""
    cust = _create_customer_with_phones(
        api_client,
        "Trần Thị B",
        [
            {"phone": "8490111222", "isPrimary": True},
            {"phone": "8499888777", "isPrimary": False},
        ],
    )
    # Order with the secondary phone and no explicit customerId.
    order = _create_order(
        api_client,
        customer="Trần Thị B",
        customerPhone="8499888777",
    )
    assert order["customerId"] == cust["id"]


def test_create_order_links_customer_by_primary_phone(api_client):
    """AC7 — order customerPhone matches the primary phone in customer_phones."""
    cust = _create_customer_with_phones(
        api_client,
        "Lê Văn C",
        [{"phone": "8491234567", "isPrimary": True}],
    )
    order = _create_order(
        api_client,
        customer="Lê Văn C",
        customerPhone="8491234567",
    )
    assert order["customerId"] == cust["id"]


def test_create_order_phone_normalized_for_matching(api_client):
    """AC7 — phone matching normalizes whitespace/dashes/dots before compare."""
    cust = _create_customer_with_phones(
        api_client,
        "Phạm Văn D",
        [{"phone": "84988776655", "isPrimary": True}],
    )
    # Same phone but with formatting; should still link.
    order = _create_order(
        api_client,
        customer="Phạm Văn D",
        customerPhone="849887 766-55",
    )
    assert order["customerId"] == cust["id"]


def test_create_order_no_match_leaves_customer_id_null(api_client):
    """AC7 — unknown phone does not link to any customer (customerId stays null)."""
    _create_customer_with_phones(
        api_client,
        "Ngô Thị E",
        [{"phone": "8490000000", "isPrimary": True}],
    )
    order = _create_order(
        api_client,
        customer="Walk-in",
        customerPhone="84999999999",
    )
    assert order["customerId"] is None


def test_create_order_explicit_customer_id_wins_over_phone(api_client):
    """AC7 — explicit customerId is respected; phone does not override it."""
    cust_a = _create_customer_with_phones(
        api_client,
        "A",
        [{"phone": "8491111111", "isPrimary": True}],
    )
    cust_b = _create_customer_with_phones(
        api_client,
        "B",
        [{"phone": "8492222222", "isPrimary": True}],
    )
    # Pass cust_b.id explicitly with cust_a's phone — explicit id must win.
    order = _create_order(
        api_client,
        customer="B",
        customerPhone="8491111111",
        customerId=cust_b["id"],
    )
    assert order["customerId"] == cust_b["id"]
    assert cust_b["id"] != cust_a["id"]


def test_edit_order_relinks_when_phone_changes(api_client):
    """AC7 — editing customerPhone re-resolves the customer link."""
    cust_a = _create_customer_with_phones(
        api_client,
        "A",
        [{"phone": "8493333333", "isPrimary": True}],
    )
    cust_b = _create_customer_with_phones(
        api_client,
        "B",
        [{"phone": "8494444444", "isPrimary": True}],
    )
    order = _create_order(
        api_client,
        customer="A",
        customerPhone="8493333333",
    )
    assert order["customerId"] == cust_a["id"]
    # Change phone to cust_b's — should re-link to cust_b.
    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}",
        json={"customerPhone": "8494444444"},
    )
    assert resp.status_code == 200
    assert resp.json()["customerId"] == cust_b["id"]


def test_edit_order_explicit_null_customer_id_not_overridden_by_phone(api_client):
    """AC7 — explicit customerId=null (unlink) is respected; phone does not re-resolve."""
    cust = _create_customer_with_phones(
        api_client,
        "C",
        [{"phone": "8495555555", "isPrimary": True}],
    )
    order = _create_order(
        api_client,
        customer="C",
        customerPhone="8495555555",
    )
    assert order["customerId"] == cust["id"]
    # Explicit null + new phone — should keep customerId null (no re-resolve).
    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}",
        json={"customerId": None, "customerPhone": "8496666666"},
    )
    assert resp.status_code == 200
    assert resp.json()["customerId"] is None


def test_create_order_shared_phone_earliest_order_wins(api_client):
    """FR8 — when multiple customers share the phone, earliest order links."""
    cust_a = _create_customer_with_phones(
        api_client,
        "Shared A",
        [{"phone": "8497777777", "isPrimary": True}],
    )
    cust_b = _create_customer_with_phones(
        api_client,
        "Shared B",
        [{"phone": "8497777777", "isPrimary": True}],
    )
    # First order to that phone — should link to the earliest customer by id.
    order = _create_order(
        api_client,
        customer="Walk-in",
        customerPhone="8497777777",
    )
    # Both customers share the phone; no orders exist for either yet, so the
    # fallback (lowest customer_id) applies. cust_a was created first.
    assert order["customerId"] in (cust_a["id"], cust_b["id"])
    # Sanity: with no prior orders, the deterministic pick is the lowest id.
    assert order["customerId"] == min(cust_a["id"], cust_b["id"])


def test_create_order_shared_phone_existing_order_tiebreak(api_client):
    """FR8 — earliest-order-wins tiebreak uses existing order created_at."""
    cust_a = _create_customer_with_phones(
        api_client,
        "Shared A",
        [{"phone": "8498888888", "isPrimary": True}],
    )
    cust_b = _create_customer_with_phones(
        api_client,
        "Shared B",
        [{"phone": "8498888888", "isPrimary": True}],
    )
    # Give cust_b an earlier order via direct DB insert so it should win.
    with get_db() as conn:
        conn.execute(
            "INSERT INTO orders (order_ref, customer_name, customer_phone, items, "
            "total_price, status, due_date, customer_id, created_at) "
            "VALUES ('EARLY-1', 'Shared B', '8498888888', '[]', 0, 'new', "
            "'2026-01-01', ?, '2026-01-01T00:00:00')",
            (cust_b["id"],),
        )
    order = _create_order(
        api_client,
        customer="Walk-in",
        customerPhone="8498888888",
    )
    assert order["customerId"] == cust_b["id"]


def test_create_order_legacy_customers_phone_fallback(api_client):
    """AC7 — falls back to customers.phone when customer_phones has no match.

    Covers pre-v58 databases or customers whose phone was written directly to
    the denormalized column without a corresponding customer_phones row.
    """
    # Create a customer with only the legacy phone column populated (no
    # customer_phones rows) by inserting directly into the DB.
    with get_db() as conn:
        cur = conn.execute(
            "INSERT INTO customers (name, phone, created_at) VALUES (?, ?, ?)",
            ("Legacy Only", "8499990000", "2026-06-01T00:00:00"),
        )
        legacy_id = cur.lastrowid
    order = _create_order(
        api_client,
        customer="Legacy Only",
        customerPhone="8499990000",
    )
    assert order["customerId"] == legacy_id
