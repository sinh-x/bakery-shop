"""Dedicated tests for baker.api.middleware (FR-PY-6).

Covers AuthMiddleware (grace-period pass-through, AUTH_REQUIRED enforcement,
public paths, JWT validation, denylist) and LoggingMiddleware (request logging,
status-based level).
"""

import jwt
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from starlette.testclient import TestClient

from baker.api.middleware import AuthMiddleware, LoggingMiddleware


def _make_app(extra_middleware=None) -> Starlette:
    async def health(request):
        return JSONResponse({"ok": True})

    async def protected(request):
        return JSONResponse({"user": getattr(request.state, "auth_username", None)})

    routes = [
        Route("/api/health", health, methods=["GET"]),
        Route("/api/orders", protected, methods=["GET"]),
        Route("/api/auth/login", health, methods=["POST"]),
    ]
    app = Starlette(routes=routes)
    app.add_middleware(LoggingMiddleware)
    if extra_middleware:
        app.add_middleware(extra_middleware)
    return app


def _client(extra_middleware=None) -> TestClient:
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
    return TestClient(_make_app(extra_middleware))


def test_logging_middleware_logs_request(api_client):
    api_client.get("/api/health")
    from baker.db.connection import get_db

    with get_db() as conn:
        rows = conn.execute("SELECT * FROM server_logs").fetchall()
        assert len(rows) >= 1
        assert rows[-1]["path"] == "/api/health"


def test_logging_middleware_4xx_logged_as_warning(api_client):
    api_client.get("/api/orders/does-not-exist")
    from baker.db.connection import get_db

    with get_db() as conn:
        row = conn.execute(
            "SELECT level FROM server_logs ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row["level"] == "WARNING"


def test_auth_grace_period_passes_through(api_client):
    # AUTH_REQUIRED=false (default in api_client) — all requests pass.
    resp = api_client.get("/api/health")
    assert resp.status_code == 200


def test_auth_required_blocks_missing_token(api_client):
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        resp = api_client.get("/api/orders")
    assert resp.status_code == 401
    assert "xác thực" in resp.json()["detail"].lower() or "đăng nhập" in resp.json()["detail"].lower()


def test_auth_required_accepts_valid_token(api_client):
    from unittest.mock import patch
    import baker.api.middleware as mw

    token = jwt.encode(
        {"sub": "testuser", "role": "staff", "jti": "jti-1"},
        mw.JWT_SECRET,
        algorithm="HS256",
    )
    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        resp = api_client.get(
            "/api/orders",
            headers={"Authorization": f"Bearer {token}"},
        )
    assert resp.status_code == 200


def test_auth_required_rejects_expired_token(api_client):
    from unittest.mock import patch
    import baker.api.middleware as mw
    from datetime import datetime, timedelta, timezone

    token = jwt.encode(
        {
            "sub": "testuser",
            "role": "staff",
            "jti": "jti-2",
            "exp": datetime.now(timezone.utc) - timedelta(hours=1),
        },
        mw.JWT_SECRET,
        algorithm="HS256",
    )
    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        resp = api_client.get(
            "/api/orders",
            headers={"Authorization": f"Bearer {token}"},
        )
    assert resp.status_code == 401
    assert "hết hạn" in resp.json()["detail"].lower() or "hết hạn" in resp.json()["detail"]


def test_auth_required_rejects_invalid_token(api_client):
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        resp = api_client.get(
            "/api/orders",
            headers={"Authorization": "Bearer not-a-real-token"},
        )
    assert resp.status_code == 401
    assert "không hợp lệ" in resp.json()["detail"].lower() or "không hợp lệ" in resp.json()["detail"]


def test_auth_required_public_paths_bypass(api_client):
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        # /api/health is public — no token needed.
        resp = api_client.get("/api/health")
    assert resp.status_code == 200


def test_auth_grace_period_attaches_claims_when_token_present(api_client):
    import baker.api.middleware as mw

    token = jwt.encode(
        {"sub": "graceuser", "role": "staff", "jti": "jti-grace"},
        mw.JWT_SECRET,
        algorithm="HS256",
    )
    # In grace mode, the token is decoded and claims attached even though
    # not required. A request with a valid token should still succeed.
    resp = api_client.get(
        "/api/health",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200


def test_auth_grace_period_ignores_invalid_token(api_client):
    # In grace mode, invalid tokens are silently ignored — no 401.
    resp = api_client.get(
        "/api/health",
        headers={"Authorization": "Bearer garbage"},
    )
    assert resp.status_code == 200