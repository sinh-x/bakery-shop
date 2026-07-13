"""Request logging and auth middleware for Baker API."""

import time

import jwt
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from baker.config import AUTH_REQUIRED, JWT_SECRET
from baker.logging import log_to_db, log_to_file, logger
from baker.utils.time import now_utc

# Paths that remain public even when AUTH_REQUIRED=true (FR2).
_PUBLIC_PATHS = frozenset({"/api/health", "/api/auth/login"})


class LoggingMiddleware(BaseHTTPMiddleware):
    """Log every API request with metadata to file and DB."""

    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.monotonic()

        # Initialize log context on request state
        request.state._log_ctx = {}

        response = await call_next(request)

        duration_ms = round((time.monotonic() - start) * 1000, 2)

        # Extract device headers
        device_model = request.headers.get("x-device-model", "")
        app_version = request.headers.get("x-app-version", "")
        os_version = request.headers.get("x-os-version", "")
        client_ip = request.client.host if request.client else ""

        # Get ref context set by route handlers
        ctx = getattr(request.state, "_log_ctx", {})

        level = "INFO"
        if response.status_code >= 500:
            level = "ERROR"
        elif response.status_code >= 400:
            level = "WARNING"

        entry = {
            "timestamp": now_utc(),
            "level": level,
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_ms": duration_ms,
            "client_ip": client_ip,
            "device_model": device_model,
            "app_version": app_version,
            "os_version": os_version,
            "ref_type": ctx.get("ref_type", ""),
            "ref_id": ctx.get("ref_id"),
            "message": f"{request.method} {request.url.path} {response.status_code} {duration_ms}ms",
            "detail": {},
        }

        # Log to file and DB (non-blocking for the response)
        log_to_file(entry)
        log_to_db(entry)

        # Evaluate triggers
        try:
            from baker.triggers import evaluate_triggers
            evaluate_triggers(entry)
        except Exception:
            logger.warning("Trigger evaluation failed", exc_info=True)

        return response


class AuthMiddleware(BaseHTTPMiddleware):
    """JWT validation middleware (FR2 / FR6 / NFR3).

    When ``AUTH_REQUIRED`` is ``true``, all API requests except
    ``/api/health`` and ``/api/auth/login`` must include a valid
    ``Authorization: Bearer <token>`` header (FR2). The JWT is decoded
    in-memory (no DB lookup for role — NFR3, role is in the token claims).
    Revoked tokens (jti in the in-memory denylist) are rejected (FR21).

    When ``AUTH_REQUIRED`` is ``false`` (grace period, default), all
    requests pass through unauthenticated (FR6 / NFR6). On valid tokens
    the decoded username and role are attached to ``request.state`` for
    downstream handlers even in grace-period mode, so Phase 3+ role-gated
    dependencies can inspect them without re-decoding.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        path = request.url.path

        # Always allow public paths through (FR2).
        if path in _PUBLIC_PATHS:
            return await call_next(request)

        # Grace period: AUTH_REQUIRED=false → pass through (FR6 / NFR6).
        # Still decode the token if present so downstream handlers can use it.
        if not AUTH_REQUIRED:
            self._attach_claims_if_present(request)
            return await call_next(request)

        # AUTH_REQUIRED=true — enforce JWT validation (FR2).
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return JSONResponse(
                status_code=401,
                content={"detail": "Yêu cầu xác thực. Vui lòng đăng nhập."},
            )

        token = auth_header[len("Bearer "):].strip()
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return JSONResponse(
                status_code=401,
                content={"detail": "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."},
            )
        except jwt.InvalidTokenError:
            return JSONResponse(
                status_code=401,
                content={"detail": "Token xác thực không hợp lệ."},
            )

        # Denylist check (FR21 — Phase 4 session management integration).
        from baker.api.auth import is_jti_revoked

        jti = payload.get("jti")
        if jti and is_jti_revoked(jti):
            return JSONResponse(
                status_code=401,
                content={"detail": "Phiên đăng nhập đã bị thu hồi."},
            )

        # Attach decoded identity for downstream handlers (NFR3: no DB lookup).
        request.state.auth_username = payload.get("sub")
        request.state.auth_role = payload.get("role")

        return await call_next(request)

    @staticmethod
    def _attach_claims_if_present(request: Request) -> None:
        """Decode and attach JWT claims when a token is present in grace period.

        In ``AUTH_REQUIRED=false`` mode, a token may still be sent by
        updated clients. Decoding it here lets role-gated dependencies
        (Phase 3+) inspect ``request.state.auth_role`` without a second
        decode. Failures are silently ignored in grace-period mode.
        """
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return
        token = auth_header[len("Bearer "):].strip()
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.InvalidTokenError:
            return
        request.state.auth_username = payload.get("sub")
        request.state.auth_role = payload.get("role")
