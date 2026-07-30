"""Tests for DG-310 Phase 3: delivery staff claiming (assign/unassign).

Covers FR5, FR6, AC6, AC8, AC10, NFR4:
  - AC6: giao-hang staff claims a non-terminal delivery order → assigned +
    assignedStaffName returned.
  - AC8: assigned staff (or admin) unclaims → assignment cleared.
  - AC10: second staff claims an already-claimed order → 409 rejected
    (single-assignee).
  - Role gating: non giao-hang staff → 403 on assign.
  - Terminal-status gating: delivered/completed/cancelled → 422 on assign.
  - NFR4: existing orders have NULL assigned_staff_id (backward compatible).
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
    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        with patch("baker.api.auth.AUTH_REQUIRED", True):
            yield api_client


def _seed_staff_user(conn, username: str, staff_name: str, staff_role: str, user_role: str = "staff") -> str:
    """Create a staff row + linked user, return a JWT for that user."""
    conn.execute(
        "INSERT INTO staff (name, role) VALUES (?, ?)",
        (staff_name, staff_role),
    )
    staff_id = int(conn.execute(
        "SELECT id FROM staff WHERE name = ?", (staff_name,)
    ).fetchone()["id"])
    _create_test_user(conn, username, "pass123", role=user_role)
    conn.execute("UPDATE users SET staff_id = ? WHERE username = ?", (staff_id, username))
    conn.commit()
    return _make_token(username, user_role)


def _auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _create_order(client=None, customer="Giao Test", status="new", dtype="delivery"):
    """Create an order row directly in the DB.

    ``client`` is accepted for signature compatibility with existing call
    sites but ignored — inserting via the DB avoids the AUTH_REQUIRED gate
    so assign/unassign can be exercised under ``auth_client`` in isolation.
    """
    from baker.models.order import Order, OrderItem

    items = [OrderItem(product="Bánh kem", qty=1, price=200000, product_id="BKS-16")]
    with get_db() as conn:
        order = Order(
            customer_name=customer,
            items=items,
            due_date="2026-07-30",
            delivery_type=dtype,
            status=status,
        )
        order_id = order.save(conn)
        order_ref = order.order_ref
        conn.commit()
    return {"id": str(order_id), "orderRef": order_ref}


# ---------------------------------------------------------------------------
# NFR4 — backward compatibility
# ---------------------------------------------------------------------------


def test_existing_orders_have_null_assigned_staff_id(api_client):
    """NFR4: a freshly created order has NULL assigned_staff_id."""
    order = _create_order()
    resp = api_client.get(f"/api/orders/{order['orderRef']}")
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["assignedStaffId"] is None
    assert data["assignedStaffName"] == ""


def test_migration_v089_adds_column():
    """v089 adds the assigned_staff_id column to orders (idempotent)."""
    from baker.db.schema import ensure_schema
    from baker.db.connection import get_db

    with get_db() as conn:
        ensure_schema(conn)
        cols = [r[1] for r in conn.execute("PRAGMA table_info(orders)").fetchall()]
        assert "assigned_staff_id" in cols
        version_row = conn.execute(
            "SELECT version FROM schema_version WHERE version = 89"
        ).fetchone()
        assert version_row is not None


# ---------------------------------------------------------------------------
# AC6 — assign
# ---------------------------------------------------------------------------


def test_assign_order_succeeds_for_giao_hang_staff(auth_client):
    """AC6: giao-hang staff claims a non-terminal delivery order."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper1", "Người Giao A", "giao-hang")

    order = _create_order()
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token))
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["assignedStaffId"] is not None
    assert data["assignedStaffName"] == "Người Giao A"


def test_assign_returns_assigned_staff_name_on_detail(auth_client):
    """FR7: GET order detail after assign carries assignedStaffName."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper2", "Người Giao B", "giao-hang")

    order = _create_order()
    assign_resp = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token))
    assert assign_resp.status_code == 200
    get_resp = auth_client.get(f"/api/orders/{order['orderRef']}", headers=_auth_headers(token))
    assert get_resp.status_code == 200
    assert get_resp.json()["assignedStaffName"] == "Người Giao B"


# ---------------------------------------------------------------------------
# Role gating
# ---------------------------------------------------------------------------


def test_assign_rejects_non_giao_hang_staff(auth_client):
    """FR5: staff without giao-hang role cannot claim (403)."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "baker1", "Thợ Nướng", "tho-nuong")

    order = _create_order()
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token))
    assert resp.status_code == 403


def test_assign_rejects_when_no_staff_link(auth_client):
    """No staff link on the user → 403."""
    with get_db() as conn:
        _create_test_user(conn, "unlinked", "pass123", role="staff")
        token = _make_token("unlinked", "staff")

    order = _create_order()
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token))
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Terminal-status gating
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("terminal", ["delivered", "completed", "cancelled"])
def test_assign_rejects_terminal_order(auth_client, terminal):
    """Cannot claim an order that has reached a terminal status (422)."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper3", "Người Giao C", "giao-hang")

    order = _create_order(status=terminal)
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token))
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# AC10 — single assignee
# ---------------------------------------------------------------------------


def test_assign_rejects_already_claimed_order(auth_client):
    """AC10: a second staff claiming an already-claimed order is rejected (409)."""
    with get_db() as conn:
        token_a = _seed_staff_user(conn, "shipper_a", "Giao A", "giao-hang")
        token_b = _seed_staff_user(conn, "shipper_b", "Giao B", "giao-hang")

    order = _create_order()
    resp_a = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token_a))
    assert resp_a.status_code == 200
    resp_b = auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token_b))
    assert resp_b.status_code == 409
    # The assignment still belongs to A.
    assert resp_a.json()["assignedStaffName"] == "Giao A"


# ---------------------------------------------------------------------------
# AC8 — unassign
# ---------------------------------------------------------------------------


def test_unassign_by_assigned_staff_succeeds(auth_client):
    """AC8: the assigned staff releases the claim → assignment cleared."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper4", "Người Giao D", "giao-hang")

    order = _create_order()
    auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token))
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/unassign", headers=_auth_headers(token))
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["assignedStaffId"] is None
    assert data["assignedStaffName"] == ""


def test_unassign_by_admin_succeeds(auth_client):
    """FR6: an admin can unclaim any order."""
    with get_db() as conn:
        shipper_token = _seed_staff_user(conn, "shipper5", "Người Giao E", "giao-hang")
        admin_token = _seed_staff_user(conn, "admin1", "Quản Lý", "quan-ly", user_role="admin")

    order = _create_order()
    auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(shipper_token))
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/unassign", headers=_auth_headers(admin_token))
    assert resp.status_code == 200, resp.text
    assert resp.json()["assignedStaffId"] is None


def test_unassign_rejects_other_staff(auth_client):
    """FR6: a different staff (non-admin) cannot unclaim another's order (403)."""
    with get_db() as conn:
        token_a = _seed_staff_user(conn, "shipper6", "Giao F", "giao-hang")
        token_b = _seed_staff_user(conn, "shipper7", "Giao G", "giao-hang")

    order = _create_order()
    auth_client.post(f"/api/orders/{order['orderRef']}/assign", headers=_auth_headers(token_a))
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/unassign", headers=_auth_headers(token_b))
    assert resp.status_code == 403


def test_unassign_rejects_when_not_assigned(auth_client):
    """Unclaiming an unassigned order → 422."""
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper8", "Người Giao H", "giao-hang")

    order = _create_order()
    resp = auth_client.post(f"/api/orders/{order['orderRef']}/unassign", headers=_auth_headers(token))
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Not-found
# ---------------------------------------------------------------------------


def test_assign_404_unknown_order(auth_client):
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper9", "Người Giao I", "giao-hang")
    resp = auth_client.post("/api/orders/ORD-9999/assign", headers=_auth_headers(token))
    assert resp.status_code == 404


def test_unassign_404_unknown_order(auth_client):
    with get_db() as conn:
        token = _seed_staff_user(conn, "shipper10", "Người Giao J", "giao-hang")
    resp = auth_client.post("/api/orders/ORD-9999/unassign", headers=_auth_headers(token))
    assert resp.status_code == 404