"""Focused DG-429 Phase 1 tests for the inventory audit domain service."""

import sqlite3
from dataclasses import FrozenInstanceError

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.inventory_fifo import create_lot_with_items
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
    query_order_entries,
    sanitize_detail,
    snapshot_inventory,
)

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
