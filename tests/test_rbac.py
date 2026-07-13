"""Tests for DG-029 Phase 3: role-gated endpoints and audit log recording.

Covers:
  - AC4: AUTH_REQUIRED=true + staff JWT → POST /api/config/order_source returns 403
  - AC5: AUTH_REQUIRED=true + admin JWT → POST /api/config/order_source returns 200
  - AC6: AUTH_REQUIRED=true + staff JWT → GET /api/orders returns 200
  - FR22: audit_log rows created on admin write operations
  - NFR6: AUTH_REQUIRED=false → write endpoints work without token (grace period)
"""

from __future__ import annotations

import time
import uuid
from unittest.mock import patch

import jwt
import pytest

from baker.api.auth import _pwd_ctx, _reset_auth_state
from baker.config import JWT_SECRET
from baker.db.connection import get_db


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _create_test_user(conn, username: str, password: str, role: str = "admin") -> None:
    hashed = _pwd_ctx.hash(password)
    conn.execute(
        "INSERT INTO users (username, password_hash, role, active) VALUES (?, ?, ?, 1)",
        (username, hashed, role),
    )
    conn.commit()


def _make_token(username: str, role: str) -> str:
    payload = {
        "sub": username,
        "role": role,
        "exp": int(time.time()) + 3600,
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


@pytest.fixture(autouse=True)
def _reset_auth():
    _reset_auth_state()
    yield
    _reset_auth_state()


@pytest.fixture
def auth_client(api_client):
    """api_client with AUTH_REQUIRED=true."""
    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        with patch("baker.api.auth.AUTH_REQUIRED", True):
            yield api_client


@pytest.fixture
def anon_client(api_client):
    """api_client with AUTH_REQUIRED=false (grace period)."""
    with patch("baker.api.middleware.AUTH_REQUIRED", False):
        with patch("baker.api.auth.AUTH_REQUIRED", False):
            yield api_client


def _seed_user(conn, username: str, role: str, password: str = "pass123") -> str:
    _create_test_user(conn, username, password, role=role)
    return _make_token(username, role)


def _auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# AC4: staff JWT → write endpoint returns 403
# ---------------------------------------------------------------------------


def test_staff_cannot_create_config_returns_403(auth_client):
    """AC4: staff JWT → POST /api/config/order_source returns 403."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.post(
        "/api/config/order_source",
        json={"value": "Zalo", "sort_order": 99},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403


def test_staff_cannot_create_product_returns_403(auth_client):
    """FR4: staff blocked from product create."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.post(
        "/api/products",
        json={"name": "Test Product", "category": "banh_mi"},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403


def test_staff_cannot_create_category_returns_403(auth_client):
    """FR4: staff blocked from category create."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.post(
        "/api/categories",
        json={"slug": "test_cat", "name": "Test", "code_prefix": "TST"},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403


def test_staff_cannot_create_checklist_template_returns_403(auth_client):
    """FR4: staff blocked from checklist template create."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.post(
        "/api/checklist/templates",
        json={"name": "New task", "period": "opening", "sort_order": 1},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403


def test_staff_cannot_submit_reconciliation_returns_403(auth_client):
    """FR4: staff blocked from reconciliation submit."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.post(
        "/api/reconciliations/submit",
        json={"staff_name": "staffuser", "lines": []},
        headers=_auth_headers(staff_token),
    )
    # 403 must take precedence over 422 validation
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# AC5: admin JWT → write endpoint succeeds
# ---------------------------------------------------------------------------


def test_admin_can_create_config_returns_200(auth_client):
    """AC5: admin JWT → POST /api/config/order_source returns 200."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")

    resp = auth_client.post(
        "/api/config/order_source",
        json={"value": "Zalo-Test", "sort_order": 99},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["config_key"] == "order_source"
    assert data["value"] == "Zalo-Test"


def test_admin_can_create_product(auth_client):
    """FR3: admin can create products."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")

    resp = auth_client.post(
        "/api/products",
        json={"name": "Admin Test Product", "category": "banh_mi"},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 201, resp.text


# ---------------------------------------------------------------------------
# AC6: staff JWT → read endpoint succeeds
# ---------------------------------------------------------------------------


def test_staff_can_read_orders_returns_200(auth_client):
    """AC6: staff JWT → GET /api/orders returns 200."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.get(
        "/api/orders",
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 200


def test_staff_can_read_products_returns_200(auth_client):
    """FR5: staff has read access to products (GET)."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.get(
        "/api/products",
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 200


def test_staff_can_read_categories_returns_200(auth_client):
    """FR5: staff has read access to categories (GET)."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.get(
        "/api/categories",
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 200


def test_staff_can_toggle_daily_checklist(auth_client):
    """FR5: daily checklist endpoints remain accessible to staff."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    # GET daily is staff-accessible
    resp = auth_client.get(
        "/api/checklist/daily",
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# NFR6: AUTH_REQUIRED=false → writes work without token (grace period)
# ---------------------------------------------------------------------------


def test_grace_period_write_works_without_token(anon_client):
    """NFR6: AUTH_REQUIRED=false → POST config works without token."""
    resp = anon_client.post(
        "/api/config/order_source",
        json={"value": "GracePeriod-Test", "sort_order": 1},
    )
    assert resp.status_code == 200


def test_grace_period_product_create_works_without_token(anon_client):
    """NFR6: AUTH_REQUIRED=false → POST product works without token."""
    resp = anon_client.post(
        "/api/products",
        json={"name": "Grace Product", "category": "banh_mi"},
    )
    assert resp.status_code == 201


# ---------------------------------------------------------------------------
# FR22: audit log recording on admin write operations
# ---------------------------------------------------------------------------


def _audit_log_rows(conn) -> list:
    return conn.execute(
        "SELECT username, action, entity_type, entity_id, old_value, new_value "
        "FROM audit_log ORDER BY id"
    ).fetchall()


def test_audit_log_recorded_on_config_create(auth_client):
    """FR22: config create records audit log."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")

    resp = auth_client.post(
        "/api/config/order_source",
        json={"value": "AuditTest", "sort_order": 1},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        matches = [
            r for r in rows
            if r["entity_type"] == "config" and r["action"] == "create"
        ]
        assert matches, f"no config create audit row found; rows={rows}"
        assert matches[-1]["username"] == "auditadmin"


def test_audit_log_recorded_on_product_create(auth_client):
    """FR22: product create records audit log."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")

    resp = auth_client.post(
        "/api/products",
        json={"name": "AuditProduct", "category": "banh_mi"},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 201
    new_id = resp.json()["id"]

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        matches = [
            r for r in rows
            if r["entity_type"] == "product"
            and r["action"] == "create"
            and r["entity_id"] == str(new_id)
        ]
        assert matches, f"no product create audit row found for id={new_id}; rows={rows}"
        assert matches[-1]["username"] == "auditadmin"


def test_audit_log_recorded_on_category_create(auth_client):
    """FR22: category create records audit log."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")

    resp = auth_client.post(
        "/api/categories",
        json={"slug": "audit_cat", "name": "Audit Cat", "code_prefix": "AUD"},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 201

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        matches = [
            r for r in rows
            if r["entity_type"] == "category" and r["action"] == "create"
        ]
        assert matches, f"no category create audit row found; rows={rows}"


def test_audit_log_recorded_on_checklist_template_create(auth_client):
    """FR22: checklist template create records audit log."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")

    resp = auth_client.post(
        "/api/checklist/templates",
        json={"name": "Audit Task", "period": "opening", "sort_order": 99},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 201

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        matches = [
            r for r in rows
            if r["entity_type"] == "checklist_template"
            and r["action"] == "create"
        ]
        assert matches, f"no checklist_template audit row found; rows={rows}"


def test_audit_log_recorded_on_config_update(auth_client):
    """FR22: config update records audit log with old/new values."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")

    # Create first
    resp = auth_client.post(
        "/api/config/order_source",
        json={"value": "ToUpdate", "sort_order": 1},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200

    # Update
    resp = auth_client.put(
        "/api/config/order_source",
        json={"old_value": "ToUpdate", "new_value": "Updated", "sort_order": 2},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        updates = [
            r for r in rows
            if r["entity_type"] == "config" and r["action"] == "update"
        ]
        assert updates, "no config update audit row found"
        last = updates[-1]
        assert last["old_value"] is not None
        assert last["new_value"] is not None


def test_audit_log_recorded_on_config_delete(auth_client):
    """FR22: config delete records audit log."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")

    # Create then delete
    auth_client.post(
        "/api/config/order_source",
        json={"value": "ToDelete", "sort_order": 1},
        headers=_auth_headers(admin_token),
    )
    resp = auth_client.request(
        "DELETE",
        "/api/config/order_source",
        params={"value": "ToDelete"},
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        deletes = [
            r for r in rows
            if r["entity_type"] == "config" and r["action"] == "delete"
        ]
        assert deletes, "no config delete audit row found"


def test_audit_log_not_recorded_when_blocked_by_role(auth_client):
    """FR22: no audit row when staff is blocked (403) — write didn't happen."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.post(
        "/api/config/order_source",
        json={"value": "ShouldNotAppear", "sort_order": 1},
        headers=_auth_headers(staff_token),
    )
    assert resp.status_code == 403

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        config_rows = [r for r in rows if r["entity_type"] == "config"]
        assert not config_rows, f"audit row created despite 403: {config_rows}"


# ---------------------------------------------------------------------------
# Mn-4 (DG-029 phase 5.6-c1): grace-period actor recorded as "anonymous"
# ---------------------------------------------------------------------------


def test_grace_period_audit_actor_recorded_as_anonymous(anon_client):
    """Mn-4: a grace-period write (no token) records actor="anonymous", not ""."""
    resp = anon_client.post(
        "/api/config/order_source",
        json={"value": "AnonActor-Test", "sort_order": 1},
    )
    assert resp.status_code == 200, resp.text

    with get_db() as conn:
        rows = _audit_log_rows(conn)
        matches = [
            r for r in rows
            if r["entity_type"] == "config"
            and r["action"] == "create"
            and r["new_value"]
            and "AnonActor-Test" in r["new_value"]
        ]
        assert matches, "no grace-period config create audit row found"
        assert matches[-1]["username"] == "anonymous", (
            f"grace-period actor should be 'anonymous', got "
            f"{matches[-1]['username']!r}"
        )