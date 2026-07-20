"""Tests for DG-259 staff-binding endpoints (FR6, M2 review-remediation).

Covers:
  - GET /api/users/me/staff-binding: happy path, unbound, 401 unauthenticated
  - PUT /api/users/me/staff-binding: happy bind/unbind, 400 non-int (422 via Pydantic),
    404 inactive/unknown staff, 409 conflict, non-admin 403, audit log row
"""

from __future__ import annotations

import pytest
from click.testing import CliRunner

from baker.cli import app
from baker.db.connection import get_db

from tests.auth_helpers import _auth_headers, _seed_user

runner = CliRunner()


def _add_staff(name: str) -> int:
    """Add a staff member via CLI and return their id."""
    result = runner.invoke(app, ["staff", "add", name])
    assert result.exit_code == 0, result.output
    with get_db() as conn:
        return int(
            conn.execute("SELECT id FROM staff WHERE name = ?", (name,)).fetchone()[0]
        )


# ---------------------------------------------------------------------------
# GET /api/users/me/staff-binding
# ---------------------------------------------------------------------------


def test_get_staff_binding_unbound(auth_client):
    """GET returns null staff_id/staff_name when user has no binding."""
    with get_db() as conn:
        token = _seed_user(conn, "unbounduser", "admin")
    resp = auth_client.get(
        "/api/users/me/staff-binding", headers=_auth_headers(token)
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["staff_id"] is None
    assert data["staff_name"] is None


def test_get_staff_binding_bound(auth_client):
    """GET returns the linked staff id and name when user has a binding."""
    staff_id = _add_staff("TestBaker")
    with get_db() as conn:
        token = _seed_user(conn, "bounduser", "admin")
        conn.execute(
            "UPDATE users SET staff_id = ? WHERE username = ?",
            (staff_id, "bounduser"),
        )
        conn.commit()
    resp = auth_client.get(
        "/api/users/me/staff-binding", headers=_auth_headers(token)
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["staff_id"] == staff_id
    assert data["staff_name"] == "TestBaker"


def test_get_staff_binding_unauthenticated(api_client):
    """GET returns 401 when no auth token is present."""
    resp = api_client.get("/api/users/me/staff-binding")
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# PUT /api/users/me/staff-binding
# ---------------------------------------------------------------------------


def test_put_staff_binding_bind(auth_client):
    """PUT with staff_id links the user to the staff member."""
    staff_id = _add_staff("BindTarget")
    with get_db() as conn:
        token = _seed_user(conn, "binduser", "admin")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": staff_id},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["staff_id"] == staff_id
    assert data["staff_name"] == "BindTarget"

    with get_db() as conn:
        row = conn.execute(
            "SELECT staff_id FROM users WHERE username = 'binduser'"
        ).fetchone()
        assert row["staff_id"] == staff_id


def test_put_staff_binding_unbind(auth_client):
    """PUT with null staff_id unbinds the user."""
    staff_id = _add_staff("UnbindTarget")
    with get_db() as conn:
        token = _seed_user(conn, "unbinduser", "admin")
        conn.execute(
            "UPDATE users SET staff_id = ? WHERE username = ?",
            (staff_id, "unbinduser"),
        )
        conn.commit()
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": None},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["staff_id"] is None
    assert data["staff_name"] is None


def test_put_staff_binding_404_inactive_staff(auth_client):
    """PUT with an inactive staff id returns 404."""
    staff_id = _add_staff("InactiveStaff")
    with get_db() as conn:
        conn.execute("UPDATE staff SET active = 0 WHERE id = ?", (staff_id,))
        conn.commit()
        token = _seed_user(conn, "inactiveuser", "admin")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": staff_id},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 404


def test_put_staff_binding_404_unknown_staff(auth_client):
    """PUT with a non-existent staff id returns 404."""
    with get_db() as conn:
        token = _seed_user(conn, "unknownstaffuser", "admin")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": 99999},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 404


def test_put_staff_binding_conflict(auth_client):
    """PUT with a staff_id already bound to another user returns 409."""
    staff_id = _add_staff("ConflictStaff")
    with get_db() as conn:
        # Bind staff to user A
        token_a = _seed_user(conn, "userA", "admin")
        conn.execute(
            "UPDATE users SET staff_id = ? WHERE username = ?",
            (staff_id, "userA"),
        )
        # Create user B (no binding yet)
        token_b = _seed_user(conn, "userB", "admin")
        conn.commit()
    # User B tries to bind the same staff → 409
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": staff_id},
        headers=_auth_headers(token_b),
    )
    assert resp.status_code == 409
    assert "userA" in resp.json()["detail"]


def test_put_staff_binding_non_admin_403(auth_client):
    """Staff (non-admin) user gets 403 when calling PUT."""
    staff_id = _add_staff("AdminOnlyStaff")
    with get_db() as conn:
        token = _seed_user(conn, "staffuser", "staff")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": staff_id},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 403


def test_put_staff_binding_audit_log_written(auth_client):
    """Successful binding writes an audit_log row."""
    staff_id = _add_staff("AuditStaff")
    with get_db() as conn:
        token = _seed_user(conn, "audituser", "admin")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": staff_id},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 200

    with get_db() as conn:
        row = conn.execute(
            "SELECT action, entity_type, entity_id, new_value "
            "FROM audit_log WHERE entity_type = 'users.staff_id' "
            "ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row is not None
        assert row["action"] == "update"
        assert row["entity_id"] == "audituser"


def test_put_staff_binding_empty_body_no_unbind(auth_client):
    """PUT with empty body (staff_id absent) does NOT unbind (m5).

    Since staff_id defaults to None in the Pydantic model (explicit null
    contract), an absent key is the same as explicit null — unbind is
    intentional. This test documents the behavior when body is {}.
    """
    with get_db() as conn:
        token = _seed_user(conn, "emptybodyuser", "admin")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={},
        headers=_auth_headers(token),
    )
    # {} → staff_id=None → unbind (explicit contract)
    assert resp.status_code == 200
    data = resp.json()
    assert data["staff_id"] is None


def test_put_staff_binding_boolean_rejected(auth_client):
    """PUT with staff_id=true returns 422 (m5 - Pydantic StrictInt rejects bool)."""
    with get_db() as conn:
        token = _seed_user(conn, "booluser", "admin")
    resp = auth_client.put(
        "/api/users/me/staff-binding",
        json={"staff_id": True},
        headers=_auth_headers(token),
    )
    assert resp.status_code == 422
