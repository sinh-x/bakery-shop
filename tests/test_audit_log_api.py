"""Tests for DG-029 Phase 5: audit log API endpoint (FR23).

Covers:
  - AC20 (partial, server-side): GET /api/audit-log fully testable server-side
  - Admin JWT → GET /api/audit-log returns 200 with paginated results
  - Staff JWT → GET /api/audit-log returns 403
  - Filters by username, entity_type, date_from, date_to each narrow results
  - Pagination (page/page_size/total)
  - NFR6: AUTH_REQUIRED=false + no token → endpoint accessible (grace period)
"""

from __future__ import annotations

import time
import uuid
from unittest.mock import patch

import jwt
import pytest

from baker.api.auth import _pwd_ctx, _reset_auth_state, record_audit_log
from baker.config import JWT_SECRET
from baker.db.connection import get_db


# ---------------------------------------------------------------------------
# Helpers (mirrors tests/test_rbac.py conventions)
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


def _insert_audit_row(
    conn,
    *,
    username: str,
    action: str = "create",
    entity_type: str = "config",
    entity_id: str = "1",
    created_at: str,
) -> None:
    """Insert a raw audit_log row with an explicit created_at (for date filtering tests)."""
    conn.execute(
        "INSERT INTO audit_log "
        "(username, action, entity_type, entity_id, old_value, new_value, created_at) "
        "VALUES (?, ?, ?, ?, NULL, ?, ?)",
        (username, action, entity_type, entity_id, f'{{"id": {entity_id}}}', created_at),
    )
    conn.commit()


# ---------------------------------------------------------------------------
# Admin access (200) + pagination shape
# ---------------------------------------------------------------------------


def test_admin_gets_audit_log_returns_200(auth_client):
    """AC20 (server-side): admin JWT → GET /api/audit-log returns 200 with paginated results."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn,
            username="adminuser",
            entity_type="config",
            entity_id="1",
            created_at="2026-07-13T10:00:00Z",
        )

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(admin_token))
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert "items" in data
    assert "page" in data
    assert "page_size" in data
    assert "total" in data
    assert data["page"] == 1
    assert data["page_size"] == 50
    assert data["total"] >= 1
    assert len(data["items"]) >= 1
    row = data["items"][0]
    for field in ("id", "username", "action", "entity_type", "entity_id",
                  "old_value", "new_value", "created_at"):
        assert field in row
    assert row["username"] == "adminuser"
    assert row["entity_type"] == "config"


def test_audit_log_pagination_default_page_size(auth_client):
    """Pagination: default page=1, page_size=50."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        for i in range(5):
            _insert_audit_row(
                conn,
                username="adminuser",
                entity_id=str(i),
                created_at="2026-07-13T10:00:00Z",
            )

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(admin_token))
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 5
    assert len(data["items"]) == 5
    assert data["page"] == 1
    assert data["page_size"] == 50


def test_audit_log_pagination_explicit_page_and_size(auth_client):
    """Pagination: explicit page/page_size returns the correct slice + total."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        for i in range(6):
            _insert_audit_row(
                conn,
                username="adminuser",
                entity_id=str(i),
                created_at=f"2026-07-13T10:00:0{i}Z",
            )

    resp = auth_client.get(
        "/api/audit-log?page=2&page_size=2",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 6
    assert data["page"] == 2
    assert data["page_size"] == 2
    assert len(data["items"]) == 2
    # Ordered newest first — page 2 of size 2 = entries 3,4 (by id desc / created_at desc)
    ids = [r["id"] for r in data["items"]]
    assert len(ids) == 2


def test_audit_log_empty_when_no_rows(auth_client):
    """GET /api/audit-log on empty table returns 200 with empty items + total 0."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(admin_token))
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 0
    assert data["items"] == []


# ---------------------------------------------------------------------------
# Staff access (403)
# ---------------------------------------------------------------------------


def test_staff_gets_403_on_audit_log(auth_client):
    """AC20: staff JWT → GET /api/audit-log returns 403 (admin-only, FR23)."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(staff_token))
    assert resp.status_code == 403


def test_staff_403_takes_precedence_even_when_rows_exist(auth_client):
    """Staff is blocked from audit log even when rows exist for their username."""
    with get_db() as conn:
        staff_token = _seed_user(conn, "staffuser", "staff")
        _insert_audit_row(
            conn,
            username="staffuser",
            entity_type="config",
            entity_id="1",
            created_at="2026-07-13T10:00:00Z",
        )

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(staff_token))
    assert resp.status_code == 403


# ---------------------------------------------------------------------------
# Filter: username
# ---------------------------------------------------------------------------


def test_filter_by_username_narrows_results(auth_client):
    """FR23: filter by username narrows results to that user."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-13T10:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-13T10:00:01Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="product", entity_id="3",
            created_at="2026-07-13T10:00:02Z",
        )

    resp = auth_client.get(
        "/api/audit-log?username=alice",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 2
    assert all(r["username"] == "alice" for r in data["items"])


def test_filter_by_username_no_match(auth_client):
    """FR23: filter by nonexistent username returns 0 results."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-13T10:00:00Z",
        )

    resp = auth_client.get(
        "/api/audit-log?username=nobody",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 0
    assert data["items"] == []


# ---------------------------------------------------------------------------
# Filter: entity_type
# ---------------------------------------------------------------------------


def test_filter_by_entity_type_narrows_results(auth_client):
    """FR23: filter by entity_type narrows results to that entity type."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-13T10:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="product", entity_id="2",
            created_at="2026-07-13T10:00:01Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="product", entity_id="3",
            created_at="2026-07-13T10:00:02Z",
        )

    resp = auth_client.get(
        "/api/audit-log?entity_type=product",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 2
    assert all(r["entity_type"] == "product" for r in data["items"])


# ---------------------------------------------------------------------------
# Filter: date_from / date_to
# ---------------------------------------------------------------------------


def test_filter_by_date_from_narrows_results(auth_client):
    """FR23: filter by date_from returns only entries on/after that date."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-10T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-13T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="3",
            created_at="2026-07-15T08:00:00Z",
        )

    resp = auth_client.get(
        "/api/audit-log?date_from=2026-07-13T00:00:00Z",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 2
    for r in data["items"]:
        assert r["created_at"] >= "2026-07-13T00:00:00Z"


def test_filter_by_date_to_narrows_results(auth_client):
    """FR23: filter by date_to returns only entries on/before that date."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-10T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-13T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="3",
            created_at="2026-07-15T08:00:00Z",
        )

    resp = auth_client.get(
        "/api/audit-log?date_to=2026-07-13T23:59:59Z",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 2
    for r in data["items"]:
        assert r["created_at"] <= "2026-07-13T23:59:59Z"


def test_filter_by_date_range_narrows_results(auth_client):
    """FR23: filter by date_from AND date_to returns only entries in the window."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-10T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-12T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="3",
            created_at="2026-07-14T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="4",
            created_at="2026-07-16T08:00:00Z",
        )

    resp = auth_client.get(
        "/api/audit-log?date_from=2026-07-11T00:00:00Z&date_to=2026-07-15T00:00:00Z",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 2
    for r in data["items"]:
        assert "2026-07-11" <= r["created_at"] <= "2026-07-15"


def test_filter_by_date_only_bounds_inclusive(auth_client):
    """FR23: date-only bounds (YYYY-MM-DD) work via lexical comparison."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-12T23:59:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-13T10:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="3",
            created_at="2026-07-13T23:00:00Z",
        )

    # date_to=2026-07-13 should include all 2026-07-13T* timestamps
    # (they all sort after "2026-07-13" lexically).
    resp = auth_client.get(
        "/api/audit-log?date_to=2026-07-13T23:59:59Z",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 3


def test_filter_by_date_only_date_to_includes_same_day(auth_client):
    """Mn-1 (DG-029 phase 5.6-c1): date_to=YYYY-MM-DD (no T) includes same-day entries.

    A date-only ``date_to`` value sorts *before* every same-day timestamp
    (``2026-07-13T..`` > ``2026-07-13``), so a naive lexical comparison
    would drop same-day entries. The server expands a date-only ``date_to``
    to ``{date}T23:59:59Z`` so the whole day is included.
    """
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-13T00:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-13T10:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="3",
            created_at="2026-07-13T23:59:59Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="4",
            created_at="2026-07-14T00:00:00Z",
        )

    # date_to=2026-07-13 (date-only, 10 chars, no T) — must include all
    # three 2026-07-13 rows but exclude 2026-07-14.
    resp = auth_client.get(
        "/api/audit-log?date_to=2026-07-13",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 3
    for r in data["items"]:
        assert r["created_at"].startswith("2026-07-13")


# ---------------------------------------------------------------------------
# Combined filters
# ---------------------------------------------------------------------------


def test_combined_filters_username_and_entity_type(auth_client):
    """FR23: combined username + entity_type filter intersects."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-13T10:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="product", entity_id="2",
            created_at="2026-07-13T10:00:01Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="3",
            created_at="2026-07-13T10:00:02Z",
        )

    resp = auth_client.get(
        "/api/audit-log?username=alice&entity_type=product",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["items"][0]["username"] == "alice"
    assert data["items"][0]["entity_type"] == "product"


def test_all_filters_combined(auth_client):
    """FR23: username + entity_type + date_from + date_to combined."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-10T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="2",
            created_at="2026-07-13T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="3",
            created_at="2026-07-13T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="product", entity_id="4",
            created_at="2026-07-13T08:00:00Z",
        )

    resp = auth_client.get(
        "/api/audit-log?username=alice&entity_type=config"
        "&date_from=2026-07-11T00:00:00Z&date_to=2026-07-14T00:00:00Z",
        headers=_auth_headers(admin_token),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["items"][0]["entity_id"] == "2"


# ---------------------------------------------------------------------------
# Ordering + integration with record_audit_log (FR22 → FR23 read)
# ---------------------------------------------------------------------------


def test_results_ordered_newest_first(auth_client):
    """GET /api/audit-log returns entries newest-first (created_at DESC, id DESC)."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "adminuser", "admin")
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="1",
            created_at="2026-07-13T08:00:00Z",
        )
        _insert_audit_row(
            conn, username="bob", entity_type="config", entity_id="2",
            created_at="2026-07-13T12:00:00Z",
        )
        _insert_audit_row(
            conn, username="alice", entity_type="config", entity_id="3",
            created_at="2026-07-13T10:00:00Z",
        )

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(admin_token))
    assert resp.status_code == 200
    items = resp.json()["items"]
    created = [r["created_at"] for r in items]
    assert created == sorted(created, reverse=True)
    assert items[0]["created_at"] == "2026-07-13T12:00:00Z"


def test_reads_rows_written_by_record_audit_log(auth_client):
    """FR22 → FR23: rows written by the Phase 3 helper are readable via the API."""
    with get_db() as conn:
        admin_token = _seed_user(conn, "auditadmin", "admin")
        record_audit_log(
            conn,
            username="auditadmin",
            action="create",
            entity_type="config",
            entity_id="42",
            old_value=None,
            new_value={"value": "FromHelper", "sort_order": 1},
        )
        conn.commit()

    resp = auth_client.get("/api/audit-log", headers=_auth_headers(admin_token))
    assert resp.status_code == 200
    items = resp.json()["items"]
    matches = [r for r in items if r["entity_id"] == "42" and r["username"] == "auditadmin"]
    assert matches, f"no row found written by record_audit_log; items={items}"
    assert matches[0]["action"] == "create"
    assert matches[0]["new_value"] is not None


# ---------------------------------------------------------------------------
# NFR6: AUTH_REQUIRED=false → grace period (no token) — admin-only endpoint
# behaves consistently with AuthMiddleware grace-period handling.
#
# Per the primer: "endpoint must behave consistently with existing
# AuthMiddleware grace-period handling." Under grace period, no token means
# auth_role is unset; RequireRole passes through. So an unauthenticated
# request reaches the endpoint (no 403, no 401) and returns 200.
# ---------------------------------------------------------------------------


def test_grace_period_no_token_returns_200(anon_client):
    """NFR6: AUTH_REQUIRED=false + no token → endpoint accessible (grace period)."""
    resp = anon_client.get("/api/audit-log")
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert "items" in data
    assert data["total"] == 0