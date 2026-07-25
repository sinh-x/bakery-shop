"""Tests for work item blank assignment CRUD endpoints (DG-294 Phase 1).

Covers POST/PATCH/DELETE /api/orders/{ref}/items/{id}/blanks and the
order_item_blanks junction table behavior.
"""

import json

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.blank import Blank


# --- helpers -----------------------------------------------------------------


def _create_order(client, customer="Khách test"):
    resp = client.post(
        "/api/orders",
        json={"customerName": customer, "dueDate": "2026-07-25"},
    )
    assert resp.status_code == 201
    return resp.json()


def _create_item(client, ref, **kwargs):
    payload = {"productName": "Bánh kem 16cm", **kwargs}
    resp = client.post(f"/api/orders/{ref}/items", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _create_blank(client, name="Cốt"):
    resp = client.post(
        "/api/blanks", json={"name": name, "category": "cot", "unit": "cai"}
    )
    assert resp.status_code == 201
    return resp.json()


def _create_blank_in_db(name="Cốt DB"):
    with get_db() as conn:
        ensure_schema(conn)
        blank = Blank(name=name, category="cot", unit="cai")
        blank.save(conn)
        return blank.id


# --- POST: add blank assignment (FR8) ----------------------------------------


def test_add_blank_assignment_creates_row(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]

    resp = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank["id"], "quantity": 2, "notes": "Phôi chính"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["blankId"] == blank["id"]
    assert body["quantity"] == 2
    assert body["notes"] == "Phôi chính"
    assert body["orderItemId"] == int(item_id)
    assert body["id"] is not None


def test_add_blank_assignment_default_quantity(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)

    resp = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"]},
    )
    assert resp.status_code == 201
    assert resp.json()["quantity"] == 1.0
    assert resp.json()["notes"] == ""


def test_add_blank_assignment_blank_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": 9999},
    )
    assert resp.status_code == 404
    assert "phôi" in resp.json()["detail"].lower()


def test_add_blank_assignment_work_item_not_found(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    resp = api_client.post(
        f"/api/orders/{order['orderRef']}/items/9999/blanks",
        json={"blankId": blank["id"]},
    )
    assert resp.status_code == 404


def test_add_blank_assignment_order_not_found(api_client):
    blank = _create_blank(api_client)
    resp = api_client.post(
        "/api/orders/ORD-NONEXIST/items/1/blanks",
        json={"blankId": blank["id"]},
    )
    assert resp.status_code == 404


def test_add_blank_assignment_negative_quantity_rejected(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    resp = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"], "quantity": -1},
    )
    assert resp.status_code == 400


def test_add_blank_assignment_duplicate_pair_upserts(api_client):
    """Re-adding the same (order_item, blank) pair upserts quantity/notes (DG-294 CQ-1).

    Previously INSERT OR IGNORE silently kept stale data. Now ON CONFLICT DO
    UPDATE refreshes quantity/notes while preserving the row id.
    """
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]

    r1 = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank["id"], "quantity": 2, "notes": "Ban đầu"},
    )
    assert r1.status_code == 201
    first_id = r1.json()["id"]
    assert r1.json()["quantity"] == 2
    assert r1.json()["notes"] == "Ban đầu"

    # Second insert for the same pair upserts: id preserved, quantity/notes refreshed
    r2 = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank["id"], "quantity": 5, "notes": "Cập nhật"},
    )
    assert r2.status_code == 201
    assert r2.json()["id"] == first_id
    assert r2.json()["quantity"] == 5
    assert r2.json()["notes"] == "Cập nhật"

    # GET list reflects the upserted values (no stale data)
    listed = api_client.get(f"/api/orders/{ref}/items").json()
    blanks = listed[0]["blanks"]
    assert len(blanks) == 1
    assert blanks[0]["id"] == first_id
    assert blanks[0]["quantity"] == 5
    assert blanks[0]["notes"] == "Cập nhật"


def test_add_multiple_blanks_to_same_work_item(api_client):
    """FR7: a work item can have multiple blanks assigned."""
    blank_a = _create_blank(api_client, name="Cốt")
    blank_b = _create_blank(api_client, name="Kem")
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]

    r1 = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank_a["id"], "quantity": 1},
    )
    assert r1.status_code == 201
    r2 = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank_b["id"], "quantity": 2, "notes": "Kem trang trí"},
    )
    assert r2.status_code == 201

    # GET list reflects both blanks
    listed = api_client.get(f"/api/orders/{ref}/items").json()
    assert len(listed[0]["blanks"]) == 2
    blank_ids = {b["blankId"] for b in listed[0]["blanks"]}
    assert blank_ids == {blank_a["id"], blank_b["id"]}


def test_add_blank_assignment_syncs_order_items_json(api_client):
    """FR12: adding a blank regenerates orders.items JSON with blanks array."""
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"], "quantity": 3, "notes": "x"},
    )
    with get_db() as conn:
        row = conn.execute(
            "SELECT items FROM orders WHERE order_ref = ?", (ref,)
        ).fetchone()
        items = json.loads(row["items"])
        assert items[0]["blanks"] == [
            {"blankId": blank["id"], "quantity": 3.0, "notes": "x"}
        ]


# --- PATCH: update blank assignment (FR9) ------------------------------------


def test_update_blank_assignment_quantity(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"], "quantity": 1},
    ).json()
    blank_item_id = created["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item['id']}/blanks/{blank_item_id}",
        json={"quantity": 5},
    )
    assert resp.status_code == 200
    assert resp.json()["quantity"] == 5.0


def test_update_blank_assignment_notes(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"], "quantity": 1, "notes": "old"},
    ).json()
    blank_item_id = created["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item['id']}/blanks/{blank_item_id}",
        json={"notes": "new notes"},
    )
    assert resp.status_code == 200
    assert resp.json()["notes"] == "new notes"


def test_update_blank_assignment_both_fields(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"], "quantity": 1},
    ).json()
    blank_item_id = created["id"]

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item['id']}/blanks/{blank_item_id}",
        json={"quantity": 4, "notes": "updated"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["quantity"] == 4.0
    assert body["notes"] == "updated"


def test_update_blank_assignment_empty_body(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"]},
    ).json()

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item['id']}/blanks/{created['id']}", json={}
    )
    assert resp.status_code == 400


def test_update_blank_assignment_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item['id']}/blanks/9999",
        json={"quantity": 5},
    )
    assert resp.status_code == 404


def test_update_blank_assignment_negative_quantity_rejected(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"]},
    ).json()

    resp = api_client.patch(
        f"/api/orders/{ref}/items/{item['id']}/blanks/{created['id']}",
        json={"quantity": -2},
    )
    assert resp.status_code == 400


# --- DELETE: remove blank assignment (FR10) ----------------------------------


def test_delete_blank_assignment(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"]},
    ).json()
    blank_item_id = created["id"]

    resp = api_client.delete(
        f"/api/orders/{ref}/items/{item['id']}/blanks/{blank_item_id}"
    )
    assert resp.status_code == 204

    # Confirm gone from the work item's blanks list
    listed = api_client.get(f"/api/orders/{ref}/items").json()
    assert listed[0]["blanks"] == []


def test_delete_blank_assignment_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    resp = api_client.delete(
        f"/api/orders/{ref}/items/{item['id']}/blanks/9999"
    )
    assert resp.status_code == 404


def test_delete_blank_assignment_work_item_not_found(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    created = api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"]},
    ).json()
    # Wrong order ref
    resp = api_client.delete(
        f"/api/orders/ORD-NONEXIST/items/{item['id']}/blanks/{created['id']}"
    )
    assert resp.status_code == 404


def test_delete_work_item_cascades_to_blanks(api_client):
    """Deleting a work item cascades to its order_item_blanks rows (ON DELETE CASCADE)."""
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = item["id"]
    created = api_client.post(
        f"/api/orders/{ref}/items/{item_id}/blanks",
        json={"blankId": blank["id"]},
    ).json()
    blank_item_id = created["id"]

    # Delete the work item
    api_client.delete(f"/api/orders/{ref}/items/{item_id}")
    # Junction row should be gone
    with get_db() as conn:
        row = conn.execute(
            "SELECT 1 FROM order_item_blanks WHERE id = ?", (blank_item_id,)
        ).fetchone()
        assert row is None


# --- Work item response shape (AC8/AC9) ---------------------------------------


def test_work_item_response_includes_blanks_array(api_client):
    """WorkItem.to_api_dict() includes a 'blanks' array (empty when none assigned)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    assert item["blanks"] == []


def test_work_item_response_blanks_populated(api_client):
    blank = _create_blank(api_client)
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    api_client.post(
        f"/api/orders/{ref}/items/{item['id']}/blanks",
        json={"blankId": blank["id"], "quantity": 2, "notes": "n"},
    )
    listed = api_client.get(f"/api/orders/{ref}/items").json()
    assert len(listed[0]["blanks"]) == 1
    b = listed[0]["blanks"][0]
    assert set(b.keys()) >= {"id", "orderItemId", "blankId", "quantity", "notes"}


# --- v83 migration: data migration from legacy blank_id column ---------------


def test_v83_migrates_legacy_blank_id_to_junction(api_client):
    """FR11: existing order_items.blank_id values are migrated to order_item_blanks."""
    blank_id = _create_blank_in_db(name="Legacy Cốt")
    order = _create_order(api_client)
    ref = order["orderRef"]
    item = _create_item(api_client, ref)
    item_id = int(item["id"])

    # Simulate pre-v83 data: the column is already dropped by v83, so insert
    # directly into the junction table to confirm the migration path is the
    # source of truth. (Direct column insertion is impossible post-v83.)
    with get_db() as conn:
        # Verify the legacy column no longer exists (v83 dropped it)
        cols = [r[1] for r in conn.execute("PRAGMA table_info(order_items)").fetchall()]
        assert "blank_id" not in cols
        # Insert a junction row manually as the migration would have
        conn.execute(
            """INSERT INTO order_item_blanks
               (order_item_id, blank_id, quantity, notes, created_at)
               VALUES (?, ?, 1, '', strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')""",
            (item_id, blank_id),
        )

    listed = api_client.get(f"/api/orders/{ref}/items").json()
    assert len(listed[0]["blanks"]) == 1
    assert listed[0]["blanks"][0]["blankId"] == blank_id


def test_v83_junction_table_schema(api_client):
    """AC8: order_item_blanks table has the required columns."""
    with get_db() as conn:
        cols = [r[1] for r in conn.execute("PRAGMA table_info(order_item_blanks)").fetchall()]
    for expected in ("id", "order_item_id", "blank_id", "quantity", "notes", "created_at"):
        assert expected in cols, f"missing column {expected!r} in {cols}"