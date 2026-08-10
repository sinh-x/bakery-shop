"""Tests for Baker API — message template endpoints (DG-375 Phase 4.1).

Covers:
  - FR1: GET /api/templates returns seeded templates grouped by scenario
  - FR4: template body stored with placeholder syntax (raw verbatim)
  - FR6: admin CRUD for system templates (POST/PATCH/DELETE)
  - FR7: staff CRUD for personal templates (scoped to owning staff)
  - FR9: 8 default templates seeded across 6 scenarios
  - FR10: management API accessible
  - AC9 (DB-level): default templates present after migration
  - NFR3: default templates seeded at migration time
  - DG-202 TC-6: created_at / updated_at are Z-suffixed UTC
"""

from __future__ import annotations

from datetime import datetime

import pytest

from baker.db.connection import get_db
from tests.auth_helpers import _auth_headers, _seed_user

pytestmark = pytest.mark.critical


# ── Helpers ──────────────────────────────────────────────────────────────────


def _seed_staff_user(conn, username: str, staff_name: str, staff_role: str = "thu-ngan", user_role: str = "staff") -> str:
    """Create a staff row + linked user, return a JWT for that user."""
    conn.execute(
        "INSERT INTO staff (name, role) VALUES (?, ?)",
        (staff_name, staff_role),
    )
    staff_id = int(conn.execute(
        "SELECT id FROM staff WHERE name = ?", (staff_name,)
    ).fetchone()["id"])
    conn.execute(
        "INSERT INTO users (username, password_hash, role, active, staff_id) "
        "VALUES (?, ?, ?, 1, ?)",
        (username, "x", user_role, staff_id),
    )
    conn.commit()
    from tests.auth_helpers import _make_token
    return _make_token(username, user_role)


def _create_template(api_client, scenario="ask_info", name="Test tmpl", body="Xin chào {customer_name}", **kw):
    payload = {"scenario": scenario, "name": name, "body": body, **kw}
    resp = api_client.post("/api/templates", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


# ── Seed data (FR9 / AC9 / NFR3) ─────────────────────────────────────────────


def test_list_templates_seeds_present(api_client):
    """FR9/AC9: 8 default templates seeded across 6 scenarios."""
    resp = api_client.get("/api/templates")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) >= 8, f"expected >=8 seeded templates, got {len(data)}"
    scenarios = {t["scenario"] for t in data}
    expected = {"ask_info", "confirm_order", "final_message", "follow_up", "status_update", "payment_request"}
    assert expected.issubset(scenarios), f"missing scenarios: {expected - scenarios}"
    # All seeded templates are system templates
    seeded = [t for t in data if t["is_system"]]
    assert len(seeded) >= 8


def test_list_templates_grouped_by_scenario(api_client):
    """FR1: templates returned ordered by scenario for client grouping."""
    resp = api_client.get("/api/templates")
    data = resp.json()
    scenarios = [t["scenario"] for t in data]
    assert scenarios == sorted(scenarios), "templates not ordered by scenario"


def test_list_templates_filter_by_scenario(api_client):
    """FR1: scenario query filter works."""
    resp = api_client.get("/api/templates?scenario=confirm_order")
    assert resp.status_code == 200
    data = resp.json()
    assert all(t["scenario"] == "confirm_order" for t in data)
    # 3 confirm_order variants seeded
    assert len(data) >= 3


def test_list_templates_invalid_scenario_400(api_client):
    resp = api_client.get("/api/templates?scenario=not_a_scenario")
    assert resp.status_code == 400


def test_seed_template_body_has_placeholders(api_client):
    """FR4: seeded template bodies contain placeholder syntax."""
    resp = api_client.get("/api/templates?scenario=confirm_order")
    data = resp.json()
    # The Pickup variant references {public_order_code}, {items_list}, {total_price}, {due_date}, {due_time}
    pickup = next(t for t in data if "Pickup" in t["name"])
    assert "{public_order_code}" in pickup["body"]
    assert "{items_list}" in pickup["body"]
    assert "{total_price}" in pickup["body"]


# ── Create (FR6 / FR7) ───────────────────────────────────────────────────────


def test_create_personal_template_staff(auth_client):
    """FR7: staff can create personal templates (is_system=false, owned)."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "stafftmpl", "Nhân Viên Mẫu")

    resp = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "My ask", "body": "Hello {customer_name}"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["is_system"] is False
    assert data["created_by_staff_id"] is not None
    assert data["scenario"] == "ask_info"
    assert data["body"] == "Hello {customer_name}"


def test_create_system_template_admin(auth_client):
    """FR6: admin can create system templates."""
    with get_db() as conn:
        token = _seed_user(conn, "admintmpl", "admin")

    resp = auth_client.post(
        "/api/templates",
        json={"scenario": "follow_up", "name": "Sys follow", "body": "Cảm ơn", "is_system": True},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["is_system"] is True
    assert data["created_by_staff_id"] is None


def test_staff_cannot_create_system_template_403(auth_client):
    """FR6: staff blocked from creating system templates."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "staffsys", "Nhân Viên Sys")

    resp = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "Sys by staff", "body": "x", "is_system": True},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 403


def test_create_template_invalid_scenario_400(api_client):
    resp = api_client.post(
        "/api/templates",
        json={"scenario": "bad", "name": "x", "body": "y"},
    )
    assert resp.status_code == 400


def test_two_staff_can_create_personal_with_same_name(auth_client):
    """FR7: the unique index is scoped to system templates only, so two
    staff members may each create a personal template with the same name."""
    with get_db() as conn:
        token_a = _seed_staff_user(conn, "sameNameA", "Nhân Viên SameA")
        token_b = _seed_staff_user(conn, "sameNameB", "Nhân Viên SameB")

    for token in (token_a, token_b):
        resp = auth_client.post(
            "/api/templates",
            json={"scenario": "ask_info", "name": "Same Name", "body": "x"},
            headers=_auth_headers(token),
        )
        assert resp.status_code == 201, resp.text


# ── List visibility (FR7 scoping) ────────────────────────────────────────────


def test_list_returns_system_plus_own_personal(auth_client):
    """FR7: staff sees system templates + their own personal templates only."""
    with get_db() as conn:
        token_a = _seed_staff_user(conn, "staffa", "Nhân Viên A")
        token_b = _seed_staff_user(conn, "staffb", "Nhân Viên B")

    # A creates a personal template
    resp = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "A's tmpl", "body": "from A"},
        headers=_auth_headers(token_a),
    )
    assert resp.status_code == 201
    a_id = resp.json()["id"]

    # A sees it
    resp = auth_client.get("/api/templates", headers=_auth_headers(token_a))
    a_ids = [t["id"] for t in resp.json()]
    assert a_id in a_ids

    # B does NOT see A's personal template
    resp = auth_client.get("/api/templates", headers=_auth_headers(token_b))
    b_ids = [t["id"] for t in resp.json()]
    assert a_id not in b_ids


# ── Update (FR6 / FR7) ───────────────────────────────────────────────────────


def test_update_personal_template_owner(auth_client):
    """FR7: staff can update their own personal template."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "staffupd", "Nhân Viên Upd")

    created = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "Old", "body": "old body"},
        headers=_auth_headers(token),
    ).json()

    resp = auth_client.patch(
        f"/api/templates/{created['id']}",
        json={"name": "New", "body": "new body"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["name"] == "New"
    assert data["body"] == "new body"
    assert data["scenario"] == "ask_info"  # unchanged


def test_update_template_not_found_404(auth_client):
    with get_db() as conn:
        token = _seed_user(conn, "adminupd", "admin")
    resp = auth_client.patch(
        "/api/templates/99999",
        json={"name": "X"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 404


def test_staff_cannot_update_system_template_403(auth_client):
    """FR6: staff cannot update system templates."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "staffsysupd", "Nhân Viên SysUpd")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]

    resp = auth_client.patch(
        f"/api/templates/{sys_id}",
        json={"name": "Hacked"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 403


def test_staff_cannot_update_other_staff_personal_403(auth_client):
    """FR7: staff cannot update another staff's personal template."""
    with get_db() as conn:
        token_a = _seed_staff_user(conn, "ownera", "Nhân Viên OwnerA")
        token_b = _seed_staff_user(conn, "otherb", "Nhân Viên OtherB")

    created = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "A's", "body": "a"},
        headers=_auth_headers(token_a),
    ).json()

    resp = auth_client.patch(
        f"/api/templates/{created['id']}",
        json={"name": "B hacked"},
        headers=_auth_headers(token_b),
    )
    assert resp.status_code == 403


def test_admin_can_update_system_template(auth_client):
    """FR6: admin can update system templates."""
    with get_db() as conn:
        token = _seed_user(conn, "adminsysupd", "admin")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]

    resp = auth_client.patch(
        f"/api/templates/{sys_id}",
        json={"name": "Updated by admin"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    assert resp.json()["name"] == "Updated by admin"


def test_staff_cannot_promote_personal_to_system_403(auth_client):
    """FR6: staff cannot set is_system=true on their personal template."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "staffpromote", "Nhân Viên Promote")

    created = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "mine", "body": "x"},
        headers=_auth_headers(token),
    ).json()

    resp = auth_client.patch(
        f"/api/templates/{created['id']}",
        json={"is_system": True},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 403


def test_update_invalid_scenario_400(auth_client):
    with get_db() as conn:
        token = _seed_user(conn, "adminbad", "admin")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]
    resp = auth_client.patch(
        f"/api/templates/{sys_id}",
        json={"scenario": "bad"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 400


# ── Delete (FR6 / FR7) ───────────────────────────────────────────────────────


def test_delete_personal_template_owner(auth_client):
    """FR7: staff can delete their own personal template."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "staffdel", "Nhân Viên Del")

    created = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "To delete", "body": "x"},
        headers=_auth_headers(token),
    ).json()

    resp = auth_client.delete(
        f"/api/templates/{created['id']}",
        headers=_auth_headers(token),
    )
    assert resp.status_code == 204

    # Verify gone
    resp = auth_client.get("/api/templates", headers=_auth_headers(token))
    ids = [t["id"] for t in resp.json()]
    assert created["id"] not in ids


def test_delete_template_not_found_404(auth_client):
    with get_db() as conn:
        token = _seed_user(conn, "admindel", "admin")
    resp = auth_client.delete(
        "/api/templates/99999",
        headers=_auth_headers(token),
    )
    assert resp.status_code == 404


def test_staff_cannot_delete_system_template_403(auth_client):
    """FR6: staff cannot delete system templates."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "staffsysdel", "Nhân Viên SysDel")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]

    resp = auth_client.delete(
        f"/api/templates/{sys_id}",
        headers=_auth_headers(token),
    )
    assert resp.status_code == 403


def test_admin_can_delete_system_template(auth_client):
    """FR6: admin can delete a system template."""
    with get_db() as conn:
        token = _seed_user(conn, "adminsysdel", "admin")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]

    resp = auth_client.delete(
        f"/api/templates/{sys_id}",
        headers=_auth_headers(token),
    )
    assert resp.status_code == 204


def test_staff_cannot_delete_other_staff_personal_403(auth_client):
    """FR7: staff cannot delete another staff's personal template."""
    with get_db() as conn:
        token_a = _seed_staff_user(conn, "delownera", "Nhân Viên DelOwnerA")
        token_b = _seed_staff_user(conn, "delotherb", "Nhân Viên DelOtherB")

    created = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "A's", "body": "a"},
        headers=_auth_headers(token_a),
    ).json()

    resp = auth_client.delete(
        f"/api/templates/{created['id']}",
        headers=_auth_headers(token_b),
    )
    assert resp.status_code == 403


# ── Timestamp format (DG-202 TC-6) ───────────────────────────────────────────


def test_template_created_at_is_z_suffixed(auth_client):
    """TC-6: created_at on created template is Z-suffixed UTC."""
    with get_db() as conn:
        token = _seed_user(conn, "tsadmin", "admin")

    resp = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "TS tmpl", "body": "x", "is_system": True},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201
    created_at = resp.json()["created_at"]
    assert created_at.endswith("Z")
    assert "+" not in created_at
    datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ")


def test_template_updated_at_is_z_suffixed(auth_client):
    """TC-6: updated_at is Z-suffixed UTC and changes on update."""
    with get_db() as conn:
        token = _seed_user(conn, "tsupdadmin", "admin")

    created = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "TS upd", "body": "x", "is_system": True},
        headers=_auth_headers(token),
    ).json()
    original_updated = created["updated_at"]

    resp = auth_client.patch(
        f"/api/templates/{created['id']}",
        json={"name": "TS upd 2"},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    updated_at = resp.json()["updated_at"]
    assert updated_at.endswith("Z")
    assert "+" not in updated_at
    datetime.strptime(updated_at, "%Y-%m-%dT%H:%M:%SZ")
    assert updated_at >= original_updated


# ── Audit log (FR22) ─────────────────────────────────────────────────────────


def test_audit_log_recorded_on_template_create(auth_client):
    """FR22: admin create records an audit_log row."""
    with get_db() as conn:
        token = _seed_user(conn, "auditadmin", "admin")

    resp = auth_client.post(
        "/api/templates",
        json={"scenario": "ask_info", "name": "Audited", "body": "x", "is_system": True},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201

    with get_db() as conn:
        rows = conn.execute("SELECT * FROM audit_log WHERE entity_type = 'message_template'").fetchall()
        matches = [r for r in rows if r["action"] == "create"]
        assert matches, f"no message_template create audit row found; rows={rows}"


def test_audit_log_recorded_on_template_delete(auth_client):
    """FR22: admin delete records an audit_log row."""
    with get_db() as conn:
        token = _seed_user(conn, "auditdeladmin", "admin")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]

    resp = auth_client.delete(
        f"/api/templates/{sys_id}",
        headers=_auth_headers(token),
    )
    assert resp.status_code == 204

    with get_db() as conn:
        rows = conn.execute("SELECT * FROM audit_log WHERE entity_type = 'message_template'").fetchall()
        matches = [r for r in rows if r["action"] == "delete"]
        assert matches, f"no message_template delete audit row found; rows={rows}"

# ── SEC-SetClause (review cycle 1) ───────────────────────────────────────────


def test_update_template_allows_known_fields(auth_client):
    """SEC-SetClause: a normal admin update with allowed fields succeeds.

    This pins that ``ALLOWED_UPDATE_FIELDS`` does not reject the legitimate
    fields produced by ``TemplateUpdate`` (name, sort_order, active).
    """
    with get_db() as conn:
        token = _seed_user(conn, "setclauseadmin", "admin")
        sys_id = conn.execute(
            "SELECT id FROM message_templates WHERE is_system = 1 LIMIT 1"
        ).fetchone()["id"]

    resp = auth_client.patch(
        f"/api/templates/{sys_id}",
        json={"name": "Renamed by admin", "sort_order": 99, "active": False},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["name"] == "Renamed by admin"
    assert data["sort_order"] == 99
    assert data["active"] is False


def test_allowed_update_fields_is_strict_allowlist():
    """SEC-SetClause: ALLOWED_UPDATE_FIELDS contains exactly the columns the
    route may legitimately build, and nothing else.

    Any key outside this set would be concatenated into raw SQL by the
    dynamic SET clause, so the allowlist must not grow accidentally.
    """
    from baker.api.templates import ALLOWED_UPDATE_FIELDS

    assert ALLOWED_UPDATE_FIELDS == {
        "scenario",
        "name",
        "body",
        "is_system",
        "sort_order",
        "active",
        "updated_at",
    }
    # Sanity: no dangerous meta-columns are allowed.
    assert "id" not in ALLOWED_UPDATE_FIELDS
    assert "created_at" not in ALLOWED_UPDATE_FIELDS
    assert "created_by_staff_id" not in ALLOWED_UPDATE_FIELDS
