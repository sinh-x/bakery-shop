"""Focused DG-429 Phase 3 API, reconciliation, and query performance tests."""

from __future__ import annotations

import json
import time

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.order_inventory_audit import (
    AuditAction,
    AuditActor,
    AuditEntryDraft,
    AuditOutcome,
    AuditReason,
    AuditTrigger,
    InventorySnapshot,
    ItemSnapshot,
    append_entry,
    create_operation_context,
    query_order_audit_page,
)
from tests.auth_helpers import _auth_headers, _seed_user

pytestmark = pytest.mark.critical


def _seed_order(conn, order_ref: str = "AUDIT-API-001") -> int:
    return int(
        conn.execute(
            "INSERT INTO orders (order_ref, customer_name, items, status, source) "
            "VALUES (?, 'Khách API audit', '[]', 'confirmed', 'Tại tiệm - POS')",
            (order_ref,),
        ).lastrowid
    )


def _append_audit_entry(
    conn,
    order_id: int,
    order_ref: str = "AUDIT-API-001",
    *,
    created_at: str = "2026-09-04T03:00:00Z",
    order_item_id: int | None = None,
    stock_movement_id: int | None = None,
    detail: str | None = None,
):
    context = create_operation_context(
        order_id=order_id,
        order_ref=order_ref,
        trigger=AuditTrigger.STATUS_ACTION,
        action=AuditAction.INVENTORY_DEDUCT,
        actor=AuditActor(
            identifier="cashier.jwt",
            username="cashier.jwt",
            staff_id=17,
            staff_name="Thu ngân",
            role="staff",
        ),
        status_before="new",
        status_after="confirmed",
        created_at=created_at,
    )
    return append_entry(
        conn,
        AuditEntryDraft(
            context=context,
            outcome=AuditOutcome.FAILED if detail else AuditOutcome.APPLIED,
            reason=(
                AuditReason.FAILURE_FIFO_MUTATION
                if detail
                else AuditReason.ELIGIBLE_DISPLAY_ITEM
            ),
            item=ItemSnapshot(
                order_item_id=order_item_id,
                product_id=31,
                product_code="TB-31",
                product_name="Bánh trưng bày",
                is_gift=False,
                is_display=True,
                source="Tại tiệm - POS",
                requested_quantity=2,
                price_chip_id=9,
                price_chip_label="Miếng lớn",
                use_inventory_present=True,
                use_inventory_value=True,
                resolved_bucket="price_chip",
                resolved_price_chip_id=9,
                resolved_price_chip_label="Miếng lớn",
                resolved_unit_price=45000,
            ),
            requested_delta=-2,
            applied_delta=0 if detail else -2,
            before=InventorySnapshot(fifo_available=5, negative=0, net=5),
            after=(
                InventorySnapshot(fifo_available=5, negative=0, net=5)
                if detail
                else InventorySnapshot(fifo_available=3, negative=0, net=3)
            ),
            stock_movement_id=stock_movement_id,
            detail=detail,
        ),
    )


def _bulk_insert_entries(conn, order_id: int, order_ref: str, count: int) -> None:
    conn.executemany(
        "INSERT INTO order_inventory_audit_entries "
        "(operation_id, order_id, order_ref, trigger, action, actor_identifier, "
        " created_at, outcome, reason_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                f"00000000-0000-4000-8000-{number:012d}",
                order_id,
                order_ref,
                "status_action",
                "status_change",
                "performance-test",
                "2026-09-04T03:00:00Z",
                "no_effect",
                "idempotent_repeat",
            )
            for number in range(count)
        ],
    )


def test_inventory_audit_known_empty_unknown_and_validation_contract(api_client):
    with get_db() as conn:
        order_id = _seed_order(conn)

    response = api_client.get(f"/api/orders/{order_id}/inventory-audit")
    assert response.status_code == 200
    assert response.json() == {
        "items": [],
        "total": 0,
        "hasMore": False,
        "limit": 100,
        "offset": 0,
    }

    assert api_client.get("/api/orders/UNKNOWN/inventory-audit").status_code == 404
    assert (
        api_client.get(
            f"/api/orders/{order_id}/inventory-audit", params={"limit": 501}
        ).status_code
        == 422
    )
    assert (
        api_client.get(
            f"/api/orders/{order_id}/inventory-audit", params={"offset": -1}
        ).status_code
        == 422
    )


def test_inventory_audit_tied_timestamp_pages_are_stable_and_newest_first(api_client):
    with get_db() as conn:
        order_id = _seed_order(conn)
        _bulk_insert_entries(conn, order_id, "AUDIT-API-001", 102)
        expected_ids = [
            row["id"]
            for row in conn.execute(
                "SELECT id FROM order_inventory_audit_entries "
                "WHERE order_id = ? ORDER BY created_at DESC, id DESC",
                (order_id,),
            ).fetchall()
        ]

    first = api_client.get(f"/api/orders/{order_id}/inventory-audit")
    repeated = api_client.get(f"/api/orders/{order_id}/inventory-audit")
    second = api_client.get(
        f"/api/orders/{order_id}/inventory-audit",
        params={"limit": 100, "offset": 100},
    )

    assert first.status_code == repeated.status_code == second.status_code == 200
    assert [item["id"] for item in first.json()["items"]] == expected_ids[:100]
    assert repeated.json()["items"] == first.json()["items"]
    assert [item["id"] for item in second.json()["items"]] == expected_ids[100:]
    assert first.json()["total"] == second.json()["total"] == 102
    assert first.json()["hasMore"] is True
    assert second.json()["hasMore"] is False
    assert second.json()["offset"] == 100


def test_inventory_audit_entry_is_camel_case_and_sanitized(api_client):
    with get_db() as conn:
        order_id = _seed_order(conn)
        entry = _append_audit_entry(
            conn,
            order_id,
            detail=(
                "stage=fifo token=top-secret\n"
                "Traceback (most recent call last):\nraw confidential request"
            ),
        )

    response = api_client.get("/api/orders/AUDIT-API-001/inventory-audit")
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["id"] == entry.id
    assert item["operationId"] == entry.context.operation_id
    assert item["actor"] == {
        "identifier": "cashier.jwt",
        "username": "cashier.jwt",
        "staffId": 17,
        "staffName": "Thu ngân",
        "role": "staff",
    }
    assert item["item"]["productCode"] == "TB-31"
    assert item["item"]["useInventoryValue"] is True
    assert item["before"] == {"fifoAvailable": 5, "negative": 0, "net": 5}
    assert item["after"] == {"fifoAvailable": 5, "negative": 0, "net": 5}
    assert item["reasonCode"] == "failure_fifo_mutation"
    assert "top-secret" not in item["detail"]
    assert "Traceback" not in item["detail"]
    assert "raw confidential request" not in item["detail"]
    assert item["reconciliationSessionId"] is None
    assert item["reconciliationSessionIds"] == []
    assert item["reconciliationLineIds"] == []
    assert item["reconciliationSaleRowIds"] == []


@pytest.mark.parametrize("role", ["staff", "admin"])
def test_inventory_audit_is_available_to_every_authenticated_order_viewer(
    auth_client,
    role,
):
    with get_db() as conn:
        order_id = _seed_order(conn, f"AUDIT-AUTH-{role}")
        _append_audit_entry(conn, order_id, f"AUDIT-AUTH-{role}")
        token = _seed_user(conn, f"audit-{role}", role)

    response = auth_client.get(
        f"/api/orders/{order_id}/inventory-audit",
        headers=_auth_headers(token),
    )
    assert response.status_code == 200
    assert response.json()["total"] == 1


def test_inventory_audit_blocks_unauthenticated_when_auth_is_required(auth_client):
    with get_db() as conn:
        order_id = _seed_order(conn)
    response = auth_client.get(f"/api/orders/{order_id}/inventory-audit")
    assert response.status_code == 401


def test_inventory_audit_preserves_configured_grace_access(anon_client):
    with get_db() as conn:
        order_id = _seed_order(conn)
    response = anon_client.get(f"/api/orders/{order_id}/inventory-audit")
    assert response.status_code == 200


def test_inventory_audit_enriches_existing_reconciliation_relationships(api_client):
    with get_db() as conn:
        product_id = int(
            conn.execute(
                "INSERT INTO products (name, category, base_price, cost, product_code) "
                "VALUES ('Bánh đối soát', 'banh_mi', 40000, 20000, 'DS-01')"
            ).lastrowid
        )
        order_id = _seed_order(conn)
        entry = _append_audit_entry(
            conn,
            order_id,
            order_item_id=501,
            stock_movement_id=701,
        )
        session_id = int(
            conn.execute(
                "INSERT INTO reconciliation_sessions "
                "(reconciliation_date, staff_name, created_at) "
                "VALUES ('2026-09-04', 'Nhân viên', '2026-09-04T02:00:00Z')"
            ).lastrowid
        )
        item_line_id = int(
            conn.execute(
                "INSERT INTO reconciliation_lines "
                "(session_id, product_id, expected_qty, counted_qty, "
                " linked_order_item_id, created_at) VALUES (?, ?, 2, 2, 501, ?)",
                (session_id, product_id, "2026-09-04T02:00:00Z"),
            ).lastrowid
        )
        movement_line_id = int(
            conn.execute(
                "INSERT INTO reconciliation_lines "
                "(session_id, product_id, expected_qty, counted_qty, "
                " linked_stock_movement_sale_id, created_at) "
                "VALUES (?, ?, 2, 2, 701, ?)",
                (session_id, product_id, "2026-09-04T02:00:00Z"),
            ).lastrowid
        )
        direct_sale_row_id = int(
            conn.execute(
                "INSERT INTO reconciliation_sale_rows "
                "(line_id, quantity, unit_price, payment_method, linked_order_ref, "
                " linked_order_refs, created_at) VALUES (?, 1, 40000, 'cash', ?, ?, ?)",
                (
                    item_line_id,
                    "AUDIT-API-001",
                    json.dumps(["AUDIT-API-001"]),
                    "2026-09-04T02:00:00Z",
                ),
            ).lastrowid
        )
        listed_sale_row_id = int(
            conn.execute(
                "INSERT INTO reconciliation_sale_rows "
                "(line_id, quantity, unit_price, payment_method, linked_order_ref, "
                " linked_order_refs, created_at) VALUES (?, 1, 40000, 'cash', ?, ?, ?)",
                (
                    movement_line_id,
                    "OTHER-ORDER",
                    json.dumps(["OTHER-ORDER", "AUDIT-API-001"]),
                    "2026-09-04T02:00:00Z",
                ),
            ).lastrowid
        )

    response = api_client.get("/api/orders/AUDIT-API-001/inventory-audit")
    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["id"] == entry.id
    assert item["reconciliationSessionId"] == session_id
    assert item["reconciliationSessionIds"] == [session_id]
    assert item["reconciliationLineIds"] == [item_line_id, movement_line_id]
    assert item["reconciliationSaleRowIds"] == [
        direct_sale_row_id,
        listed_sale_row_id,
    ]


def test_inventory_audit_exposes_no_mutation_route(api_client):
    with get_db() as conn:
        order_id = _seed_order(conn)
        _append_audit_entry(conn, order_id)

    path = f"/api/orders/{order_id}/inventory-audit"
    assert api_client.post(path, json={}).status_code == 405
    assert api_client.patch(path, json={}).status_code == 405
    assert api_client.delete(path).status_code == 405
    with get_db() as conn:
        count = conn.execute(
            "SELECT COUNT(*) FROM order_inventory_audit_entries WHERE order_id = ?",
            (order_id,),
        ).fetchone()[0]
    assert count == 1


def test_query_first_page_of_10000_entries_under_500ms():
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn, "AUDIT-PERF-001")
        _bulk_insert_entries(conn, order_id, "AUDIT-PERF-001", 10_000)
        conn.commit()
        plan = conn.execute(
            "EXPLAIN QUERY PLAN SELECT * FROM order_inventory_audit_entries "
            "WHERE order_id = ? ORDER BY created_at DESC, id DESC LIMIT 100 OFFSET 0",
            (order_id,),
        ).fetchall()
        assert any(
            "idx_order_inventory_audit_order_created" in row["detail"]
            for row in plan
        )

        started = time.perf_counter()
        page = query_order_audit_page(conn, order_id=order_id)
        elapsed_ms = (time.perf_counter() - started) * 1000

    print(f"DG-429 inventory audit query: {elapsed_ms:.3f} ms")
    assert len(page["items"]) == 100
    assert page["total"] == 10_000
    assert page["hasMore"] is True
    assert page["limit"] == 100
    assert elapsed_ms < 500
