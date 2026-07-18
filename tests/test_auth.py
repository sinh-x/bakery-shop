"""Tests for DG-029 Phase 2: auth endpoint, middleware, rate limiting, lockout.

Covers:
  - AC1: valid username+password → JWT with {sub, role, exp, jti} claims, HTTP 200
  - AC2: invalid username/password → HTTP 401
  - AC3: AUTH_REQUIRED=true, no Authorization header → HTTP 401 on protected endpoints
  - AC7: AUTH_REQUIRED=false → requests succeed without token (grace period)
  - AC15: 3 failed login attempts from same IP in 1 min → 4th attempt returns 429
  - AC16: 5 consecutive failed login attempts → HTTP 423 Locked for 30 min
"""

from __future__ import annotations

import time
import uuid
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from baker.api.auth import _pwd_ctx, _reset_auth_state
from baker.config import JWT_SECRET
from baker.db.connection import get_db


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_test_user(conn, username: str, password: str, role: str = "admin") -> None:
    """Insert a test user with a known bcrypt-hashed password."""
    hashed = _pwd_ctx.hash(password)
    conn.execute(
        "INSERT INTO users (username, password_hash, role, active) VALUES (?, ?, ?, 1)",
        (username, hashed, role),
    )
    conn.commit()


@pytest.fixture(autouse=True)
def _reset_auth():
    """Clear in-memory auth state before each test."""
    _reset_auth_state()
    yield
    _reset_auth_state()


# auth_client and anon_client fixtures live in conftest.py so they are shared
# with test_user_session_cli.py and other Phase 4+ test modules.


def _seed_user_and_get_token(api_client, username="testadmin", password="testpass123"):
    """Create a test user and return a valid JWT token via the login endpoint."""
    with get_db() as conn:
        _create_test_user(conn, username, password, role="admin")
    resp = api_client.post(
        "/api/auth/login",
        json={"username": username, "password": password},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["token"]


# ---------------------------------------------------------------------------
# AC1: valid login returns JWT with correct claims
# ---------------------------------------------------------------------------


def test_login_success_returns_jwt_with_claims(api_client):
    """AC1: valid username+password → JWT with {sub, role, exp, jti}, HTTP 200."""
    with get_db() as conn:
        _create_test_user(conn, "testadmin", "testpass123", role="admin")

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "testadmin", "password": "testpass123"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["username"] == "testadmin"
    assert data["role"] == "admin"
    assert "token" in data

    # Decode and verify JWT claims.
    payload = jwt.decode(data["token"], JWT_SECRET, algorithms=["HS256"])
    assert payload["sub"] == "testadmin"
    assert payload["role"] == "admin"
    assert "exp" in payload
    assert "jti" in payload
    # exp should be ~7 days from now.
    expected_exp = int(time.time()) + 7 * 24 * 60 * 60
    assert abs(payload["exp"] - expected_exp) < 10
    # jti should be a valid UUID.
    uuid.UUID(payload["jti"])


def test_login_success_staff_role(api_client):
    """AC1 variant: staff role is correctly returned and included in JWT."""
    with get_db() as conn:
        _create_test_user(conn, "staff1", "staffpass456", role="staff")

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "staff1", "password": "staffpass456"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["role"] == "staff"
    payload = jwt.decode(data["token"], JWT_SECRET, algorithms=["HS256"])
    assert payload["role"] == "staff"


# ---------------------------------------------------------------------------
# AC2: invalid credentials return 401
# ---------------------------------------------------------------------------


def test_login_wrong_password_returns_401(api_client):
    """AC2: invalid password → HTTP 401."""
    with get_db() as conn:
        _create_test_user(conn, "testadmin", "testpass123")

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "testadmin", "password": "wrongpassword"},
    )
    assert resp.status_code == 401


def test_login_nonexistent_user_returns_401(api_client):
    """AC2: nonexistent username → HTTP 401."""
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "nobody", "password": "whatever"},
    )
    assert resp.status_code == 401


def test_login_inactive_user_returns_401(api_client):
    """Inactive (deactivated) users cannot log in."""
    with get_db() as conn:
        _create_test_user(conn, "inactive", "somepass789")
        conn.execute("UPDATE users SET active = 0 WHERE username = 'inactive'")
        conn.commit()

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "inactive", "password": "somepass789"},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# AC7: AUTH_REQUIRED=false → grace period, requests succeed without token
# ---------------------------------------------------------------------------


def test_grace_period_anon_request_succeeds(anon_client):
    """AC7: AUTH_REQUIRED=false → endpoint works without token."""
    resp = anon_client.get("/api/health")
    assert resp.status_code == 200


def test_grace_period_protected_endpoint_no_token(anon_client):
    """AC7: AUTH_REQUIRED=false → protected endpoint works without token."""
    resp = anon_client.get("/api/products")
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# DG-259 Phase 3 — Grace period actor resolution (FR8 / AC6 / AC6-a / AC6-b / AC6-c)
# ---------------------------------------------------------------------------


def _make_expired_token(username: str, role: str, jti: str) -> str:
    """Mint an expired JWT with the given jti (bypasses login)."""
    payload = {
        "sub": username,
        "role": role,
        "exp": int(time.time()) - 3600,  # expired 1 hour ago
        "jti": jti,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def _create_session(conn, jti: str, username: str, role: str = "admin", staff_id: object = None) -> None:
    """Insert an active session row (bypasses login)."""
    from baker.utils.time import now_utc
    ts = now_utc()
    conn.execute(
        "INSERT INTO sessions "
        "(jti, username, role, client_ip, device_model, app_version, "
        " os_version, logged_in_at, last_activity, revoked_at, staff_id) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)",
        (jti, username, role, '', '', '', '', ts, ts, staff_id),
    )


def test_grace_period_order_create_uses_fallback_when_no_session(api_client):
    """AC6-b: AUTH_REQUIRED=false, no JWT, no session → created_by uses client-supplied value."""
    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Test AC6-b",
            "dueDate": "2026-07-20",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
            "createdBy": "Ngân",
        },
    )
    assert resp.status_code == 201
    assert resp.json()["createdBy"] == "Ngân"

    with get_db() as conn:
        row = conn.execute(
            "SELECT created_by FROM orders WHERE order_ref = ?",
            (resp.json()["orderRef"],),
        ).fetchone()
    assert row["created_by"] == "Ngân"


def test_grace_period_order_create_preserves_empty_created_by(api_client):
    """AC6-b variant: no createdBy sent → created_by is empty (legacy contract)."""
    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Test AC6-b-empty",
            "dueDate": "2026-07-20",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
        },
    )
    assert resp.status_code == 201
    assert resp.json()["createdBy"] == ""


def test_grace_period_order_create_uses_session_staff_name(api_client):
    """AC6-c: expired JWT + session with staff_id → created_by = staff name."""
    staff_name = "TestStaffGia"
    with get_db() as conn:
        conn.execute(
            "INSERT INTO staff (name, role) VALUES (?, ?)",
            (staff_name, "staff"),
        )
        staff_id = int(conn.execute(
            "SELECT id FROM staff WHERE name = ?", (staff_name,)
        ).fetchone()["id"])

        user = "teststaffgia"
        _create_test_user(conn, user, "pass123", role="staff")
        conn.execute("UPDATE users SET staff_id = ? WHERE username = ?", (staff_id, user))

        jti = str(uuid.uuid4())
        _create_session(conn, jti, user, role="staff", staff_id=staff_id)

    expired_token = _make_expired_token(user, "staff", jti)

    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Test AC6-c",
            "dueDate": "2026-07-20",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
        },
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert resp.status_code == 201
    assert resp.json()["createdBy"] == staff_name

    with get_db() as conn:
        row = conn.execute(
            "SELECT created_by FROM orders WHERE order_ref = ?",
            (resp.json()["orderRef"],),
        ).fetchone()
    assert row["created_by"] == staff_name


def test_grace_period_order_create_with_expired_jwt_no_session_fallback(api_client):
    """Expired JWT but no session row → falls through to client-supplied fallback."""
    user = "expirednosesh"
    jti = str(uuid.uuid4())
    with get_db() as conn:
        _create_test_user(conn, user, "pass123", role="staff")

    expired_token = _make_expired_token(user, "staff", jti)

    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Test no-session",
            "dueDate": "2026-07-20",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
            "createdBy": "Phượng",
        },
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert resp.status_code == 201
    assert resp.json()["createdBy"] == "Phượng"


def test_grace_period_order_create_expired_jwt_session_no_staff_fallback(api_client):
    """Expired JWT + session but staff_id is NULL → falls through to fallback."""
    user = "expirednostaff"
    jti = str(uuid.uuid4())
    with get_db() as conn:
        _create_test_user(conn, user, "pass123", role="staff")
        _create_session(conn, jti, user, role="staff", staff_id=None)

    expired_token = _make_expired_token(user, "staff", jti)

    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Test no-staff-id",
            "dueDate": "2026-07-20",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
            "createdBy": "Tân",
        },
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert resp.status_code == 201
    assert resp.json()["createdBy"] == "Tân"


def test_grace_period_order_create_valid_jwt_still_wins(api_client):
    """Valid JWT (even with session) → JWT sub claim always wins (AC1)."""
    from tests.auth_helpers import _seed_user, _auth_headers

    user = "validuser"
    with get_db() as conn:
        token = _seed_user(conn, user, "admin")

    resp = api_client.post(
        "/api/orders",
        json={
            "customerName": "Test JWT wins",
            "dueDate": "2026-07-20",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
            "createdBy": "Imposter",
        },
        headers=_auth_headers(token),
    )
    assert resp.status_code == 201
    assert resp.json()["createdBy"] == user


# ---------------------------------------------------------------------------
# AC3: AUTH_REQUIRED=true, no Authorization header → HTTP 401
# ---------------------------------------------------------------------------


def test_auth_required_no_token_returns_401(auth_client):
    """AC3: AUTH_REQUIRED=true, no Authorization header → HTTP 401."""
    resp = auth_client.get("/api/products")
    assert resp.status_code == 401


def test_auth_required_invalid_token_returns_401(auth_client):
    """AC3 variant: invalid token → HTTP 401."""
    resp = auth_client.get(
        "/api/products",
        headers={"Authorization": "Bearer invalidtoken123"},
    )
    assert resp.status_code == 401


def test_auth_required_expired_token_returns_401(auth_client):
    """Expired JWT → HTTP 401 with expiry message."""
    # Create an expired token.
    expired_payload = {
        "sub": "testadmin",
        "role": "admin",
        "exp": int(time.time()) - 3600,
        "jti": str(uuid.uuid4()),
    }
    expired_token = jwt.encode(expired_payload, JWT_SECRET, algorithm="HS256")

    resp = auth_client.get(
        "/api/products",
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert resp.status_code == 401


def test_auth_required_valid_token_succeeds(auth_client):
    """Valid token → request succeeds."""
    token = _seed_user_and_get_token(auth_client)
    resp = auth_client.get(
        "/api/products",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200


def test_auth_required_health_remains_public(auth_client):
    """AC3: /api/health remains public even when AUTH_REQUIRED=true."""
    resp = auth_client.get("/api/health")
    assert resp.status_code == 200


def test_auth_required_login_remains_public(auth_client):
    """Login endpoint remains public (no token needed to login)."""
    with get_db() as conn:
        _create_test_user(conn, "pub", "pubpass123")
    resp = auth_client.post(
        "/api/auth/login",
        json={"username": "pub", "password": "pubpass123"},
    )
    assert resp.status_code == 200


# ---------------------------------------------------------------------------
# AC15: rate limiting — 3 failed attempts per IP in 1 min → 429
# ---------------------------------------------------------------------------


def test_rate_limit_3_failures_triggers_429(api_client):
    """AC15: 3 failed login attempts from same IP → 4th returns 429."""
    with get_db() as conn:
        _create_test_user(conn, "ratelimited", "realpass123")

    # 3 failed attempts.
    for _ in range(3):
        resp = api_client.post(
            "/api/auth/login",
            json={"username": "ratelimited", "password": "wrong"},
        )
        assert resp.status_code == 401

    # 4th attempt — should be rate limited (429).
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "ratelimited", "password": "wrong"},
    )
    assert resp.status_code == 429


def test_rate_limit_successful_login_clears_counter(api_client):
    """A successful login before the threshold clears the failure counter."""
    with get_db() as conn:
        _create_test_user(conn, "clearcounter", "realpass123")

    # 2 failed attempts (below threshold).
    for _ in range(2):
        resp = api_client.post(
            "/api/auth/login",
            json={"username": "clearcounter", "password": "wrong"},
        )
        assert resp.status_code == 401

    # Successful login — clears counter.
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "clearcounter", "password": "realpass123"},
    )
    assert resp.status_code == 200

    # 2 more failures should not trigger 429 (counter was reset).
    for _ in range(2):
        resp = api_client.post(
            "/api/auth/login",
            json={"username": "clearcounter", "password": "wrong"},
        )
        assert resp.status_code == 401

    # 3rd failure is the one that triggers block (need 3 total in window).
    # But we have 2 already, so this is 3rd → triggers block → 4th gets 429.
    # Actually the 3rd failure itself sets the block; the 4th request gets 429.
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "clearcounter", "password": "wrong"},
    )
    assert resp.status_code == 401  # 3rd failure — sets block

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "clearcounter", "password": "wrong"},
    )
    assert resp.status_code == 429  # blocked now


# ---------------------------------------------------------------------------
# AC16: account lockout — 5 consecutive fails → 423 Locked
# ---------------------------------------------------------------------------


def test_account_lockout_5_failures_returns_423(api_client):
    """AC16: 5 consecutive failed login attempts → HTTP 423 (Locked).

    Rate limiting (FR18) is IP-level and would block at 3 failures from the
    same test-client IP before lockout (5) can trigger. These are independent
    security layers — rate limiting protects against rapid single-IP brute
    force, lockout protects against slow cross-IP brute force on one
    username. We clear rate-limit state between attempts to isolate lockout.
    """
    from baker.api.auth import _rate_failures, _rate_blocked_until

    with get_db() as conn:
        _create_test_user(conn, "lockme", "realpass123")

    # 5 failed attempts — clear rate limit state between each to isolate lockout.
    for i in range(5):
        _rate_failures.clear()
        _rate_blocked_until.clear()
        resp = api_client.post(
            "/api/auth/login",
            json={"username": "lockme", "password": "wrong"},
        )
        if i < 4:
            assert resp.status_code == 401, f"attempt {i+1}: {resp.status_code}"
        else:
            # 5th failure — account gets locked, response is 423.
            assert resp.status_code == 423, f"attempt {i+1}: {resp.status_code}"

    # 6th attempt with correct password — still locked (423).
    _rate_failures.clear()
    _rate_blocked_until.clear()
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "lockme", "password": "realpass123"},
    )
    assert resp.status_code == 423


def test_account_lockout_persists_in_db(api_client):
    """Lockout timestamp is persisted in users.locked_until (NFR8)."""
    from baker.api.auth import _rate_failures, _rate_blocked_until

    with get_db() as conn:
        _create_test_user(conn, "persistlock", "realpass123")

    # Trigger lockout — clear rate limit state between attempts.
    for _ in range(5):
        _rate_failures.clear()
        _rate_blocked_until.clear()
        api_client.post(
            "/api/auth/login",
            json={"username": "persistlock", "password": "wrong"},
        )

    with get_db() as conn:
        row = conn.execute(
            "SELECT locked_until FROM users WHERE username = 'persistlock'"
        ).fetchone()
        assert row["locked_until"] is not None
        # locked_until should be ~30 minutes from now.
        lock_dt = datetime.fromisoformat(row["locked_until"].replace("Z", "+00:00"))
        delta = lock_dt - datetime.now(timezone.utc)
        assert timedelta(minutes=29) < delta < timedelta(minutes=31)


def test_account_lockout_resets_on_success(api_client):
    """A successful login before 5 failures resets the counter."""
    from baker.api.auth import _rate_failures, _rate_blocked_until

    with get_db() as conn:
        _create_test_user(conn, "resetsok", "realpass123")

    # 4 failures (below lockout threshold) — clear rate limit between each.
    for _ in range(4):
        _rate_failures.clear()
        _rate_blocked_until.clear()
        resp = api_client.post(
            "/api/auth/login",
            json={"username": "resetsok", "password": "wrong"},
        )
        assert resp.status_code == 401

    # Successful login — resets counter.
    _rate_failures.clear()
    _rate_blocked_until.clear()
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "resetsok", "password": "realpass123"},
    )
    assert resp.status_code == 200

    # 4 more failures should not lock (counter was reset).
    for _ in range(4):
        _rate_failures.clear()
        _rate_blocked_until.clear()
        resp = api_client.post(
            "/api/auth/login",
            json={"username": "resetsok", "password": "wrong"},
        )
        assert resp.status_code == 401  # not locked yet

    # 5th failure now triggers the lock.
    _rate_failures.clear()
    _rate_blocked_until.clear()
    resp = api_client.post(
        "/api/auth/login",
        json={"username": "resetsok", "password": "wrong"},
    )
    assert resp.status_code == 423


# ---------------------------------------------------------------------------
# Middleware: denylist (FR21 — Phase 4 integration)
# ---------------------------------------------------------------------------


def test_denied_jti_rejected(auth_client):
    """A revoked jti in the denylist returns 401."""
    token = _seed_user_and_get_token(auth_client)
    payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])

    from baker.api.auth import revoke_token_jti
    revoke_token_jti(payload["jti"])

    resp = auth_client.get(
        "/api/products",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Mn-5 (DG-029 phase 5.6-c1): startup validation refuses to start when
# AUTH_REQUIRED=true and BAKER_JWT_SECRET is unset (ephemeral).
# ---------------------------------------------------------------------------


def test_create_app_refuses_to_start_when_auth_required_and_jwt_ephemeral():
    """Mn-5: AUTH_REQUIRED=true + ephemeral JWT_SECRET → RuntimeError."""
    from unittest.mock import patch

    with patch("baker.config.AUTH_REQUIRED", True):
        with patch("baker.config.JWT_SECRET_EPHEMERAL", True):
            # create_app is imported lazily so the patched module-level
            # attributes are read at call time.
            from baker.api.app import create_app
            with pytest.raises(RuntimeError, match="BAKER_JWT_SECRET"):
                create_app()


def test_create_app_starts_when_auth_required_and_jwt_set(monkeypatch):
    """Mn-5: AUTH_REQUIRED=true + stable JWT_SECRET → starts normally."""
    from unittest.mock import patch

    stable_secret = "a" * 48  # >= 32 bytes, stable, not ephemeral
    with patch("baker.config.AUTH_REQUIRED", True):
        with patch("baker.config.JWT_SECRET_EPHEMERAL", False):
            with patch("baker.config.JWT_SECRET", stable_secret):
                from baker.api.app import create_app
                app = create_app()
                assert app is not None


def test_create_app_starts_in_grace_period_without_jwt(monkeypatch):
    """Mn-5: AUTH_REQUIRED=false (grace period) → starts even with ephemeral secret."""
    from unittest.mock import patch

    with patch("baker.config.AUTH_REQUIRED", False):
        with patch("baker.config.JWT_SECRET_EPHEMERAL", True):
            from baker.api.app import create_app
            app = create_app()
            assert app is not None