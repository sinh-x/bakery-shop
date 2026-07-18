"""Auth API routes — login endpoint with rate limiting and account lockout.

DG-029 Phase 2. Implements:
  - POST /api/auth/login (FR1): bcrypt password verify, JWT issuance with
    {sub, role, exp, jti} claims, 7-day expiry (NFR2).
  - Login rate limiting (FR18): 3 failed attempts per IP within 1 minute
    triggers HTTP 429 for 5 minutes. In-memory per-IP counter (NFR7).
  - Brute-force account lockout (FR19): 5 consecutive failed attempts for
    the same username triggers HTTP 423 (Locked) for 30 minutes. Lock
    timestamp stored in users.locked_until (NFR8).

The middleware (AuthMiddleware) and router registration live in
``baker.api.app`` and ``baker.api.middleware`` respectively.
"""

from __future__ import annotations

import json
import time
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import jwt
from fastapi import APIRouter, HTTPException, Request
from passlib.context import CryptContext
from pydantic import BaseModel

from baker.config import AUTH_REQUIRED, BCRYPT_ROUNDS, JWT_SECRET
from baker.db.connection import get_db
from baker.utils.time import now_utc

router = APIRouter(prefix="/api/auth", tags=["auth"])

# bcrypt password hashing context (NFR4: cost factor 12 by default in prod).
# BCRYPT_ROUNDS defaults to 12 in production; tests override it via
# BAKER_BCRYPT_ROUNDS to keep the suite fast (DG-029 Post-UAT Follow-up Item 1).
_pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=BCRYPT_ROUNDS)

# JWT token expiry: 7 days from issuance (NFR2). No refresh mechanism.
_JWT_EXPIRY_SECONDS = 7 * 24 * 60 * 60


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    token: str
    username: str
    role: str


# ---------------------------------------------------------------------------
# Rate limiting (FR18 / NFR7) — in-memory per-IP failed-attempt tracking.
#
# Tracks failed login attempts per client IP address. When 3 failures occur
# within a 1-minute sliding window, the IP is blocked for 5 minutes (returns
# HTTP 429 on any login attempt during the block window). State is in-memory
# and resets on server restart (NFR7 — acceptable for bakery use case).
#
# Structure:
#   _rate_failures[ip] = [timestamp1, timestamp2, ...]  (failed attempts)
#   _rate_blocked_until[ip] = epoch_seconds             (block expiry)
# ---------------------------------------------------------------------------

_RATE_WINDOW_SECONDS = 60          # 1-minute sliding window for failures.
_RATE_MAX_FAILURES = 3             # 3 failures within the window → block.
_RATE_BLOCK_SECONDS = 5 * 60      # Block duration: 5 minutes.

_rate_failures: dict[str, list[float]] = defaultdict(list)
_rate_blocked_until: dict[str, float] = {}


def _client_ip(request: Request) -> str:
    """Return the client IP address for rate-limit keying."""
    return request.client.host if request.client else "unknown"


def _is_rate_blocked(ip: str) -> bool:
    """Check whether ``ip`` is currently blocked by rate limiting (FR18)."""
    until = _rate_blocked_until.get(ip)
    if until is None:
        return False
    if time.monotonic() >= until:
        # Block expired — clean up.
        _rate_blocked_until.pop(ip, None)
        return False
    return True


def _record_rate_failure(ip: str) -> None:
    """Record a failed login attempt for ``ip`` and block if threshold reached."""
    now = time.monotonic()
    failures = _rate_failures[ip]
    # Prune failures outside the sliding window.
    _rate_failures[ip] = [t for t in failures if now - t < _RATE_WINDOW_SECONDS]
    _rate_failures[ip].append(now)

    if len(_rate_failures[ip]) >= _RATE_MAX_FAILURES:
        _rate_blocked_until[ip] = now + _RATE_BLOCK_SECONDS
        # Clear the failure list so post-block failures start fresh.
        _rate_failures[ip] = []


def _clear_rate_failures(ip: str) -> None:
    """Clear rate-limit failures for ``ip`` (called on successful login)."""
    _rate_failures.pop(ip, None)


# ---------------------------------------------------------------------------
# Account lockout (FR19 / NFR8) — 5 consecutive failed attempts → 30 min lock.
#
# Tracks consecutive failed login attempts per username in-memory for fast
# threshold checking, and persists the lock expiry timestamp in the
# ``users.locked_until`` column so the lock survives server restarts
# (NFR8: auto-expiring after 30 minutes, no manual intervention needed for
# expiry). A successful login resets the consecutive-failure counter.
# ---------------------------------------------------------------------------

_LOCKOUT_MAX_FAILURES = 5             # 5 consecutive fails → lock.
_LOCKOUT_DURATION_SECONDS = 30 * 60  # 30-minute lock.

# In-memory consecutive-failure counter per username. Survives until server
# restart; the DB locked_until column is the persistent authority.
_lockout_failures: dict[str, int] = defaultdict(int)


def _is_account_locked(locked_until: Optional[str]) -> bool:
    """Check whether a user is currently locked based on ``locked_until``.

    ``locked_until`` is an ISO-8601 UTC timestamp string or NULL. Returns
    ``True`` when the lock has not yet expired.
    """
    if not locked_until:
        return False
    try:
        lock_dt = datetime.fromisoformat(locked_until.replace("Z", "+00:00"))
        return datetime.now(timezone.utc) < lock_dt
    except (ValueError, TypeError):
        return False


def _lock_account(conn, username: str) -> None:
    """Set ``users.locked_until`` to now + 30 minutes (NFR8)."""
    lock_until = (datetime.now(timezone.utc) + timedelta(seconds=_LOCKOUT_DURATION_SECONDS))
    lock_until_str = lock_until.strftime("%Y-%m-%dT%H:%M:%SZ")
    conn.execute(
        "UPDATE users SET locked_until = ? WHERE username = ?",
        (lock_until_str, username),
    )


def _record_login_failure(conn, username: str) -> bool:
    """Record a consecutive failed login attempt for ``username`` (FR19).

    Increments the in-memory counter and, on the 5th consecutive failure,
    locks the account by setting ``locked_until`` in the DB. Returns
    ``True`` if the account was just locked on this call, ``False`` otherwise.
    """
    _lockout_failures[username] += 1
    if _lockout_failures[username] >= _LOCKOUT_MAX_FAILURES:
        _lock_account(conn, username)
        return True
    return False


def _clear_login_failures(username: str) -> None:
    """Reset the consecutive-failure counter for ``username`` on success."""
    _lockout_failures.pop(username, None)


# ---------------------------------------------------------------------------
# Login endpoint (FR1)
# ---------------------------------------------------------------------------

@router.post("/login", response_model=LoginResponse)
def login(body: LoginRequest, request: Request):
    """Authenticate a user and return a JWT token (FR1).

    Accepts ``{username, password}``. On success returns ``{token,
    username, role}`` with a JWT containing ``{sub, role, exp, jti}`` claims
    (7-day expiry, NFR2). On failure returns 401 (invalid credentials), 423
    (account locked), or 429 (rate limited).
    """
    ip = _client_ip(request)

    # FR18: rate limiting — check IP block first.
    if _is_rate_blocked(ip):
        raise HTTPException(
            status_code=429,
            detail="Quá nhiều lần đăng nhập thất bại. Vui lòng thử lại sau 5 phút.",
        )

    with get_db() as conn:
        row = conn.execute(
            "SELECT id, username, password_hash, role, active, locked_until, staff_id "
            "FROM users WHERE username = ?",
            (body.username,),
        ).fetchone()

        # FR19: account lockout — check before password verify.
        if row is not None:
            if not row["active"]:
                raise HTTPException(
                    status_code=401,
                    detail="Tài khoản đã bị vô hiệu hóa.",
                )
            if _is_account_locked(row["locked_until"]):
                raise HTTPException(
                    status_code=423,
                    detail="Tài khoản đã bị khóa tạm thời do quá nhiều lần đăng nhập thất bại. Vui lòng thử lại sau 30 phút.",
                )

        # Verify password (NFR1: bcrypt cost factor 12).
        if row is None or not _pwd_ctx.verify(body.password, row["password_hash"]):
            # Record failures for rate limiting and lockout.
            _record_rate_failure(ip)
            just_locked = False
            if row is not None:
                just_locked = _record_login_failure(conn, row["username"])
            # Commit the lockout UPDATE before raising (the get_db context
            # manager rolls back on exception, which would undo the lock).
            if just_locked:
                conn.commit()
                raise HTTPException(
                    status_code=423,
                    detail="Tài khoản đã bị khóa tạm thời do quá nhiều lần đăng nhập thất bại. Vui lòng thử lại sau 30 phút.",
                )
            raise HTTPException(
                status_code=401,
                detail="Tên đăng nhập hoặc mật khẩu không đúng.",
            )

        # Success — clear failure counters.
        _clear_rate_failures(ip)
        _clear_login_failures(row["username"])

        # Generate JWT with {sub, role, exp, jti} claims (FR1, NFR2).
        now = int(time.time())
        jti = str(uuid.uuid4())
        payload = {
            "sub": row["username"],
            "role": row["role"],
            "exp": now + _JWT_EXPIRY_SECONDS,
            "jti": jti,
        }
        token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")

        # DG-029 Phase 4: record the active session (FR20). IP/device metadata
        # is captured from the request so `baker session list` can display it.
        # DG-259 FR5: carry users.staff_id into the session row at login.
        device_model = request.headers.get("x-device-model", "")
        app_version = request.headers.get("x-app-version", "")
        os_version = request.headers.get("x-os-version", "")
        _record_session(
            conn,
            jti=jti,
            username=row["username"],
            role=row["role"],
            client_ip=ip,
            device_model=device_model,
            app_version=app_version,
            os_version=os_version,
            staff_id=row["staff_id"],
        )

        return LoginResponse(
            token=token,
            username=row["username"],
            role=row["role"],
        )


# ---------------------------------------------------------------------------
# Token denylist (NFR3) — in-memory set of revoked jti values.
#
# Used by AuthMiddleware to reject tokens that have been force-logged-out via
# CLI session management (Phase 4). Adding a jti here invalidates the token
# immediately. State is in-memory; resets on server restart (same trade-off
# as rate limiting — acceptable for bakery use case).
# ---------------------------------------------------------------------------

_token_denylist: set[str] = set()


def revoke_token_jti(jti: str) -> None:
    """Add a JWT ID to the in-memory denylist (NFR3, Phase 4 integration)."""
    _token_denylist.add(jti)


def is_jti_revoked(jti: str) -> bool:
    """Check whether a JWT ID has been revoked via the denylist."""
    return jti in _token_denylist


# ---------------------------------------------------------------------------
# Session tracking (DG-029 Phase 4, FR20/FR21)
#
# Active login sessions are persisted in the ``sessions`` table so that
# ``baker session list`` can display username/role/IP/device/login time/last
# activity. Force-logout (``baker session logout`` / ``logout-all``) revokes
# rows by adding their jti to the in-memory denylist checked by
# AuthMiddleware (FR21) and stamping ``revoked_at`` so future ``session
# list`` runs omit them. The DB is the source of truth for session metadata;
# the denylist is the runtime enforcement point.
# ---------------------------------------------------------------------------


def _record_session(
    conn,
    *,
    jti: str,
    username: str,
    role: str,
    client_ip: str = "",
    device_model: str = "",
    app_version: str = "",
    os_version: str = "",
    staff_id: int | None = None,
) -> None:
    """Insert an active session row on successful login (FR20).

    Called inside the caller's ``get_db()`` transaction so the session row
    commits atomically with the login response.  DG-259 FR5: stores
    ``staff_id`` from ``users.staff_id`` for actor-traceability.
    """
    ts = now_utc()
    conn.execute(
        "INSERT INTO sessions "
        "(jti, username, role, client_ip, device_model, app_version, "
        " os_version, logged_in_at, last_activity, revoked_at, staff_id) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)",
        (jti, username, role, client_ip, device_model, app_version, os_version, ts, ts, staff_id),
    )


def fetch_active_sessions(conn) -> list:
    """Return all active (non-revoked) session rows for `baker session list` (FR20).

    Includes staff name and role via LEFT JOIN (FR9/DG-259). Rows are ordered
    by most recent login first.
    """
    return conn.execute(
        "SELECT s.id, s.jti, s.username, s.role, s.client_ip, s.device_model, "
        "       s.app_version, s.os_version, s.logged_in_at, s.last_activity, "
        "       s.revoked_at, st.name AS staff_name, st.role AS staff_role "
        "FROM sessions s "
        "LEFT JOIN staff st ON st.id = s.staff_id "
        "WHERE s.revoked_at IS NULL "
        "ORDER BY s.logged_in_at DESC"
    ).fetchall()


def revoke_user_sessions(conn, username: str) -> int:
    """Revoke all active sessions for ``username`` (FR21 — `baker session logout`).

    Adds each session's jti to the in-memory denylist and stamps
    ``revoked_at`` in the DB. Returns the number of sessions revoked.
    """
    rows = conn.execute(
        "SELECT jti FROM sessions WHERE username = ? AND revoked_at IS NULL",
        (username,),
    ).fetchall()
    ts = now_utc()
    for row in rows:
        _token_denylist.add(row["jti"])
    conn.execute(
        "UPDATE sessions SET revoked_at = ? "
        "WHERE username = ? AND revoked_at IS NULL",
        (ts, username),
    )
    return len(rows)


def revoke_all_sessions(conn) -> int:
    """Revoke all active sessions for all users (FR21 — `baker session logout-all`).

    Adds every active session's jti to the in-memory denylist and stamps
    ``revoked_at``. Returns the number of sessions revoked.
    """
    rows = conn.execute(
        "SELECT jti FROM sessions WHERE revoked_at IS NULL"
    ).fetchall()
    ts = now_utc()
    for row in rows:
        _token_denylist.add(row["jti"])
    conn.execute(
        "UPDATE sessions SET revoked_at = ? WHERE revoked_at IS NULL",
        (ts,),
    )
    return len(rows)


def _reset_auth_state() -> None:
    """Clear all in-memory auth state (test helper)."""
    _rate_failures.clear()
    _rate_blocked_until.clear()
    _lockout_failures.clear()
    _token_denylist.clear()


# ---------------------------------------------------------------------------
# Role-gated dependency (DG-029 Phase 3, FR3/FR4/FR5)
#
# ``RequireRole("admin")`` is a FastAPI dependency that inspects the role
# attached by ``AuthMiddleware`` to ``request.state.auth_role``. It raises
# HTTP 403 when the caller's role does not match the required role.
#
# Behavior under AUTH_REQUIRED=false (grace period, NFR6):
#   - When no token is presented, ``auth_role`` is unset. The dependency
#     allows the request through (backward compatible — no auth enforced).
#   - When a token *is* presented, the decoded role is honored, so updated
#     clients still get correct RBAC feedback during rollout.
# ---------------------------------------------------------------------------


def RequireRole(required_role: str):
    """FastAPI dependency factory enforcing a minimum JWT role (FR3/FR4/FR5).

    Reads ``request.state.auth_role`` set by ``AuthMiddleware``. Returns the
    authenticated username on success; raises HTTP 403 when the role does
    not match. When ``AUTH_REQUIRED`` is false and no token is present, the
    dependency passes through (NFR6 backward compatibility).
    """

    def _check(request: Request) -> str:
        role = getattr(request.state, "auth_role", None)
        username = getattr(request.state, "auth_username", "") or ""

        # Grace-period pass-through: no auth enforced when token absent.
        # Mn-4 (DG-029 phase 5.6-c1): record a distinguishable actor so
        # grace-period audit rows are not empty strings.
        if role is None and not AUTH_REQUIRED:
            return username or "anonymous"

        if role != required_role:
            raise HTTPException(
                status_code=403,
                detail="Bạn không có quyền thực hiện thao tác này.",
            )
        return username

    return _check


# ---------------------------------------------------------------------------
# Actor derivation helper (DG-029 Phase 5.6-c2, AC14/FR17)
#
# ``resolve_actor`` derives the acting username from the authenticated JWT
# session (``request.state.auth_username`` set by ``AuthMiddleware``) instead
# of trusting free-text client input. When the authenticated identity is
# present it always wins — the client-supplied fallback is ignored. When
# ``AUTH_REQUIRED=false`` (grace period) and no token is present, it falls
# back to the client-provided name so legacy unauthenticated flows keep
# working (NFR6 / DG-119 grace-period baseline).
#
# Use this for any write path that records an actor/``completed_by`` /
# ``logged_by`` / ``staff_name`` field: checklist toggle, event log create/
# edit/delete, stock reconciliation submit.
# ---------------------------------------------------------------------------


def resolve_actor(request: Request, fallback: str = "") -> str:
    """Return the acting username, preferring the authenticated JWT identity.

    DG-029 AC14/FR17: the authenticated ``sub`` claim always wins over any
    client-supplied free-text name. During the grace period
    (``AUTH_REQUIRED=false``) with no token, the client-supplied
    ``fallback`` is returned unchanged so existing unauthenticated clients
    keep working (NFR6 backward compatibility). Note this intentionally
    does *not* substitute ``"anonymous"`` for an empty fallback — that
    sentinel is reserved for admin-gated audit rows via ``RequireRole``
    (Mn-4); these actor fields preserve the legacy empty-string contract.

    DG-259 Phase 3 (FR8): when no valid JWT is present and
    ``AUTH_REQUIRED=false``, the resolution chain extends to the request's
    session. If the Bearer token carries a ``jti`` (even expired) that
    resolves to an active session row with a linked ``staff_id``, the
    staff member's display name is returned. This lets unauthenticated
    users (grace period) who previously logged in have their actions
    attributed to their staff identity rather than a free-text fallback.
    """
    auth_username = getattr(request.state, "auth_username", None)
    if auth_username:
        return auth_username

    if not AUTH_REQUIRED:
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header[len("Bearer "):].strip()
            try:
                payload = jwt.decode(
                    token, JWT_SECRET, algorithms=["HS256"],
                    options={"verify_exp": False},
                )
                jti = payload.get("jti")
                if jti:
                    with get_db() as conn:
                        row = conn.execute(
                            "SELECT st.name FROM sessions s "
                            "LEFT JOIN staff st ON st.id = s.staff_id "
                            "WHERE s.jti = ? AND s.revoked_at IS NULL",
                            (jti,),
                        ).fetchone()
                        if row and row["name"]:
                            return row["name"]
            except jwt.InvalidTokenError:
                pass

    return fallback


# ---------------------------------------------------------------------------
# Audit log recording (DG-029 Phase 3, FR22)
#
# ``record_audit_log`` writes a single row to the ``audit_log`` table for
# admin write operations. ``old_value`` and ``new_value`` are JSON-encoded
# snapshots of the affected entity (or ``None`` for creates/deletes where a
# snapshot is not applicable). The helper is fire-and-forget safe to call
# inside an existing ``get_db()`` transaction — it uses the provided conn.
# ---------------------------------------------------------------------------


def record_audit_log(
    conn,
    username: str,
    action: str,
    entity_type: str,
    entity_id: Any,
    old_value: Any = None,
    new_value: Any = None,
) -> None:
    """Write an audit_log row for an admin write operation (FR22).

    ``old_value``/``new_value`` are JSON-serialized when not None. Must be
    called within the caller's open DB transaction so the audit entry
    commits atomically with the audited mutation.
    """
    def _serialize(value: Any) -> Optional[str]:
        if value is None:
            return None
        if isinstance(value, str):
            return value
        try:
            return json.dumps(value, ensure_ascii=False, default=str)
        except (TypeError, ValueError):
            return str(value)

    conn.execute(
        "INSERT INTO audit_log "
        "(username, action, entity_type, entity_id, old_value, new_value, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (
            username or "",
            action,
            entity_type,
            str(entity_id) if entity_id is not None else None,
            _serialize(old_value),
            _serialize(new_value),
            now_utc(),
        ),
    )