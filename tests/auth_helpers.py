"""Shared auth test helpers (DG-029 Phase 5.6-c3 / CQ-2).

These helpers were previously duplicated verbatim across test_rbac.py,
test_actor_derivation.py, and test_audit_log_api.py. They are centralized
here so test modules import them instead of redefining them.

Fixtures (``_reset_auth``, ``auth_client``, ``anon_client``) live in
``tests/conftest.py`` and are auto-discovered by pytest — no import needed.
"""

from __future__ import annotations

import time
import uuid

import jwt

from baker.api.auth import _pwd_ctx
from baker.config import JWT_SECRET


def _create_test_user(conn, username: str, password: str, role: str = "admin") -> None:
    """Insert a test user with a known bcrypt-hashed password."""
    hashed = _pwd_ctx.hash(password)
    conn.execute(
        "INSERT INTO users (username, password_hash, role, active) VALUES (?, ?, ?, 1)",
        (username, hashed, role),
    )
    conn.commit()


def _make_token(username: str, role: str) -> str:
    """Mint a JWT for the given user/role (bypasses the login endpoint)."""
    payload = {
        "sub": username,
        "role": role,
        "exp": int(time.time()) + 3600,
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def _seed_user(conn, username: str, role: str, password: str = "pass123") -> str:
    """Create a test user and return a valid JWT token for them."""
    _create_test_user(conn, username, password, role=role)
    return _make_token(username, role)


def _auth_headers(token: str) -> dict:
    """Build an Authorization: Bearer header dict from a token."""
    return {"Authorization": f"Bearer {token}"}