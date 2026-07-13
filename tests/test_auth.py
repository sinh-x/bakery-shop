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


@pytest.fixture
def auth_client(api_client):
    """api_client variant with AUTH_REQUIRED=true for middleware tests."""
    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        yield api_client


@pytest.fixture
def anon_client(api_client):
    """api_client variant with AUTH_REQUIRED=false (grace period, default)."""
    with patch("baker.api.middleware.AUTH_REQUIRED", False):
        yield api_client


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