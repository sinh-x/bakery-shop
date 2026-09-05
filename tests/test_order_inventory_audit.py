"""Focused DG-429 Phase 1 tests for the inventory audit domain service."""

import sqlite3
from dataclasses import FrozenInstanceError

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.inventory_fifo import create_lot_with_items
from baker.services import order_stock
from baker.services.order_inventory_audit import (
    AuditAction,
    AuditActor,
    AuditEntryDraft,
    AuditOutcome,
    AuditReason,
    AuditTrigger,
    InventorySnapshot,
    ItemSnapshot,
    append_entries,
    append_entry,
    count_order_entries,
    create_operation_context,
    execute_inventory_audit_savepoint,
    query_order_entries,
    sanitize_detail,
    snapshot_inventory,
)
from baker.services.order_stock import (
    audited_auto_decrement_stock,
    audited_restore_stock_for_order,
    audited_reverse_order_stock_for_edit,
    load_order_inventory_rows,
    reverse_order_stock_for_edit,
)
from tests.auth_helpers import _auth_headers, _seed_user

pytestmark = pytest.mark.critical


def _seed_order_product_and_chip(conn) -> tuple[int, int, int, int]:
    order = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, items, status, source) "
        "VALUES ('AUDIT-001', 'Khách audit', '[]', 'confirmed', 'Tại tiệm - POS')"
    )
    product = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, product_code) "
        "VALUES ('Bánh audit', 'banh_mi', 15000, 7000, 'AUD-01')"
    )
    product_id = int(product.lastrowid)
    chip = conn.execute(
        "INSERT INTO product_price_chips (product_id, label, price, position) "
        "VALUES (?, 'Giá audit', 17000, 1)",
        (product_id,),
    )
    chip_id = int(chip.lastrowid)
    item = conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, status, "
        " is_gift, price_chip_id, attributes) "
        "VALUES (?, ?, 'Bánh audit', 4, 17000, 'pending', 0, ?, ?)",
        (int(order.lastrowid), str(product_id), chip_id, '{"useInventory":"true"}'),
    )
    return int(order.lastrowid), product_id, chip_id, int(item.lastrowid)


def _context(
    order_id: int,
    *,
    created_at: str = "2026-09-04T03:00:00Z",
    operation_id: str = "11111111-1111-4111-8111-111111111111",
):
    return create_operation_context(
        order_id=order_id,
        order_ref="AUDIT-001",
        trigger=AuditTrigger.STATUS_ACTION,
        action=AuditAction.INVENTORY_DEDUCT,
        actor=AuditActor(
            identifier="cashier",
            username="cashier",
            staff_id=7,
            staff_name="Ân",
            role="staff",
        ),
        status_before="confirmed",
        status_after="delivered",
        operation_id=operation_id,
        created_at=created_at,
    )


def test_operation_context_generates_unique_id_and_utc_timestamp():
    first = create_operation_context(
        order_id=1,
        order_ref="UTC-1",
        trigger=AuditTrigger.ORDER_CREATION,
        action=AuditAction.ORDER_CREATE,
        actor=AuditActor(identifier="system"),
        created_at="2026-09-04T10:00:00+07:00",
    )
    second = create_operation_context(
        order_id=1,
        order_ref="UTC-1",
        trigger=AuditTrigger.ORDER_CREATION,
        action=AuditAction.ORDER_CREATE,
        actor=AuditActor(identifier="system"),
    )

    assert first.operation_id != second.operation_id
    assert first.created_at == "2026-09-04T03:00:00Z"
    assert second.created_at.endswith("Z")
    assert "+" not in second.created_at


def test_append_preserves_full_snapshot_when_operational_rows_change():
    with get_db() as conn:
        ensure_schema(conn)
        order_id, product_id, chip_id, item_id = _seed_order_product_and_chip(conn)
        create_lot_with_items(conn, product_id, chip_id, 5)
        conn.execute(
            "INSERT INTO negative_balance (product_id, price_chip_id, qty) "
            "VALUES (?, ?, 2)",
            (product_id, chip_id),
        )
        before = snapshot_inventory(conn, product_id, chip_id)
        assert before == InventorySnapshot(fifo_available=5, negative=2, net=3)

        entry = append_entry(
            conn,
            AuditEntryDraft(
                context=_context(order_id),
                outcome=AuditOutcome.APPLIED,
                reason=AuditReason.NEGATIVE_SALE,
                item=ItemSnapshot(
                    order_item_id=item_id,
                    product_id=product_id,
                    product_code="AUD-01",
                    product_name="Bánh audit",
                    is_gift=False,
                    is_display=True,
                    source="Tại tiệm - POS",
                    requested_quantity=4,
                    price_chip_id=chip_id,
                    price_chip_label="Giá audit",
                    use_inventory_present=True,
                    use_inventory_value=True,
                    resolved_bucket="price_chip",
                    resolved_price_chip_id=chip_id,
                    resolved_price_chip_label="Giá audit",
                    resolved_unit_price=17000,
                ),
                requested_delta=-4,
                applied_delta=-4,
                before=before,
                after=InventorySnapshot(fifo_available=1, negative=4, net=-3),
                stock_movement_id=41,
                negative_movement_id=42,
                detail="FIFO and negative effect committed",
            ),
        )

        conn.execute(
            "UPDATE products SET name = 'Tên mới', product_code = 'NEW' WHERE id = ?",
            (product_id,),
        )
        conn.execute(
            "UPDATE product_price_chips SET label = 'Nhãn mới' WHERE id = ?",
            (chip_id,),
        )
        conn.execute(
            "UPDATE order_items SET product_name = 'Mục mới', quantity = 99 WHERE id = ?",
            (item_id,),
        )

        stored = query_order_entries(conn, order_id=order_id)[0]
        assert stored == entry
        assert stored.item.product_code == "AUD-01"
        assert stored.item.product_name == "Bánh audit"
        assert stored.item.price_chip_label == "Giá audit"
        assert stored.item.requested_quantity == 4
        assert stored.before.net == 3
        assert stored.after.net == -3
        assert stored.context.actor.staff_name == "Ân"


def test_nullable_non_applicable_snapshots_round_trip_without_invented_zeroes():
    with get_db() as conn:
        ensure_schema(conn)
        order_id = int(
            conn.execute(
                "INSERT INTO orders (order_ref, customer_name, items) "
                "VALUES ('AUDIT-001', 'Khách audit', '[]')"
            ).lastrowid
        )
        stored = append_entry(
            conn,
            AuditEntryDraft(
                context=_context(order_id),
                outcome=AuditOutcome.SKIPPED,
                reason=AuditReason.MISSING_PRODUCT,
                item=ItemSnapshot(
                    product_code="REMOVED-CODE",
                    product_name="Sản phẩm đã xóa",
                    source="manual",
                    requested_quantity=2,
                ),
            ),
        )

        assert stored.item.product_id is None
        assert stored.item.order_item_id is None
        assert stored.item.is_display is None
        assert stored.item.use_inventory_present is None
        assert stored.item.use_inventory_value is None
        assert stored.item.resolved_bucket is None
        assert stored.before == InventorySnapshot()
        assert stored.after == InventorySnapshot()
        assert stored.requested_delta is None
        assert stored.applied_delta is None


def test_table_and_domain_objects_are_immutable():
    with get_db() as conn:
        ensure_schema(conn)
        order_id = int(
            conn.execute(
                "INSERT INTO orders (order_ref, customer_name, items) "
                "VALUES ('AUDIT-001', 'Khách audit', '[]')"
            ).lastrowid
        )
        entry = append_entry(
            conn,
            AuditEntryDraft(
                context=_context(order_id),
                outcome=AuditOutcome.NO_EFFECT,
                reason=AuditReason.STATUS_NO_EFFECT,
            ),
        )

        with pytest.raises(FrozenInstanceError):
            entry.detail = "changed"
        with pytest.raises(sqlite3.IntegrityError, match="append-only"):
            conn.execute(
                "UPDATE order_inventory_audit_entries SET detail = 'changed' WHERE id = ?",
                (entry.id,),
            )
        with pytest.raises(sqlite3.IntegrityError, match="append-only"):
            conn.execute(
                "DELETE FROM order_inventory_audit_entries WHERE id = ?",
                (entry.id,),
            )
        assert count_order_entries(conn, order_ref="AUDIT-001") == 1


def test_same_timestamp_query_uses_id_desc_and_bounded_default_page():
    with get_db() as conn:
        ensure_schema(conn)
        order_id = int(
            conn.execute(
                "INSERT INTO orders (order_ref, customer_name, items) "
                "VALUES ('AUDIT-001', 'Khách audit', '[]')"
            ).lastrowid
        )
        context = _context(order_id)
        entries = append_entries(
            conn,
            [
                AuditEntryDraft(
                    context=context,
                    outcome=AuditOutcome.NO_EFFECT,
                    reason=AuditReason.IDEMPOTENT_REPEAT,
                    detail=f"entry {number}",
                )
                for number in range(3)
            ],
        )
        queried = query_order_entries(conn, order_ref="AUDIT-001")
        assert [entry.id for entry in queried] == [entry.id for entry in reversed(entries)]

        minimal_rows = [
            (
                f"00000000-0000-4000-8000-{number:012d}", order_id, "AUDIT-001",
                "status_action", "status_change", "cashier",
                "2026-09-04T02:59:59Z", "no_effect", "idempotent_repeat",
            )
            for number in range(101)
        ]
        conn.executemany(
            "INSERT INTO order_inventory_audit_entries "
            "(operation_id, order_id, order_ref, trigger, action, actor_identifier, "
            " created_at, outcome, reason_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            minimal_rows,
        )
        assert len(query_order_entries(conn, order_id=order_id)) == 100
        assert count_order_entries(conn, order_id=order_id) == 104
        with pytest.raises(ValueError, match="between 1 and 500"):
            query_order_entries(conn, order_id=order_id, limit=501)


def test_failure_taxonomy_and_detail_sanitization_are_enforced():
    assert sanitize_detail("stage=fifo\nTraceback (most recent call last):\nraw") == "[redacted]"
    with get_db() as conn:
        ensure_schema(conn)
        order_id = int(
            conn.execute(
                "INSERT INTO orders (order_ref, customer_name, items) "
                "VALUES ('AUDIT-001', 'Khách audit', '[]')"
            ).lastrowid
        )
        failed = append_entry(
            conn,
            AuditEntryDraft(
                context=_context(order_id),
                outcome=AuditOutcome.FAILED,
                reason=AuditReason.FAILURE_FIFO_MUTATION,
                detail="stage=fifo\nTraceback (most recent call last):\nraw",
            ),
        )
        assert failed.detail == "[redacted]"

        with pytest.raises(ValueError, match="allow-listed failure reason"):
            append_entry(
                conn,
                AuditEntryDraft(
                    context=_context(order_id),
                    outcome=AuditOutcome.FAILED,
                    reason=AuditReason.MISSING_PRODUCT,
                ),
            )
        with pytest.raises(ValueError, match="outcome=failed"):
            append_entry(
                conn,
                AuditEntryDraft(
                    context=_context(order_id),
                    outcome=AuditOutcome.SKIPPED,
                    reason=AuditReason.FAILURE_UNEXPECTED,
                ),
            )


# Phase 2 decision and rollback coverage.


def _set_display(product_id: int, enabled: bool = True) -> None:
    with get_db() as conn:
        if enabled:
            conn.execute(
                "INSERT INTO product_attribute_values "
                "(product_id, attribute_type, value) VALUES (?, 'trung_bay', 'true') "
                "ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = 'true'",
                (product_id,),
            )
        else:
            conn.execute(
                "DELETE FROM product_attribute_values "
                "WHERE product_id = ? AND attribute_type = 'trung_bay'",
                (product_id,),
            )


def _create_chip(client, product_id: int, label: str, price: int) -> int:
    response = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price},
    )
    assert response.status_code == 201
    return int(response.json()["id"])


def _create_api_order(
    client,
    items: list[dict],
    *,
    headers: dict | None = None,
    **overrides,
) -> dict:
    payload = {
        "customerName": "Khách kiểm tra audit",
        "dueDate": "2026-09-04",
        "items": items,
        **overrides,
    }
    response = client.post("/api/orders", json=payload, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def _service_context(order_id: int, order_ref: str, action=AuditAction.INVENTORY_DEDUCT):
    return create_operation_context(
        order_id=order_id,
        order_ref=order_ref,
        trigger=AuditTrigger.STATUS_ACTION,
        action=action,
        actor=AuditActor(identifier="fault-tester"),
        status_before="new",
        status_after="confirmed",
    )


def _available(conn, product_id: int, chip_id: int | None) -> int:
    return snapshot_inventory(conn, product_id, chip_id).fifo_available or 0


def test_phase2_creation_decision_matrix_and_base_fallback(api_client):
    _set_display(1)
    _set_display(2, False)
    chip_id = _create_chip(api_client, 1, "Phase2 matrix", 17001)
    assert api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 5, "price_chip_id": chip_id},
    ).status_code == 200

    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Áp dụng", "quantity": 2,
             "unitPrice": 17001, "priceChipId": chip_id},
            {"productId": "1", "productName": "Bật tồn", "quantity": 1,
             "unitPrice": 17001, "priceChipId": chip_id,
             "attributes": {"useInventory": True}},
            {"productId": "1", "productName": "Quà", "quantity": 1,
             "unitPrice": 17001, "priceChipId": chip_id, "isGift": True},
            {"productId": "1", "productName": "Tắt tồn", "quantity": 1,
             "unitPrice": 17001, "priceChipId": chip_id,
             "attributes": {"useInventory": False}},
            {"productId": "2", "productName": "Không trưng bày", "quantity": 1,
             "unitPrice": 10000},
            {"productId": "REMOVED", "productName": "Đã xóa", "quantity": 1,
             "unitPrice": 10000},
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
        createdBy="phase2-cashier",
    )
    with get_db() as conn:
        entries = query_order_entries(conn, order_ref=order["orderRef"])
        by_name = {entry.item.product_name: entry for entry in entries}
        assert by_name["Áp dụng"].outcome == AuditOutcome.APPLIED
        assert by_name["Áp dụng"].reason == AuditReason.SOURCE_DEFAULT_CONSUME
        assert by_name["Áp dụng"].applied_delta == -2
        assert by_name["Áp dụng"].before.net == 5
        assert by_name["Áp dụng"].after.net == 3
        assert by_name["Áp dụng"].stock_movement_id is not None
        assert by_name["Áp dụng"].context.actor.identifier == "phase2-cashier"
        assert by_name["Áp dụng"].context.trigger == AuditTrigger.ORDER_CREATION
        assert by_name["Bật tồn"].outcome == AuditOutcome.APPLIED
        assert by_name["Bật tồn"].reason == AuditReason.EXPLICIT_INVENTORY_OPT_IN
        assert by_name["Bật tồn"].applied_delta == -1
        assert by_name["Quà"].reason == AuditReason.GIFT_ITEM
        assert by_name["Tắt tồn"].reason == AuditReason.EXPLICIT_INVENTORY_OPT_OUT
        assert by_name["Không trưng bày"].reason == AuditReason.NON_DISPLAY_PRODUCT
        assert by_name["Đã xóa"].reason == AuditReason.MISSING_PRODUCT
        assert all(
            by_name[name].outcome == AuditOutcome.SKIPPED
            for name in ("Quà", "Tắt tồn", "Không trưng bày", "Đã xóa")
        )

    assert api_client.post(
        "/api/products/1/stock/restock", json={"quantity": 1}
    ).status_code == 200
    fallback = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Rơi về giá gốc", "quantity": 1,
          "unitPrice": 987654}],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    with get_db() as conn:
        entry = query_order_entries(conn, order_ref=fallback["orderRef"])[0]
        assert entry.reason == AuditReason.PRICE_CHIP_FALLBACK_TO_BASE
        assert entry.outcome == AuditOutcome.APPLIED
        assert entry.item.resolved_bucket == "base"
        assert entry.applied_delta == -1

    default_skip = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Nguồn mặc định bỏ qua", "quantity": 1,
          "unitPrice": 17001, "priceChipId": chip_id}],
        source="Đặt trước",
    )
    assert api_client.post(
        f"/api/orders/{default_skip['orderRef']}/status",
        json={"status": "confirmed"},
    ).status_code == 200
    with get_db() as conn:
        entry = query_order_entries(conn, order_ref=default_skip["orderRef"])[0]
        assert entry.context.trigger == AuditTrigger.STATUS_ACTION
        assert entry.outcome == AuditOutcome.SKIPPED
        assert entry.reason == AuditReason.SOURCE_DEFAULT_SKIP
        assert entry.applied_delta == 0


def test_review_fallback_preserves_opt_out_and_source_skip_reasons(api_client):
    _set_display(1)

    opt_out = _create_api_order(
        api_client,
        [{
            "productId": "1",
            "productName": "Fallback tắt tồn",
            "quantity": 1,
            "unitPrice": 987654,
            "attributes": {"useInventory": False},
        }],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    source_skip = _create_api_order(
        api_client,
        [{
            "productId": "1",
            "productName": "Fallback nguồn bỏ qua",
            "quantity": 1,
            "unitPrice": 987654,
        }],
        source="Đặt trước",
    )
    assert api_client.post(
        f"/api/orders/{source_skip['orderRef']}/status",
        json={"status": "confirmed"},
    ).status_code == 200

    with get_db() as conn:
        opt_out_entry = query_order_entries(
            conn, order_ref=opt_out["orderRef"]
        )[0]
        source_skip_entry = query_order_entries(
            conn, order_ref=source_skip["orderRef"]
        )[0]

        assert opt_out_entry.outcome == AuditOutcome.SKIPPED
        assert opt_out_entry.reason == AuditReason.EXPLICIT_INVENTORY_OPT_OUT
        assert opt_out_entry.item.resolved_bucket == "base"
        assert opt_out_entry.item.resolved_price_chip_id is None
        assert opt_out_entry.applied_delta == 0
        assert source_skip_entry.outcome == AuditOutcome.SKIPPED
        assert source_skip_entry.reason == AuditReason.SOURCE_DEFAULT_SKIP
        assert source_skip_entry.item.resolved_bucket == "base"
        assert source_skip_entry.item.resolved_price_chip_id is None
        assert source_skip_entry.applied_delta == 0


def test_review_gift_snapshots_resolve_numeric_and_code_product_identity(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Gift identity chip", 17501)
    with get_db() as conn:
        product = conn.execute(
            "SELECT product_code FROM products WHERE id = 1"
        ).fetchone()
        product_code = product["product_code"]

    order = _create_api_order(
        api_client,
        [
            {
                "productId": "1",
                "productName": "Quà theo mã số",
                "quantity": 1,
                "unitPrice": 17501,
                "priceChipId": chip_id,
                "isGift": True,
            },
            {
                "productId": product_code,
                "productName": "Quà theo mã sản phẩm",
                "quantity": 1,
                "unitPrice": 17501,
                "priceChipId": chip_id,
                "isGift": True,
            },
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )

    with get_db() as conn:
        gifts = {
            entry.item.product_name: entry
            for entry in query_order_entries(conn, order_ref=order["orderRef"])
        }
        assert set(gifts) == {"Quà theo mã số", "Quà theo mã sản phẩm"}
        for name, entry in gifts.items():
            assert entry.reason == AuditReason.GIFT_ITEM
            assert entry.outcome == AuditOutcome.SKIPPED
            assert entry.item.product_id == 1
            assert entry.item.product_code == product_code
            assert entry.item.product_name == name
            assert entry.item.price_chip_id == chip_id
            assert entry.item.price_chip_label == "Gift identity chip"
            assert entry.item.is_gift is True
            assert entry.item.is_display is True
            assert entry.item.resolved_bucket == "price_chip"
            assert entry.item.resolved_price_chip_id == chip_id
            assert entry.item.resolved_price_chip_label == "Gift identity chip"
            assert entry.before == InventorySnapshot()
            assert entry.after == InventorySnapshot()


def test_phase5_authenticated_actor_precedes_client_fallback(auth_client):
    with get_db() as conn:
        staff_id = int(
            conn.execute(
                "INSERT INTO staff (name, role) VALUES ('Nhân viên audit', 'cashier')"
            ).lastrowid
        )
        token = _seed_user(conn, "audit.jwt", "staff")
        conn.execute(
            "UPDATE users SET staff_id = ? WHERE username = 'audit.jwt'",
            (staff_id,),
        )
        product_id = int(
            conn.execute(
                "INSERT INTO products (name, category, base_price, cost, product_code) "
                "VALUES ('Bánh JWT', 'banh_mi', 25000, 10000, 'AUD-JWT')"
            ).lastrowid
        )
        conn.execute(
            "INSERT INTO product_attribute_values "
            "(product_id, attribute_type, value) VALUES (?, 'trung_bay', 'true')",
            (product_id,),
        )
        create_lot_with_items(conn, product_id, None, 1)

    order = _create_api_order(
        auth_client,
        [{"productId": str(product_id), "productName": "Bánh JWT", "quantity": 1,
          "unitPrice": 25000}],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
        createdBy="spoofed-client-actor",
        headers=_auth_headers(token),
    )
    with get_db() as conn:
        entry = query_order_entries(conn, order_ref=order["orderRef"])[0]
        assert entry.context.actor.identifier == "audit.jwt"
        assert entry.context.actor.username == "audit.jwt"
        assert entry.context.actor.staff_id == staff_id
        assert entry.context.actor.staff_name == "Nhân viên audit"
        assert entry.context.actor.role == "staff"
        assert entry.context.actor.identifier != "spoofed-client-actor"


def test_phase2_status_edit_cancel_repeat_and_rejection_evidence(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase2 lifecycle", 18001)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 4, "price_chip_id": chip_id},
    )
    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Vòng đời", "quantity": 2,
             "unitPrice": 18001, "priceChipId": chip_id,
             "attributes": {"useInventory": True}},
            {"productId": "1", "productName": "Quà vòng đời", "quantity": 1,
             "unitPrice": 18001, "priceChipId": chip_id, "isGift": True},
        ],
        changedBy="ignored",
    )
    ref = order["orderRef"]
    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "confirmed", "changedBy": "cashier"},
    ).status_code == 200
    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "confirmed", "changedBy": "cashier"},
    ).status_code == 200
    assert api_client.post(
        f"/api/orders/{ref}/status", json={"status": "in_progress"}
    ).status_code == 200
    assert api_client.post(
        f"/api/orders/{ref}/status", json={"status": "ready"}
    ).status_code == 200
    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "in_progress", "reason": "quay lại xử lý"},
    ).status_code == 200

    response = api_client.patch(
        f"/api/orders/{ref}",
        json={"changedBy": "editor", "items": [
            {"productId": "1", "productName": "Vòng đời mới", "quantity": 1,
             "unitPrice": 18001, "priceChipId": chip_id,
             "attributes": {"useInventory": True}}
        ]},
    )
    assert response.status_code == 200
    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "khách hủy"},
    ).status_code == 200
    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "lặp lại"},
    ).status_code == 200
    rejected = api_client.post(
        f"/api/orders/{ref}/status", json={"status": "not-a-status"}
    )
    assert rejected.status_code == 422

    with get_db() as conn:
        entries = query_order_entries(conn, order_ref=ref, limit=100)
        reasons = [entry.reason for entry in entries]
        assert AuditReason.IDEMPOTENT_REPEAT in reasons
        assert AuditReason.STATUS_NO_EFFECT in reasons
        assert AuditReason.CANCEL_RESTORE in reasons
        assert {entry.outcome for entry in entries} == set(AuditOutcome)
        status_entries = [
            entry for entry in entries
            if entry.context.trigger == AuditTrigger.STATUS_ACTION
        ]
        assert {entry.context.action for entry in status_entries} >= {
            AuditAction.STATUS_CHANGE,
            AuditAction.INVENTORY_DEDUCT,
            AuditAction.INVENTORY_RESTORE,
        }
        cancel_entry = next(
            entry for entry in entries if entry.reason == AuditReason.CANCEL_RESTORE
        )
        assert cancel_entry.outcome == AuditOutcome.REVERSED
        rejected_entry = next(entry for entry in entries if entry.detail == "invalid_status")
        assert rejected_entry.outcome == AuditOutcome.FAILED
        assert rejected_entry.context.trigger == AuditTrigger.STATUS_ACTION
        edits = [
            entry for entry in entries
            if entry.reason in (AuditReason.EDIT_REVERSAL, AuditReason.EDIT_RE_EVALUATION)
        ]
        assert len(edits) == 2
        assert len({entry.context.operation_id for entry in edits}) == 1
        reversal = next(e for e in edits if e.reason == AuditReason.EDIT_REVERSAL)
        reevaluation = next(e for e in edits if e.reason == AuditReason.EDIT_RE_EVALUATION)
        assert reevaluation.related_entry_id == reversal.id
        assert reversal.item.product_name == "Vòng đời"
        assert reversal.context.trigger == AuditTrigger.REVERSAL
        assert reversal.outcome == AuditOutcome.REVERSED
        assert reevaluation.item.product_name == "Vòng đời mới"
        assert reevaluation.context.trigger == AuditTrigger.RE_EVALUATION
        assert reevaluation.outcome == AuditOutcome.APPLIED
        assert _available(conn, 1, chip_id) == 4


def test_review_duplicate_bucket_cancel_restores_each_sale_once(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Duplicate restore", 18501)
    assert api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    ).status_code == 200
    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Trùng một", "quantity": 1,
             "unitPrice": 18501, "priceChipId": chip_id},
            {"productId": "1", "productName": "Trùng hai", "quantity": 1,
             "unitPrice": 18501, "priceChipId": chip_id},
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    ref = order["orderRef"]
    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "khách hủy"},
    ).status_code == 200

    with get_db() as conn:
        assert snapshot_inventory(conn, 1, chip_id) == InventorySnapshot(
            fifo_available=2, negative=0, net=2
        )
        restores = conn.execute(
            "SELECT id, quantity FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'restore_sale' ORDER BY id",
            (ref,),
        ).fetchall()
        assert [row["quantity"] for row in restores] == [1, 1]
        cancel_entries = sorted(
            (
                entry for entry in query_order_entries(conn, order_ref=ref)
                if entry.reason == AuditReason.CANCEL_RESTORE
            ),
            key=lambda entry: entry.id,
        )
        assert len(cancel_entries) == 2
        assert [(entry.before.net, entry.after.net) for entry in cancel_entries] == [
            (0, 1),
            (1, 2),
        ]
        assert sum(entry.applied_delta or 0 for entry in cancel_entries) == 2
        assert [entry.stock_movement_id for entry in cancel_entries] == [
            row["id"] for row in restores
        ]
        assert len({entry.stock_movement_id for entry in cancel_entries}) == 2

    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "khôi phục lặp"},
    ).status_code == 200
    with get_db() as conn:
        assert snapshot_inventory(conn, 1, chip_id).net == 2
        assert conn.execute(
            "SELECT COUNT(*) AS qty FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'restore_sale'",
            (ref,),
        ).fetchone()["qty"] == 2
        repeated = query_order_entries(conn, order_ref=ref)[:2]
        assert all(entry.outcome == AuditOutcome.NO_EFFECT for entry in repeated)
        assert all(entry.reason == AuditReason.IDEMPOTENT_REPEAT for entry in repeated)
        assert all(entry.applied_delta == 0 for entry in repeated)
        assert all(entry.before == entry.after for entry in repeated)
        assert all(entry.stock_movement_id is None for entry in repeated)


def test_review_duplicate_bucket_oversold_cancel_clears_each_negative(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Duplicate negative restore", 18601)
    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Âm trùng một", "quantity": 1,
             "unitPrice": 18601, "priceChipId": chip_id},
            {"productId": "1", "productName": "Âm trùng hai", "quantity": 1,
             "unitPrice": 18601, "priceChipId": chip_id},
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    ref = order["orderRef"]
    with get_db() as conn:
        assert snapshot_inventory(conn, 1, chip_id).negative == 2

    assert api_client.post(
        f"/api/orders/{ref}/status",
        json={"status": "cancelled", "reason": "hủy bán âm"},
    ).status_code == 200

    with get_db() as conn:
        assert snapshot_inventory(conn, 1, chip_id) == InventorySnapshot(
            fifo_available=0, negative=0, net=0
        )
        restores = conn.execute(
            "SELECT id, quantity FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'restore_sale' ORDER BY id",
            (ref,),
        ).fetchall()
        negative_sales = conn.execute(
            "SELECT id FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'negative_sale' ORDER BY id",
            (ref,),
        ).fetchall()
        assert [row["quantity"] for row in restores] == [1, 1]
        cancel_entries = sorted(
            (
                entry for entry in query_order_entries(conn, order_ref=ref)
                if entry.reason == AuditReason.CANCEL_RESTORE
            ),
            key=lambda entry: entry.id,
        )
        assert len(cancel_entries) == 2
        assert [(entry.before.negative, entry.after.negative) for entry in cancel_entries] == [
            (2, 1),
            (1, 0),
        ]
        assert [(entry.before.net, entry.after.net) for entry in cancel_entries] == [
            (-2, -1),
            (-1, 0),
        ]
        assert sum(entry.applied_delta or 0 for entry in cancel_entries) == 2
        assert [entry.stock_movement_id for entry in cancel_entries] == [
            row["id"] for row in restores
        ]
        assert [entry.negative_movement_id for entry in cancel_entries] == [
            row["id"] for row in negative_sales
        ]


def test_phase2_reconciliation_and_work_item_paths_share_trusted_context(api_client):
    _set_display(1)
    with get_db() as conn:
        create_lot_with_items(conn, 1, None, 4)
    response = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "reconciliation-actor",
            "payment_method": "cash",
            "lines": [{
                "product_id": 1,
                "expected_qty": 4,
                "counted_qty": 2,
                "sale_qty": 2,
                "waste_qty": 0,
                "manual_unit_price": 15000,
            }],
        },
    )
    assert response.status_code == 201, response.text
    with get_db() as conn:
        reconciliation_entries = conn.execute(
            "SELECT operation_id, actor_identifier, order_ref "
            "FROM order_inventory_audit_entries "
            "WHERE source = 'reconciliation' ORDER BY id"
        ).fetchall()
        assert len(reconciliation_entries) == 2
        assert len({row["operation_id"] for row in reconciliation_entries}) == 1
        assert {row["actor_identifier"] for row in reconciliation_entries} == {
            "reconciliation-actor"
        }

    chip_id = _create_chip(api_client, 1, "Phase2 work item", 23001)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 1, "price_chip_id": chip_id},
    )
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Work item audit", "quantity": 1,
          "unitPrice": 23001, "priceChipId": chip_id,
          "attributes": {"useInventory": True}}],
    )
    item_id = order["workItems"][0]["id"]
    response = api_client.post(
        f"/api/orders/{order['orderRef']}/items/{item_id}/status",
        json={"status": "confirmed", "reason": ""},
    )
    assert response.status_code == 200, response.text
    with get_db() as conn:
        entry = query_order_entries(conn, order_ref=order["orderRef"])[0]
        assert entry.context.trigger == AuditTrigger.STATUS_ACTION
        assert entry.context.status_before == "new"
        assert entry.context.status_after == "confirmed"
        assert entry.outcome == AuditOutcome.APPLIED

    response = api_client.post(
        f"/api/orders/{order['orderRef']}/items/{item_id}/status",
        json={"status": "cancelled", "reason": "hủy công việc"},
    )
    assert response.status_code == 200, response.text
    with get_db() as conn:
        entry = query_order_entries(conn, order_ref=order["orderRef"])[0]
        assert entry.context.trigger == AuditTrigger.STATUS_ACTION
        assert entry.context.status_before == "confirmed"
        assert entry.context.status_after == "cancelled"
        assert entry.outcome == AuditOutcome.REVERSED
        assert entry.reason == AuditReason.CANCEL_RESTORE


def test_phase2_negative_edit_replaces_instead_of_accumulating_deficit(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase2 negative edit", 24001)
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Âm cũ", "quantity": 3,
          "unitPrice": 24001, "priceChipId": chip_id}],
        source="Tại tiệm - POS", status="delivered", paymentMethod="cash",
    )
    response = api_client.patch(
        f"/api/orders/{order['orderRef']}",
        json={"items": [
            {"productId": "1", "productName": "Âm mới", "quantity": 1,
             "unitPrice": 24001, "priceChipId": chip_id}
        ]},
    )
    assert response.status_code == 200
    with get_db() as conn:
        snapshot = snapshot_inventory(conn, 1, chip_id)
        assert snapshot.negative == 1
        assert snapshot.net == -1
        edits = [
            entry for entry in query_order_entries(conn, order_ref=order["orderRef"])
            if entry.context.trigger in (AuditTrigger.REVERSAL, AuditTrigger.RE_EVALUATION)
        ]
        assert {entry.context.trigger for entry in edits} == {
            AuditTrigger.REVERSAL,
            AuditTrigger.RE_EVALUATION,
        }
        assert sum(entry.applied_delta or 0 for entry in edits) == 2
        negative_entries = [
            entry for entry in query_order_entries(conn, order_ref=order["orderRef"])
            if entry.reason == AuditReason.NEGATIVE_SALE
        ]
        assert negative_entries
        assert all(entry.outcome == AuditOutcome.APPLIED for entry in negative_entries)
        assert all(entry.negative_movement_id is not None for entry in negative_entries)


def test_phase5_order_edit_entry_point_records_sanitized_outer_failure(
    monkeypatch,
    api_client,
):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase5 outer edit fault", 24501)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Edit outer fault", "quantity": 1,
          "unitPrice": 24501, "priceChipId": chip_id,
          "attributes": {"useInventory": True}}],
    )
    ref = order["orderRef"]
    assert api_client.post(
        f"/api/orders/{ref}/status", json={"status": "confirmed"}
    ).status_code == 200

    from baker.api import orders as orders_api

    def fail_before_reversal(*args, **kwargs):
        raise RuntimeError("token=outer-edit-secret")

    monkeypatch.setattr(
        orders_api,
        "audited_reverse_order_stock_for_edit",
        fail_before_reversal,
    )
    response = api_client.patch(
        f"/api/orders/{ref}",
        json={"items": [
            {"productId": "1", "productName": "Edit outer fault new", "quantity": 2,
             "unitPrice": 24501, "priceChipId": chip_id,
             "attributes": {"useInventory": True}}
        ]},
    )
    assert response.status_code == 200
    assert response.json()["accountingSyncWarning"] == "journal_sync_failed"

    with get_db() as conn:
        assert _available(conn, 1, chip_id) == 1
        failed = query_order_entries(conn, order_ref=ref)[0]
        assert failed.context.trigger == AuditTrigger.ORDER_EDIT
        assert failed.context.action == AuditAction.ORDER_EDIT
        assert failed.outcome == AuditOutcome.FAILED
        assert failed.reason == AuditReason.FAILURE_UNEXPECTED
        assert failed.detail == "edit_inventory_failed"
        assert "outer-edit-secret" not in (failed.detail or "")


def test_review_later_item_fifo_failure_keeps_exact_item_and_snapshot(api_client):
    _set_display(1)
    first_chip = _create_chip(api_client, 1, "Failure first chip", 18801)
    failing_chip = _create_chip(api_client, 1, "Failure second chip", 18802)
    assert api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 1, "price_chip_id": first_chip},
    ).status_code == 200
    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Mục đủ tồn", "quantity": 1,
             "unitPrice": 18801, "priceChipId": first_chip,
             "attributes": {"useInventory": True}},
            {"productId": "1", "productName": "Mục thiếu tồn", "quantity": 1,
             "unitPrice": 18802, "priceChipId": failing_chip,
             "attributes": {"useInventory": True}},
        ],
        source="Đặt trước",
    )
    ref = order["orderRef"]

    with get_db() as conn:
        context = _service_context(int(order["id"]), ref)
        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_auto_decrement_stock(
                conn, int(order["id"]), ref, context
            ),
            failure_reason=AuditReason.FAILURE_FIFO_MUTATION,
            failure_detail="fifo_outer_failed",
        )
        assert snapshot_inventory(conn, 1, first_chip).net == 1
        assert snapshot_inventory(conn, 1, failing_chip).net == 0
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ?", (ref,)
        ).fetchone() is None
        failed = query_order_entries(conn, order_ref=ref)[0]
        saved_items = load_order_inventory_rows(conn, int(order["id"]))
        failing_item_id = next(
            row["id"] for row in saved_items if row["product_name"] == "Mục thiếu tồn"
        )
        assert failed.outcome == AuditOutcome.FAILED
        assert failed.reason == AuditReason.FAILURE_INSUFFICIENT_STOCK
        assert failed.detail == "inventory_fifo_rejected"
        assert failed.item.order_item_id == failing_item_id
        assert failed.item.product_id == 1
        assert failed.item.product_name == "Mục thiếu tồn"
        assert failed.item.price_chip_id == failing_chip
        assert failed.item.price_chip_label == "Failure second chip"
        assert failed.item.resolved_price_chip_id == failing_chip
        assert failed.before == InventorySnapshot(fifo_available=0, negative=0, net=0)
        assert failed.after == failed.before


def test_review_same_bucket_failure_uses_committed_post_rollback_snapshot(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Same bucket failure", 18803)
    assert api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 1, "price_chip_id": chip_id},
    ).status_code == 200
    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Tạm dùng tồn", "quantity": 1,
             "unitPrice": 18803, "priceChipId": chip_id,
             "attributes": {"useInventory": True}},
            {"productId": "1", "productName": "Thất bại cùng kho", "quantity": 1,
             "unitPrice": 18803, "priceChipId": chip_id,
             "attributes": {"useInventory": True}},
        ],
        source="Đặt trước",
    )
    ref = order["orderRef"]

    with get_db() as conn:
        context = _service_context(int(order["id"]), ref)
        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_auto_decrement_stock(
                conn, int(order["id"]), ref, context
            ),
            failure_reason=AuditReason.FAILURE_FIFO_MUTATION,
            failure_detail="fifo_outer_failed",
        )
        committed = InventorySnapshot(fifo_available=1, negative=0, net=1)
        assert snapshot_inventory(conn, 1, chip_id) == committed
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ?", (ref,)
        ).fetchone() is None
        entries = query_order_entries(conn, order_ref=ref)
        assert len(entries) == 1
        failed = entries[0]
        failing_item_id = next(
            row["id"]
            for row in load_order_inventory_rows(conn, int(order["id"]))
            if row["product_name"] == "Thất bại cùng kho"
        )
        assert failed.outcome == AuditOutcome.FAILED
        assert failed.reason == AuditReason.FAILURE_INSUFFICIENT_STOCK
        assert failed.detail == "inventory_fifo_rejected"
        assert failed.item.order_item_id == failing_item_id
        assert failed.item.product_name == "Thất bại cùng kho"
        assert failed.item.resolved_price_chip_id == chip_id
        assert failed.before == committed
        assert failed.after == committed
        with pytest.raises(sqlite3.IntegrityError, match="append-only"):
            conn.execute(
                "UPDATE order_inventory_audit_entries SET detail = 'changed' "
                "WHERE id = ?",
                (failed.id,),
            )
        assert query_order_entries(conn, order_ref=ref)[0] == failed


def test_phase2_fifo_fault_rolls_back_partial_consumption(monkeypatch, api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase2 fifo fault", 19001)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "FIFO fault", "quantity": 1,
          "unitPrice": 19001, "priceChipId": chip_id,
          "attributes": {"useInventory": True}}],
    )
    original = order_stock.consume_fifo_items

    def consume_then_fail(*args, **kwargs):
        original(*args, **kwargs)
        raise RuntimeError("token=confidential")

    monkeypatch.setattr(order_stock, "consume_fifo_items", consume_then_fail)
    with get_db() as conn:
        context = _service_context(int(order["id"]), order["orderRef"])
        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_auto_decrement_stock(
                conn, int(order["id"]), order["orderRef"], context
            ),
            failure_reason=AuditReason.FAILURE_FIFO_MUTATION,
            failure_detail="fifo_outer_failed",
        )
        assert _available(conn, 1, chip_id) == 2
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ?",
            (order["orderRef"],),
        ).fetchone() is None
        failed = query_order_entries(conn, order_ref=order["orderRef"])[0]
        assert failed.reason == AuditReason.FAILURE_FIFO_MUTATION
        assert failed.detail == "inventory_fifo_mutation_failed"
        assert "confidential" not in (failed.detail or "")


def test_phase2_negative_fault_rolls_back_balance_and_movements(monkeypatch, api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase2 negative fault", 20001)
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Negative fault", "quantity": 2,
          "unitPrice": 20001, "priceChipId": chip_id}],
        source="Tại tiệm - POS",
    )
    original = order_stock.upsert_negative_balance

    def update_then_fail(*args, **kwargs):
        original(*args, **kwargs)
        raise RuntimeError("password=confidential")

    monkeypatch.setattr(order_stock, "upsert_negative_balance", update_then_fail)
    with get_db() as conn:
        context = _service_context(int(order["id"]), order["orderRef"])
        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_auto_decrement_stock(
                conn, int(order["id"]), order["orderRef"], context
            ),
            failure_reason=AuditReason.FAILURE_FIFO_MUTATION,
            failure_detail="negative_outer_failed",
        )
        assert snapshot_inventory(conn, 1, chip_id).negative == 0
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ?",
            (order["orderRef"],),
        ).fetchone() is None
        failed = query_order_entries(conn, order_ref=order["orderRef"])[0]
        assert failed.reason == AuditReason.FAILURE_NEGATIVE_BALANCE_MUTATION
        assert failed.detail == "negative_balance_mutation_failed"


def test_phase2_edit_reversal_fault_rolls_back_before_failure_evidence(api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase2 edit fault", 21001)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Edit fault", "quantity": 1,
          "unitPrice": 21001, "priceChipId": chip_id,
          "attributes": {"useInventory": True}}],
    )
    ref = order["orderRef"]
    api_client.post(f"/api/orders/{ref}/status", json={"status": "confirmed"})

    with get_db() as conn:
        context = _service_context(
            int(order["id"]), ref, AuditAction.INVENTORY_REVERSE
        )
        rows = load_order_inventory_rows(conn, int(order["id"]))

        def reverse_then_fail(*args):
            reverse_order_stock_for_edit(*args)
            raise RuntimeError("secret=confidential")

        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_reverse_order_stock_for_edit(
                conn, int(order["id"]), ref, context,
                item_rows=rows, reverse_operation=reverse_then_fail,
            ),
            failure_reason=AuditReason.FAILURE_FIFO_MUTATION,
            failure_detail="edit_outer_failed",
        )
        assert _available(conn, 1, chip_id) == 1
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'sale'", (ref,),
        ).fetchone() is not None
        failed = query_order_entries(conn, order_ref=ref)[0]
        assert failed.outcome == AuditOutcome.FAILED
        assert failed.detail == "edit_reversal_mutation_failed"


def test_phase2_restore_fault_rolls_back_partial_lot(monkeypatch, api_client):
    _set_display(1)
    chip_id = _create_chip(api_client, 1, "Phase2 restore fault", 22001)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 1, "price_chip_id": chip_id},
    )
    order = _create_api_order(
        api_client,
        [{"productId": "1", "productName": "Restore fault", "quantity": 1,
          "unitPrice": 22001, "priceChipId": chip_id}],
        source="Tại tiệm - POS", status="delivered", paymentMethod="cash",
    )
    original = order_stock.create_lot_with_items

    def restore_then_fail(*args, **kwargs):
        original(*args, **kwargs)
        raise RuntimeError("cookie=confidential")

    monkeypatch.setattr(order_stock, "create_lot_with_items", restore_then_fail)
    with get_db() as conn:
        context = _service_context(
            int(order["id"]), order["orderRef"], AuditAction.INVENTORY_RESTORE
        )
        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_restore_stock_for_order(
                conn, int(order["id"]), order["orderRef"], context
            ),
            failure_reason=AuditReason.FAILURE_RESTORE_MUTATION,
            failure_detail="restore_outer_failed",
        )
        assert _available(conn, 1, chip_id) == 0
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'restore_sale'", (order["orderRef"],),
        ).fetchone() is None
        failed = query_order_entries(conn, order_ref=order["orderRef"])[0]
        assert failed.reason == AuditReason.FAILURE_RESTORE_MUTATION
        assert failed.detail == "inventory_restore_mutation_failed"


@pytest.mark.parametrize("restore_kind", ["fifo", "negative"])
def test_review_second_restore_fault_keeps_exact_item_and_committed_state(
    monkeypatch,
    api_client,
    restore_kind,
):
    _set_display(1)
    chip_id = _create_chip(
        api_client, 1, f"Second {restore_kind} restore fault", 22002
    )
    if restore_kind == "fifo":
        assert api_client.post(
            "/api/products/1/stock/restock",
            json={"quantity": 2, "price_chip_id": chip_id},
        ).status_code == 200
    order = _create_api_order(
        api_client,
        [
            {"productId": "1", "productName": "Hoàn mục một", "quantity": 1,
             "unitPrice": 22002, "priceChipId": chip_id},
            {"productId": "1", "productName": "Hoàn mục hai", "quantity": 1,
             "unitPrice": 22002, "priceChipId": chip_id},
        ],
        source="Tại tiệm - POS",
        status="delivered",
        paymentMethod="cash",
    )
    ref = order["orderRef"]
    if restore_kind == "fifo":
        original = order_stock.create_lot_with_items
        calls = 0

        def fail_second_fifo_restore(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise RuntimeError("token=second-fifo-secret")
            return original(*args, **kwargs)

        monkeypatch.setattr(
            order_stock, "create_lot_with_items", fail_second_fifo_restore
        )

    with get_db() as conn:
        if restore_kind == "negative":
            conn.execute(
                f"""CREATE TEMP TRIGGER fail_second_negative_restore
                    BEFORE UPDATE OF qty ON negative_balance
                    WHEN OLD.product_id = 1
                      AND OLD.price_chip_id = {chip_id}
                      AND OLD.qty = 1
                    BEGIN
                      SELECT RAISE(ABORT, 'token=second-negative-secret');
                    END"""
            )
        committed = snapshot_inventory(conn, 1, chip_id)
        expected = (
            InventorySnapshot(fifo_available=0, negative=0, net=0)
            if restore_kind == "fifo"
            else InventorySnapshot(fifo_available=0, negative=2, net=-2)
        )
        assert committed == expected
        sale_movements = conn.execute(
            "SELECT id FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'sale' ORDER BY id",
            (ref,),
        ).fetchall()
        negative_movements = conn.execute(
            "SELECT id FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'negative_sale' ORDER BY id",
            (ref,),
        ).fetchall()
        context = _service_context(
            int(order["id"]), ref, AuditAction.INVENTORY_RESTORE
        )
        assert not execute_inventory_audit_savepoint(
            conn,
            context=context,
            operation=lambda: audited_restore_stock_for_order(
                conn, int(order["id"]), ref, context
            ),
            failure_reason=AuditReason.FAILURE_RESTORE_MUTATION,
            failure_detail="restore_outer_failed",
        )
        assert snapshot_inventory(conn, 1, chip_id) == committed
        assert conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? "
            "AND movement_type = 'restore_sale'",
            (ref,),
        ).fetchone() is None
        failed = query_order_entries(conn, order_ref=ref)[0]
        second_item_id = next(
            row["id"]
            for row in load_order_inventory_rows(conn, int(order["id"]))
            if row["product_name"] == "Hoàn mục hai"
        )
        assert failed.outcome == AuditOutcome.FAILED
        assert failed.reason == AuditReason.FAILURE_RESTORE_MUTATION
        assert failed.detail == "inventory_restore_mutation_failed"
        assert failed.item.order_item_id == second_item_id
        assert failed.item.product_name == "Hoàn mục hai"
        assert failed.stock_movement_id == sale_movements[1]["id"]
        assert failed.negative_movement_id == (
            negative_movements[1]["id"] if restore_kind == "negative" else None
        )
        assert failed.before == committed
        assert failed.after == committed
        assert "secret" not in (failed.detail or "")
