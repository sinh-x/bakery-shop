"""DG-252 Phase 3 — Merge + duplicates API tests (FR5, FR6, NFR3, AC3).

Covers:
  - Merge endpoint ``POST /api/customers/{id}/merge``:
    - admin succeeds (relink orders, dedupe phones, recompute year summary,
      hard-delete source, audit-log entry written)
    - non-admin → 403
    - unknown target id → 404
    - unknown source id → 404
    - self-merge (source == target) → 400
    - rollback-on-failure: a mid-transaction exception leaves target, source,
      orders, phones, and year summary all unchanged (NFR3)
  - Duplicates endpoint ``GET /api/customers/duplicates``:
    - admin succeeds with phone-keyed and name-keyed groups
    - non-admin → 403
    - groups include per-customer order counts
    - empty DB → empty groups
    - diacritic-insensitive name grouping
"""

from __future__ import annotations

import pytest

from datetime import datetime, timezone

from baker.api.customers import (
    CUSTOMER_BATCH_MERGE_DUPLICATE_MSG,
    CUSTOMER_BATCH_MERGE_EMPTY_MSG,
    CUSTOMER_BATCH_MERGE_SELF_MSG,
    CUSTOMER_BATCH_MERGE_SOURCE_NOT_FOUND_MSG,
    CUSTOMER_MERGE_NOT_FOUND_MSG,
    CUSTOMER_MERGE_SELF_MSG,
    CUSTOMER_MERGE_SOURCE_NOT_FOUND_MSG,
)
from baker.db.connection import get_db
from baker.models.customer import load_year_summary
from tests.auth_helpers import _auth_headers, _seed_user

pytestmark = pytest.mark.critical


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _current_year() -> int:
    return datetime.now(timezone.utc).year


def _create_customer(client, name="Nguyễn Văn A", phone="0901234567", headers=None, **kwargs):
    payload = {"name": name, "phone": phone, **kwargs}
    resp = client.post("/api/customers", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_order(client, customer_id, customer_name="Khách", phone="", headers=None):
    payload = {
        "customerName": customer_name,
        "customerPhone": phone,
        "customerId": customer_id,
        "items": [
            {"productName": "Bánh mì", "quantity": 1, "unitPrice": 10000, "productId": "BMI-01"}
        ],
        "dueDate": "2026-07-01",
    }
    resp = client.post("/api/orders", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _seed_admin(client_fixture):
    """Seed an admin user and return an admin token."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "mergeadmin", "admin")
    return admin_token


def _seed_staff(client_fixture):
    with get_db() as conn:
        staff_token = _seed_user(conn, "mergestaff", "staff")
    return staff_token


def _admin_setup(client):
    """Seed an admin and return (admin_headers, admin_token)."""
    token = _seed_admin(client)
    return _auth_headers(token), token


# ---------------------------------------------------------------------------
# Merge: admin success path (FR5 / AC3)
# ---------------------------------------------------------------------------


def test_merge_admin_succeeds_relinks_orders_phones_recomputes_summary_deletes_source(auth_client):
    """FR5/AC3 — admin merge relinks orders+phones, recomputes year summary,
    hard-deletes source, and writes an audit-log entry."""
    headers, admin_token = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Khách đích", phone="0901111222", headers=headers)
    source = _create_customer(auth_client, name="Khách nguồn", phone="0902222333", headers=headers)
    # Add a secondary phone to the source so phone-dedupe is exercised.
    auth_client.patch(
        f"/api/customers/{source['id']}",
        json={"phones": [
            {"phone": "0902222333", "isPrimary": True},
            {"phone": "0903333444", "isPrimary": False},
        ]},
        headers=headers,
    )
    # Two orders on the source, one on the target.
    _create_order(auth_client, source["id"], source["name"], headers=headers)
    _create_order(auth_client, source["id"], source["name"], headers=headers)
    _create_order(auth_client, target["id"], target["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source["id"]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ok"] is True
    assert body["targetId"] == target["id"]
    assert body["sourceId"] == source["id"]
    assert body["movedOrders"] == 2
    # Source had 2 phones, target had 1 unique phone → 2 new phones added.
    assert body["addedPhones"] == 2

    # Source is hard-deleted.
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM customers WHERE id = ?", (source["id"],)
        ).fetchone()
        assert row is None
        # All source orders now point at target.
        target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?",
            (target["id"],),
        ).fetchone()[0]
        assert target_orders == 3
        # Source phone rows gone; target has 3 phones (1 original + 2 merged).
        target_phones = conn.execute(
            "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ? "
            "ORDER BY is_primary DESC, id ASC",
            (target["id"],),
        ).fetchall()
        target_phone_set = {r["phone"] for r in target_phones}
        assert target_phone_set == {"0901111222", "0902222333", "0903333444"}
        # DG-252 r3 [MINOR] invariant: a merged customer with phone rows
        # must have exactly one primary (mirrors CustomerCreate/CustomerUpdate
        # validators at customers.py:81,108).
        primaries = [r for r in target_phones if r["is_primary"] == 1]
        assert len(primaries) == 1, (
            f"merged customer must have exactly one primary phone, got "
            f"{len(primaries)}: {[(r['phone'], r['is_primary']) for r in target_phones]}"
        )
        # Year summary recomputed for the current year (3 orders × 10000).
        ys = load_year_summary(conn, target["id"], _current_year())
        assert ys["orderCount"] == 3
        assert ys["totalVolume"] == 30000
        # Audit log entry written.
        audit = conn.execute(
            "SELECT action, entity_type, entity_id, old_value, new_value "
            "FROM audit_log WHERE entity_type = 'customer' AND action = 'merge' "
            "ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert audit is not None
        assert audit["entity_id"] == str(target["id"])

    # Target is still fetchable via the API.
    get_resp = auth_client.get(f"/api/customers/{target['id']}", headers=headers)
    assert get_resp.status_code == 200


def test_merge_dedupes_overlapping_phones(auth_client):
    """FR5 — phones the target already owns are not duplicated on merge."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0900", headers=headers)
    source = _create_customer(auth_client, name="Nguồn", phone="0900", headers=headers)  # same phone
    _create_order(auth_client, source["id"], source["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source["id"]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["addedPhones"] == 0

    with get_db() as conn:
        phones = conn.execute(
            "SELECT phone FROM customer_phones WHERE customer_id = ?",
            (target["id"],),
        ).fetchall()
        # Only one row for the shared phone (no duplicate).
        assert len(phones) == 1
        assert phones[0]["phone"] == "0900"


# ---------------------------------------------------------------------------
# Merge: error paths (FR5 / AC3)
# ---------------------------------------------------------------------------


def test_merge_non_admin_returns_403(auth_client):
    """FR5/AC3 — staff JWT → 403."""
    admin_headers, _ = _admin_setup(auth_client)
    staff_token = _seed_staff(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0901", headers=admin_headers)
    source = _create_customer(auth_client, name="Nguồn", phone="0902", headers=admin_headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source["id"]},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403
    # No data changes.
    assert auth_client.get(f"/api/customers/{source['id']}", headers=admin_headers).status_code == 200


def test_merge_self_merge_returns_400(auth_client):
    """FR5/AC3 — source == target → 400."""
    headers, _ = _admin_setup(auth_client)
    target = _create_customer(auth_client, name="Trùng id", phone="0901", headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": target["id"]},
        headers=headers,
    )
    assert resp.status_code == 400
    assert resp.json()["detail"] == CUSTOMER_MERGE_SELF_MSG


def test_merge_unknown_target_returns_404(auth_client):
    """FR5/AC3 — unknown target id → 404."""
    headers, _ = _admin_setup(auth_client)
    source = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)

    resp = auth_client.post(
        "/api/customers/999999/merge",
        json={"sourceCustomerId": source["id"]},
        headers=headers,
    )
    assert resp.status_code == 404
    assert resp.json()["detail"] == CUSTOMER_MERGE_NOT_FOUND_MSG


def test_merge_unknown_source_returns_404(auth_client):
    """FR5/AC3 — unknown source id → 404."""
    headers, _ = _admin_setup(auth_client)
    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": 999999},
        headers=headers,
    )
    assert resp.status_code == 404
    assert resp.json()["detail"] == CUSTOMER_MERGE_SOURCE_NOT_FOUND_MSG


def test_merge_grace_period_anon_allowed_when_auth_required_false(anon_client):
    """NFR6 — AUTH_REQUIRED=false (grace period) lets an unauthenticated
    merge request through, mirroring the other admin write endpoints."""
    target = _create_customer(anon_client, name="Đích", phone="0901")
    source = _create_customer(anon_client, name="Nguồn", phone="0902")
    _create_order(anon_client, source["id"], source["name"])

    resp = anon_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source["id"]},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["movedOrders"] == 1


# ---------------------------------------------------------------------------
# Merge: transactional rollback (NFR3)
# ---------------------------------------------------------------------------


def test_merge_rolls_back_on_failure(auth_client, monkeypatch):
    """NFR3 — a mid-transaction exception leaves target, source, orders,
    phones, and year summary all unchanged. The whole merge is atomic."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    source = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)
    _create_order(auth_client, source["id"], source["name"], headers=headers)

    # Snapshot pre-merge state for comparison after the failed merge.
    with get_db() as conn:
        pre_source_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (source["id"],)
        ).fetchone()[0]
        pre_target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (target["id"],)
        ).fetchone()[0]
        pre_source_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (source["id"],),
        ).fetchone()[0]
        pre_target_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (target["id"],),
        ).fetchone()[0]

    # Inject a failure into _recompute_customer_year_summary so the merge
    # aborts AFTER the orders have been relinked but BEFORE commit. The
    # get_db() context manager must roll the whole transaction back.
    from baker.api import customers as customers_module

    original_recompute = customers_module._recompute_customer_year_summary

    def _boom(conn, customer_id, year):
        raise RuntimeError("simulated mid-merge failure")

    monkeypatch.setattr(
        customers_module, "_recompute_customer_year_summary", _boom
    )

    # TestClient re-raises server exceptions by default; catch it so we can
    # assert the request failed (the merge must NOT have committed).
    merge_failed = False
    try:
        auth_client.post(
            f"/api/customers/{target['id']}/merge",
            json={"sourceCustomerId": source["id"]},
            headers=headers,
        )
    except RuntimeError:
        merge_failed = True

    # Restore before any further DB access so the post-merge assertions use
    # the real implementation.
    monkeypatch.setattr(
        customers_module, "_recompute_customer_year_summary", original_recompute
    )

    assert merge_failed, "merge should have failed mid-transaction"

    with get_db() as conn:
        # Source still exists (hard-delete rolled back).
        row = conn.execute(
            "SELECT id FROM customers WHERE id = ?", (source["id"],)
        ).fetchone()
        assert row is not None
        # Orders still on the source, none moved to target.
        post_source_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (source["id"],)
        ).fetchone()[0]
        post_target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (target["id"],)
        ).fetchone()[0]
        assert post_source_orders == pre_source_orders
        assert post_target_orders == pre_target_orders
        # Phones unchanged.
        post_source_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (source["id"],),
        ).fetchone()[0]
        post_target_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (target["id"],),
        ).fetchone()[0]
        assert post_source_phones == pre_source_phones
        assert post_target_phones == pre_target_phones
        # No audit-log entry committed.
        audit = conn.execute(
            "SELECT COUNT(*) FROM audit_log WHERE entity_type = 'customer' "
            "AND action = 'merge'"
        ).fetchone()[0]
        assert audit == 0


# ---------------------------------------------------------------------------
# Duplicates: admin success path (FR6)
# ---------------------------------------------------------------------------


def test_duplicates_admin_returns_phone_groups(auth_client):
    """FR6 — admin gets duplicate groups keyed by normalized phone, with
    per-customer order counts."""
    headers, _ = _admin_setup(auth_client)

    a = _create_customer(auth_client, name="Khách A", phone="0900555666", headers=headers)
    b = _create_customer(auth_client, name="Khách B", phone="0900555666", headers=headers)
    _create_order(auth_client, a["id"], a["name"], headers=headers)
    _create_order(auth_client, a["id"], a["name"], headers=headers)
    _create_order(auth_client, b["id"], b["name"], headers=headers)
    # A unique customer that should NOT appear in any group.
    _create_customer(auth_client, name="Độc nhất", phone="0911111222", headers=headers)

    resp = auth_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200, resp.text
    groups = resp.json()["groups"]
    phone_groups = [g for g in groups if g["kind"] == "phone"]
    assert len(phone_groups) == 1
    g = phone_groups[0]
    assert g["key"] == "0900555666"
    members = {m["id"]: m for m in g["customers"]}
    assert set(members) == {a["id"], b["id"]}
    assert members[a["id"]]["orderCount"] == 2
    assert members[b["id"]]["orderCount"] == 1


def test_duplicates_admin_returns_name_groups_diacritic_insensitive(auth_client):
    """FR6 — diacritic-stripped search_name groups customers whose names
    differ only by Vietnamese diacritics."""
    headers, _ = _admin_setup(auth_client)

    _create_customer(auth_client, name="Nguyễn Văn Đức", phone="0901", headers=headers)
    _create_customer(auth_client, name="Nguyen Van Duc", phone="0902", headers=headers)

    resp = auth_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200, resp.text
    groups = resp.json()["groups"]
    name_groups = [g for g in groups if g["kind"] == "name"]
    assert len(name_groups) == 1
    g = name_groups[0]
    # _strip_diacritics("Nguyễn Văn Đức") == "nguyen van duc"
    assert g["key"] == "nguyen van duc"
    assert len(g["customers"]) == 2


def test_duplicates_empty_db_returns_empty_groups(auth_client):
    """FR6 — no customers → empty groups list."""
    headers, _ = _admin_setup(auth_client)
    resp = auth_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["groups"] == []


def test_duplicates_omits_groups_with_single_customer(auth_client):
    """FR6 — a customer with a unique phone and unique name forms no group."""
    headers, _ = _admin_setup(auth_client)
    _create_customer(auth_client, name="Duy nhất", phone="0911999888", headers=headers)

    resp = auth_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["groups"] == []


def test_duplicates_non_admin_returns_403(auth_client):
    """FR6 — staff JWT → 403."""
    staff_token = _seed_staff(auth_client)
    resp = auth_client.get(
        "/api/customers/duplicates", headers=_auth_headers(staff_token)
    )
    assert resp.status_code == 403


def test_duplicates_grace_period_anon_allowed(anon_client):
    """NFR6 — AUTH_REQUIRED=false lets an unauthenticated duplicates request
    through (grace period), matching the other admin-only GET endpoints."""
    resp = anon_client.get("/api/customers/duplicates")
    assert resp.status_code == 200
    assert resp.json()["groups"] == []


# ---------------------------------------------------------------------------
# Duplicates: dedup across kinds (phone + name overlap)
# ---------------------------------------------------------------------------


def test_duplicates_emits_both_phone_and_name_groups_when_sets_differ(auth_client):
    """FR6 — when a phone group and a name group cover different customer
    sets, both groups are emitted. When they cover the exact same set of
    customers under the same kind, only one is emitted."""
    headers, _ = _admin_setup(auth_client)

    # Two customers share a phone but have different names → 1 phone group.
    _create_customer(auth_client, name="Trùng SĐT A", phone="0900", headers=headers)
    _create_customer(auth_client, name="Trùng SĐT B", phone="0900", headers=headers)
    # Two other customers share a name but have different phones → 1 name group.
    _create_customer(auth_client, name="Trùng tên", phone="0911", headers=headers)
    _create_customer(auth_client, name="Trùng tên", phone="0922", headers=headers)

    resp = auth_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200
    groups = resp.json()["groups"]
    phone_groups = [g for g in groups if g["kind"] == "phone"]
    name_groups = [g for g in groups if g["kind"] == "name"]
    assert len(phone_groups) == 1
    assert len(name_groups) == 1
    assert phone_groups[0]["key"] == "0900"
    assert name_groups[0]["key"] == "trung ten"


def test_duplicates_emits_one_group_when_phone_and_name_cover_same_set(auth_client):
    """Mn-4 (DG-252 review) — two customers sharing BOTH the same phone AND
    the same (diacritic-stripped) name should produce exactly one group, not
    two. Phone groups are emitted first and win; the matching name group is
    suppressed by the cross-kind dedupe (set_key excludes ``kind``).
    """
    headers, _ = _admin_setup(auth_client)

    # Two customers sharing both phone and diacritic-stripped name.
    a = _create_customer(auth_client, name="Nguyễn A", phone="0900555777", headers=headers)
    b = _create_customer(auth_client, name="Nguyen A", phone="0900555777", headers=headers)
    _create_order(auth_client, a["id"], a["name"], headers=headers)
    _create_order(auth_client, b["id"], b["name"], headers=headers)
    _create_order(auth_client, b["id"], b["name"], headers=headers)

    resp = auth_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200, resp.text
    groups = resp.json()["groups"]
    # The two customers form one customer set; only the phone group should
    # be emitted (phone wins because phone groups are emitted first).
    matching = [
        g for g in groups
        if {m["id"] for m in g["customers"]} == {a["id"], b["id"]}
    ]
    assert len(matching) == 1, (
        f"expected one group for the shared set, got {len(matching)}: {matching}"
    )
    assert matching[0]["kind"] == "phone"
    # Order counts still accurate after the grouped-query refactor (Mn-6).
    members = {m["id"]: m for m in matching[0]["customers"]}
    assert members[a["id"]]["orderCount"] == 1
    assert members[b["id"]]["orderCount"] == 2


# ---------------------------------------------------------------------------
# DELETE admin-gate + audit-log (Mn-5, DG-252 review)
# ---------------------------------------------------------------------------


def test_delete_customer_non_admin_returns_403(auth_client):
    """Mn-5 — DELETE /api/customers/{id} is admin-only; staff JWT → 403."""
    headers, _ = _admin_setup(auth_client)
    cust = _create_customer(auth_client, name="Xóa", phone="0900", headers=headers)
    staff_token = _seed_staff(auth_client)
    staff_headers = _auth_headers(staff_token)

    resp = auth_client.delete(f"/api/customers/{cust['id']}", headers=staff_headers)
    assert resp.status_code == 403

    # Customer still exists.
    assert auth_client.get(
        f"/api/customers/{cust['id']}", headers=headers
    ).status_code == 200


def test_delete_customer_admin_writes_audit_log(auth_client):
    """Mn-5 — admin DELETE writes an audit_log entry (mirrors merge)."""
    import json

    headers, _ = _admin_setup(auth_client)
    cust = _create_customer(auth_client, name="Xóa audit", phone="0900", headers=headers)

    resp = auth_client.delete(f"/api/customers/{cust['id']}", headers=headers)
    assert resp.status_code == 200

    with get_db() as conn:
        audit = conn.execute(
            "SELECT action, entity_type, entity_id, old_value, new_value "
            "FROM audit_log WHERE entity_type = 'customer' AND action = 'delete' "
            "ORDER BY id DESC LIMIT 1"
        ).fetchone()
    assert audit is not None
    assert audit["entity_id"] == str(cust["id"])
    old = json.loads(audit["old_value"])
    assert old["name"] == "Xóa audit"
    assert audit["new_value"] is None


def test_delete_customer_grace_period_anon_allowed(anon_client):
    """Mn-5 — AUTH_REQUIRED=false lets an unauthenticated delete through
    (grace period), preserving the DG-119 backward-compat baseline."""
    # Seed a customer via the create endpoint (also unauthenticated under
    # grace period).
    created = anon_client.post(
        "/api/customers", json={"name": "Grace xóa", "phone": "0900"}
    ).json()
    resp = anon_client.delete(f"/api/customers/{created['id']}")
    assert resp.status_code == 200
    assert anon_client.get(f"/api/customers/{created['id']}").status_code == 404


# ---------------------------------------------------------------------------
# DG-252 r3 [MAJOR] regression — auto-created customers must materialize
# `customer_phones` rows so the dedup finder sees them and a later merge
# preserves their phone.
# ---------------------------------------------------------------------------


def test_order_auto_created_customer_visible_to_duplicates_finder(api_client):
    """r3 [MAJOR] regression (a) — an order auto-created customer with a
    phone must appear as a `/duplicates` phone group when a manually
    created customer shares the same phone. Before the r3 fix the
    auto-created customer had no `customer_phones` row, so the join in
    `/duplicates` missed it entirely.
    """
    headers, _ = _admin_setup(api_client)

    # Order with an unknown phone+name → auto-create path at
    # orders.py:_resolve_or_create_customer_id. Before r3 this wrote no
    # `customer_phones` row.
    order = api_client.post(
        "/api/orders",
        json={
            "customerName": "Khách tự phát sinh",
            "customerPhone": "0905111222",
            "items": [
                {"productName": "Bánh mì", "quantity": 1, "unitPrice": 10000, "productId": "BMI-01"}
            ],
            "dueDate": "2026-07-01",
        },
    ).json()
    auto_id = order["customerId"]
    assert auto_id is not None

    # Manually created customer with the same phone (populates
    # customer_phones). Placed AFTER the order so the order's resolution
    # cannot match it and must auto-create.
    manual = _create_customer(
        api_client, name="Khách tự thêm", phone="0905111222", headers=headers
    )
    assert manual["id"] != auto_id

    # The auto-created customer must now have a `customer_phones` row.
    with get_db() as conn:
        rows = conn.execute(
            "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ?",
            (auto_id,),
        ).fetchall()
    assert len(rows) == 1, (
        f"auto-created customer must materialize a customer_phones row, "
        f"got {len(rows)} rows"
    )
    assert rows[0]["phone"] == "0905111222"
    assert rows[0]["is_primary"] == 1

    # `/duplicates` must surface the shared phone as one group covering both.
    resp = api_client.get("/api/customers/duplicates", headers=headers)
    assert resp.status_code == 200, resp.text
    phone_groups = [
        g for g in resp.json()["groups"]
        if g["kind"] == "phone" and g["key"] == "0905111222"
    ]
    assert len(phone_groups) == 1, (
        f"expected one phone group for 0905111222, got {len(phone_groups)}"
    )
    members = {m["id"] for m in phone_groups[0]["customers"]}
    assert members == {manual["id"], auto_id}


def test_merge_preserves_auto_created_source_phone_via_customer_phones(api_client):
    """r3 [MAJOR] regression (b) — merging an order-auto-created source
    into a target with a different phone must report `addedPhones == 1`
    and the source phone must survive on the target. Before the r3 fix the
    source's phone lived only in legacy `customers.phone` and was dropped
    on merge, so the next order with that phone would auto-create a fresh
    duplicate — un-doing the merge.
    """
    headers, _ = _admin_setup(api_client)

    # Order auto-creates a source customer with phone A.
    order = api_client.post(
        "/api/orders",
        json={
            "customerName": "Khách tự phát sinh",
            "customerPhone": "0906111333",
            "items": [
                {"productName": "Bánh mì", "quantity": 1, "unitPrice": 10000, "productId": "BMI-01"}
            ],
            "dueDate": "2026-07-01",
        },
    ).json()
    source_id = order["customerId"]
    assert source_id is not None

    # Target with a different phone (created via API so it has a phone row).
    target = _create_customer(
        api_client, name="Khách đích", phone="0908999888", headers=headers
    )

    resp = api_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source_id},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["addedPhones"] == 1, (
        f"merge must copy the auto-created source's phone, got "
        f"addedPhones={body['addedPhones']}"
    )

    # Source phone must survive on the target (in customer_phones).
    with get_db() as conn:
        target_phones = {
            r["phone"]: r["is_primary"]
            for r in conn.execute(
                "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ?",
                (target["id"],),
            ).fetchall()
        }
    assert "0906111333" in target_phones, (
        f"source phone 0906111333 missing from target phones {target_phones}"
    )
    # The target's own primary phone is preserved as primary.
    assert target_phones["0908999888"] == 1


def test_merge_preserves_auto_created_source_phone_legacy_fallback(api_client):
    """r3 [MAJOR] defense-in-depth — even when the source has NO
    `customer_phones` rows (simulating a pre-r3 or pre-v58 customer), the
    merge must copy the legacy `customers.phone` value to the target so
    the phone is not lost. This is the legacy-fallback branch added to
    `_merge_customer_into_target`.
    """
    headers, _ = _admin_setup(api_client)

    # Create a source directly with a legacy phone column and no
    # customer_phones rows (simulating a pre-r3 auto-created customer).
    with get_db() as conn:
        cur = conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES (?, ?, ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            ("Khách cũ", "0907111444", "khach cu"),
        )
        source_id = cur.lastrowid
    target = _create_customer(
        api_client, name="Đích legacy", phone="0908999777", headers=headers
    )

    resp = api_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source_id},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["addedPhones"] == 1

    with get_db() as conn:
        target_phones = {
            r["phone"] for r in conn.execute(
                "SELECT phone FROM customer_phones WHERE customer_id = ?",
                (target["id"],),
            ).fetchall()
        }
    assert "0907111444" in target_phones


# ---------------------------------------------------------------------------
# DG-252 r3 [MINOR] — invariant: a merged customer with phone rows must
# have exactly one primary phone (mirrors CustomerCreate/CustomerUpdate
# validators).
# ---------------------------------------------------------------------------


def test_merge_into_target_with_no_phones_promotes_first_to_primary(api_client):
    """r3 [MINOR] — merging a phone-having source into a target with no
    phone rows must promote the first copied phone to primary so the
    merged customer satisfies the "exactly one primary when non-empty"
    invariant. Before the r3 fix the copied rows all landed with
    is_primary=0.
    """
    headers, _ = _admin_setup(api_client)

    # Target with no phone rows: create via API, then wipe its phones.
    target = _create_customer(
        api_client, name="Đích không SĐT", phone="0900000000", headers=headers
    )
    with get_db() as conn:
        conn.execute(
            "DELETE FROM customer_phones WHERE customer_id = ?", (target["id"],)
        )
        conn.execute(
            "UPDATE customers SET phone = '' WHERE id = ?", (target["id"],)
        )

    # Source with one phone.
    source = _create_customer(
        api_client, name="Nguồn có SĐT", phone="0912333444", headers=headers
    )
    _create_order(api_client, source["id"], source["name"], headers=headers)

    resp = api_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source["id"]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text

    with get_db() as conn:
        rows = conn.execute(
            "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ? "
            "ORDER BY id ASC",
            (target["id"],),
        ).fetchall()
    assert len(rows) >= 1
    primaries = [r for r in rows if r["is_primary"] == 1]
    assert len(primaries) == 1, (
        f"merged customer must have exactly one primary phone, got "
        f"{len(primaries)} out of {len(rows)} rows: {[(r['phone'], r['is_primary']) for r in rows]}"
    )
    assert primaries[0]["phone"] == "0912333444"


# ---------------------------------------------------------------------------
# DG-252 r4 [MAJOR] regression — merge must not drop the target's legacy
# `customers.phone` when the target has zero `customer_phones` rows. Before
# the r4 fix the step-5 overwrite set `customers.phone` to the first source
# phone and the target's original legacy phone was silently lost.
# ---------------------------------------------------------------------------


def test_merge_preserves_target_legacy_phone_when_target_has_no_phone_rows(api_client):
    """r4 [MAJOR] regression — a v66-style target with a legacy
    `customers.phone` and zero `customer_phones` rows, merged with an
    API-created source that has a different phone, must end up with BOTH
    phones present as `customer_phones` rows on the target, and
    `customers.phone` must keep the target's original primary phone
    (not be overwritten by the source's phone).
    """
    headers, _ = _admin_setup(api_client)

    # Target: v66-style row with a legacy phone column and no
    # customer_phones rows (simulating a pre-v58/v66 customer whose phone
    # was never materialized into a row).
    with get_db() as conn:
        cur = conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES (?, ?, ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            ("Khách đích cũ", "0907777000", "khach dich cu"),
        )
        target_id = cur.lastrowid

    # Source: API-created with a different phone (has a customer_phones row).
    source = _create_customer(
        api_client, name="Khách nguồn mới", phone="0912888999", headers=headers
    )
    _create_order(api_client, source["id"], source["name"], headers=headers)

    resp = api_client.post(
        f"/api/customers/{target_id}/merge",
        json={"sourceCustomerId": source["id"]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # The source's phone is added (target had no rows; target's legacy
    # phone is materialized as part of the merge, not counted in
    # addedPhones since addedPhones counts only source-copy inserts).
    assert body["addedPhones"] == 1, (
        f"merge must copy the source's phone, got addedPhones={body['addedPhones']}"
    )

    with get_db() as conn:
        # Both phones must exist as customer_phones rows on the target.
        target_phones = {
            r["phone"]: r["is_primary"]
            for r in conn.execute(
                "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ? "
                "ORDER BY id ASC",
                (target_id,),
            ).fetchall()
        }
        assert set(target_phones) == {"0907777000", "0912888999"}, (
            f"both target legacy and source phones must survive, got {target_phones}"
        )
        # Exactly one primary (invariant).
        primaries = [p for p, ip in target_phones.items() if ip == 1]
        assert len(primaries) == 1, (
            f"merged customer must have exactly one primary, got {target_phones}"
        )
        # The target's original legacy phone stays primary.
        assert target_phones["0907777000"] == 1, (
            f"target's original legacy phone must remain primary, got {target_phones}"
        )
        # customers.phone keeps the target's original primary.
        cust_row = conn.execute(
            "SELECT phone FROM customers WHERE id = ?", (target_id,)
        ).fetchone()
        assert cust_row["phone"] == "0907777000", (
            f"customers.phone must keep the target's original primary, "
            f"got {cust_row['phone']}"
        )


# ---------------------------------------------------------------------------
# DG-252 r4 [MAJOR] migration — v75 backfills a primary customer_phones
# row from non-empty customers.phone for any customer with zero phone rows.
# ---------------------------------------------------------------------------


def test_v75_migration_backfills_primary_phone_from_legacy_column(use_memory_db):
    """r4 [MAJOR] — v75 backfills a primary `customer_phones` row from
    `customers.phone` for every customer with zero phone rows and a
    non-empty legacy phone. Customers with an empty legacy phone or with
    existing phone rows are left untouched.
    """
    from baker.db.connection import get_db
    from baker.db.schema import _migrate_v75_backfill_primary_customer_phones, ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        # Three customers: one with a legacy phone and no rows (should be
        # backfilled), one with an empty phone and no rows (should NOT be
        # backfilled), one with a phone that already has a row (should NOT
        # be double-backfilled).
        cur1 = conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES ('Có legacy', '0910000001', 'co legacy', "
            "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')"
        )
        backfill_id = cur1.lastrowid
        cur2 = conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES ('Trống SĐT', '', 'trong sdt', "
            "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')"
        )
        empty_id = cur2.lastrowid
        cur3 = conn.execute(
            "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
            "VALUES ('Đã có row', '0910000003', 'da co row', "
            "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')"
        )
        already_id = cur3.lastrowid
        conn.execute(
            "INSERT INTO customer_phones (customer_id, phone, is_primary, created_at) "
            "VALUES (?, ?, 0, '2026-01-01T00:00:00Z')",
            (already_id, "0910000003"),
        )

        _migrate_v75_backfill_primary_customer_phones(conn)

        # Backfilled customer: one primary row matching the legacy phone.
        bf_rows = conn.execute(
            "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ?",
            (backfill_id,),
        ).fetchall()
        assert len(bf_rows) == 1, f"expected 1 backfilled row, got {bf_rows}"
        assert bf_rows[0]["phone"] == "0910000001"
        assert bf_rows[0]["is_primary"] == 1

        # Empty-phone customer: still no rows.
        empty_rows = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (empty_id,),
        ).fetchone()[0]
        assert empty_rows == 0, (
            f"empty-phone customer must not be backfilled, got {empty_rows} rows"
        )

        # Already-has-row customer: still exactly one row, unchanged.
        already_rows = conn.execute(
            "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ?",
            (already_id,),
        ).fetchall()
        assert len(already_rows) == 1, (
            f"customer with existing row must not be double-backfilled, "
            f"got {already_rows}"
        )
        assert already_rows[0]["phone"] == "0910000003"

        # Idempotency: a second run inserts nothing.
        before = conn.execute("SELECT COUNT(*) FROM customer_phones").fetchone()[0]
        _migrate_v75_backfill_primary_customer_phones(conn)
        after = conn.execute("SELECT COUNT(*) FROM customer_phones").fetchone()[0]
        assert after == before, (
            f"v75 must be idempotent: before={before}, after={after}"
        )


# ---------------------------------------------------------------------------
# DG-369 Phase 1 — Batch merge endpoint (FR1/FR2/FR3, NFR1, AC2/AC7)
#
# POST /api/customers/{id}/batch-merge accepts sourceCustomerIds: list[int]
# and merges all sources into the target inside a single SQLite transaction.
# Reuses _merge_customer_into_target() per source. Admin-only.
# ---------------------------------------------------------------------------


def test_batch_merge_admin_succeeds_merges_all_sources_atomically(auth_client):
    """FR1/FR2/FR3/AC2 — admin batch-merge of 2 sources into one target
    relinks all orders + phones, recomputes year summary, hard-deletes every
    source, and writes one audit-log entry per source."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích gộp", phone="0901111000", headers=headers)
    src1 = _create_customer(auth_client, name="Nguồn 1", phone="0902222001", headers=headers)
    src2 = _create_customer(auth_client, name="Nguồn 2", phone="0902222002", headers=headers)
    # One order on each source + one on the target.
    _create_order(auth_client, src1["id"], src1["name"], headers=headers)
    _create_order(auth_client, src1["id"], src1["name"], headers=headers)
    _create_order(auth_client, src2["id"], src2["name"], headers=headers)
    _create_order(auth_client, target["id"], target["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src1["id"], src2["id"]]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ok"] is True
    assert body["targetId"] == target["id"]
    assert body["sourceIds"] == [src1["id"], src2["id"]]
    assert body["totalMovedOrders"] == 3
    # 2 source phones added (each unique vs target).
    assert body["totalAddedPhones"] == 2
    # merged list carries per-source detail.
    assert len(body["merged"]) == 2
    by_src = {m["sourceId"]: m for m in body["merged"]}
    assert by_src[src1["id"]]["movedOrders"] == 2
    assert by_src[src2["id"]]["movedOrders"] == 1

    with get_db() as conn:
        # Both sources hard-deleted.
        for sid in (src1["id"], src2["id"]):
            row = conn.execute(
                "SELECT id FROM customers WHERE id = ?", (sid,)
            ).fetchone()
            assert row is None
        # All orders now on the target (1 original + 2 from src1 + 1 from src2).
        target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?",
            (target["id"],),
        ).fetchone()[0]
        assert target_orders == 4
        # Target has 3 phones (1 original + 2 merged), exactly one primary.
        target_phones = conn.execute(
            "SELECT phone, is_primary FROM customer_phones WHERE customer_id = ? "
            "ORDER BY is_primary DESC, id ASC",
            (target["id"],),
        ).fetchall()
        assert {r["phone"] for r in target_phones} == {
            "0901111000",
            "0902222001",
            "0902222002",
        }
        primaries = [r for r in target_phones if r["is_primary"] == 1]
        assert len(primaries) == 1
        # Year summary recomputed for the current year (4 orders x 10000).
        ys = load_year_summary(conn, target["id"], _current_year())
        assert ys["orderCount"] == 4
        assert ys["totalVolume"] == 40000
        # Two audit-log entries (one per source merge).
        audit_rows = conn.execute(
            "SELECT action, entity_type, entity_id FROM audit_log "
            "WHERE entity_type = 'customer' AND action = 'merge' "
            "ORDER BY id DESC LIMIT 2"
        ).fetchall()
        assert len(audit_rows) == 2
        assert all(r["entity_id"] == str(target["id"]) for r in audit_rows)

    # Target is still fetchable via the API.
    get_resp = auth_client.get(f"/api/customers/{target['id']}", headers=headers)
    assert get_resp.status_code == 200


def test_batch_merge_dedupes_overlapping_phones_across_sources(auth_client):
    """FR3 — phones the target already owns or that an earlier source
    contributed are not duplicated across the batch."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0900", headers=headers)
    src1 = _create_customer(auth_client, name="Nguồn 1", phone="0900", headers=headers)  # shares target phone
    src2 = _create_customer(auth_client, name="Nguồn 2", phone="0911", headers=headers)  # unique
    _create_order(auth_client, src1["id"], src1["name"], headers=headers)
    _create_order(auth_client, src2["id"], src2["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src1["id"], src2["id"]]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # Only the unique source phone was added; the shared one was deduped.
    assert body["totalAddedPhones"] == 1

    with get_db() as conn:
        phones = {
            r["phone"]
            for r in conn.execute(
                "SELECT phone FROM customer_phones WHERE customer_id = ?",
                (target["id"],),
            ).fetchall()
        }
        assert phones == {"0900", "0911"}


def test_batch_merge_non_admin_returns_403(auth_client):
    """FR1 — staff JWT → 403, no data changes."""
    admin_headers, _ = _admin_setup(auth_client)
    staff_token = _seed_staff(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0901", headers=admin_headers)
    src = _create_customer(auth_client, name="Nguồn", phone="0902", headers=admin_headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src["id"]]},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403
    # Source still exists.
    assert auth_client.get(
        f"/api/customers/{src['id']}", headers=admin_headers
    ).status_code == 200


def test_batch_merge_self_in_sources_returns_400(auth_client):
    """FR1/AC7 — target id present in sourceCustomerIds → 400."""
    headers, _ = _admin_setup(auth_client)
    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    src = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src["id"], target["id"]]},
        headers=headers,
    )
    assert resp.status_code == 400
    assert resp.json()["detail"] == CUSTOMER_BATCH_MERGE_SELF_MSG
    # No data changes.
    assert auth_client.get(
        f"/api/customers/{src['id']}", headers=headers
    ).status_code == 200


def test_batch_merge_empty_source_list_returns_422(auth_client):
    """FR1 — empty sourceCustomerIds is rejected by the request model (422)."""
    headers, _ = _admin_setup(auth_client)
    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": []},
        headers=headers,
    )
    # Pydantic validator raises 422 (request validation error).
    assert resp.status_code == 422
    assert CUSTOMER_BATCH_MERGE_EMPTY_MSG in resp.text


def test_batch_merge_duplicate_source_ids_returns_422(auth_client):
    """FR1 — duplicate ids in sourceCustomerIds are rejected (422)."""
    headers, _ = _admin_setup(auth_client)
    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    src = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src["id"], src["id"]]},
        headers=headers,
    )
    assert resp.status_code == 422
    assert CUSTOMER_BATCH_MERGE_DUPLICATE_MSG in resp.text


def test_batch_merge_unknown_target_returns_404(auth_client):
    """FR1 — unknown target id → 404."""
    headers, _ = _admin_setup(auth_client)
    src = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)

    resp = auth_client.post(
        "/api/customers/999999/batch-merge",
        json={"sourceCustomerIds": [src["id"]]},
        headers=headers,
    )
    assert resp.status_code == 404
    assert resp.json()["detail"] == CUSTOMER_MERGE_NOT_FOUND_MSG


def test_batch_merge_unknown_source_returns_404(auth_client):
    """FR1 — any unknown source id → 404, no partial merge."""
    headers, _ = _admin_setup(auth_client)
    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    src = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)
    _create_order(auth_client, src["id"], src["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src["id"], 999999]},
        headers=headers,
    )
    assert resp.status_code == 404
    assert resp.json()["detail"] == CUSTOMER_BATCH_MERGE_SOURCE_NOT_FOUND_MSG

    # No data changes: source still exists with its order, target has none.
    with get_db() as conn:
        src_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (src["id"],)
        ).fetchone()[0]
        assert src_orders == 1
        tgt_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (target["id"],)
        ).fetchone()[0]
        assert tgt_orders == 0
    assert auth_client.get(
        f"/api/customers/{src['id']}", headers=headers
    ).status_code == 200


def test_batch_merge_rolls_back_on_failure(auth_client, monkeypatch):
    """NFR1 — a mid-batch exception leaves target, all sources, orders,
    phones, and year summaries unchanged. The whole batch is atomic."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    src1 = _create_customer(auth_client, name="Nguồn 1", phone="0902", headers=headers)
    src2 = _create_customer(auth_client, name="Nguồn 2", phone="0903", headers=headers)
    _create_order(auth_client, src1["id"], src1["name"], headers=headers)
    _create_order(auth_client, src2["id"], src2["name"], headers=headers)

    # Snapshot pre-merge state.
    with get_db() as conn:
        pre_src1_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (src1["id"],)
        ).fetchone()[0]
        pre_src2_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (src2["id"],)
        ).fetchone()[0]
        pre_target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (target["id"],)
        ).fetchone()[0]
        pre_src1_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (src1["id"],),
        ).fetchone()[0]
        pre_src2_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (src2["id"],),
        ).fetchone()[0]

    # Inject a failure into _recompute_customer_year_summary so the batch
    # aborts after the first source merge but before commit. The get_db()
    # context manager must roll the whole transaction back, restoring the
    # second source's orders that the first merge left untouched anyway.
    from baker.api import customers as customers_module

    original_recompute = customers_module._recompute_customer_year_summary
    call_count = {"n": 0}

    def _boom(conn, customer_id, year):
        call_count["n"] += 1
        # Fail on the second invocation (first source's recompute succeeds,
        # second source's recompute raises) so the first merge has mutated
        # state inside the transaction that must be rolled back.
        if call_count["n"] >= 2:
            raise RuntimeError("simulated mid-batch failure")

    monkeypatch.setattr(
        customers_module, "_recompute_customer_year_summary", _boom
    )

    batch_failed = False
    try:
        auth_client.post(
            f"/api/customers/{target['id']}/batch-merge",
            json={"sourceCustomerIds": [src1["id"], src2["id"]]},
            headers=headers,
        )
    except RuntimeError:
        batch_failed = True

    monkeypatch.setattr(
        customers_module, "_recompute_customer_year_summary", original_recompute
    )

    assert batch_failed, "batch merge should have failed mid-transaction"

    with get_db() as conn:
        # Both sources still exist (hard-delete rolled back).
        for sid in (src1["id"], src2["id"]):
            row = conn.execute(
                "SELECT id FROM customers WHERE id = ?", (sid,)
            ).fetchone()
            assert row is not None
        # Orders unchanged on every customer.
        post_src1_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (src1["id"],)
        ).fetchone()[0]
        post_src2_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (src2["id"],)
        ).fetchone()[0]
        post_target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?", (target["id"],)
        ).fetchone()[0]
        assert post_src1_orders == pre_src1_orders
        assert post_src2_orders == pre_src2_orders
        assert post_target_orders == pre_target_orders
        # Phones unchanged on both sources.
        post_src1_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (src1["id"],),
        ).fetchone()[0]
        post_src2_phones = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (src2["id"],),
        ).fetchone()[0]
        assert post_src1_phones == pre_src1_phones
        assert post_src2_phones == pre_src2_phones
        # No audit-log entries committed.
        audit = conn.execute(
            "SELECT COUNT(*) FROM audit_log WHERE entity_type = 'customer' "
            "AND action = 'merge'"
        ).fetchone()[0]
        assert audit == 0


def test_batch_merge_existing_single_pair_endpoint_unchanged(auth_client):
    """NFR2 — the existing POST /api/customers/{id}/merge endpoint continues
    to work unchanged alongside the new batch endpoint."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    source = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)
    _create_order(auth_client, source["id"], source["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/merge",
        json={"sourceCustomerId": source["id"]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["ok"] is True
    assert body["targetId"] == target["id"]
    assert body["sourceId"] == source["id"]
    assert body["movedOrders"] == 1
    # Single-pair response shape unchanged: no batch fields.
    assert "sourceIds" not in body
    assert "merged" not in body


def test_batch_merge_grace_period_anon_allowed_when_auth_required_false(anon_client):
    """NFR6 — AUTH_REQUIRED=false (grace period) lets an unauthenticated
    batch merge request through, mirroring the single-pair merge endpoint."""
    target = _create_customer(anon_client, name="Đích", phone="0901")
    src = _create_customer(anon_client, name="Nguồn", phone="0902")
    _create_order(anon_client, src["id"], src["name"])

    resp = anon_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src["id"]]},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["totalMovedOrders"] == 1


def test_batch_merge_single_source_succeeds(auth_client):
    """FR1 — a batch with one source works (degenerate case of the batch)."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích", phone="0901", headers=headers)
    src = _create_customer(auth_client, name="Nguồn", phone="0902", headers=headers)
    _create_order(auth_client, src["id"], src["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": [src["id"]]},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["totalMovedOrders"] == 1
    assert body["sourceIds"] == [src["id"]]

    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM customers WHERE id = ?", (src["id"],)
        ).fetchone()
        assert row is None


def test_batch_merge_ten_sources_completes(auth_client):
    """NFR3 — batch merge of 10 sources completes within one transaction."""
    headers, _ = _admin_setup(auth_client)

    target = _create_customer(auth_client, name="Đích 10", phone="0900000000", headers=headers)
    source_ids: list[int] = []
    for i in range(10):
        s = _create_customer(
            auth_client,
            name=f"Nguồn {i}",
            phone=f"090{i:07d}",
            headers=headers,
        )
        source_ids.append(s["id"])
        _create_order(auth_client, s["id"], s["name"], headers=headers)

    resp = auth_client.post(
        f"/api/customers/{target['id']}/batch-merge",
        json={"sourceCustomerIds": source_ids},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["totalMovedOrders"] == 10
    assert len(body["merged"]) == 10

    with get_db() as conn:
        remaining_sources = conn.execute(
            "SELECT COUNT(*) FROM customers WHERE id IN (%s)"
            % ",".join("?" * len(source_ids)),
            source_ids,
        ).fetchone()[0]
        assert remaining_sources == 0
        target_orders = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id = ?",
            (target["id"],),
        ).fetchone()[0]
        assert target_orders == 10
