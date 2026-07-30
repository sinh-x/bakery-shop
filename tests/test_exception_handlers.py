"""Dedicated tests for baker.api.exception_handlers (FR-PY-6).

Covers global_exception_handler — returns 500 with sanitized Vietnamese
message, logs the exception to server_logs with type/message, and avoids
leaking tracebacks.
"""

import asyncio
import json

from starlette.requests import Request

from baker.api.exception_handlers import global_exception_handler


def _make_request(path: str = "/api/test-crash") -> Request:
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": path,
            "headers": [],
            "client": ("127.0.0.1", 12345),
            "scheme": "http",
            "server": ("testserver", 80),
            "query_string": b"",
            "root_path": "",
            "http_version": "1.1",
        }
    )


def test_global_exception_handler_returns_500(api_client):
    request = _make_request()
    response = asyncio.run(global_exception_handler(request, RuntimeError("boom")))
    assert response.status_code == 500
    body = json.loads(response.body)
    assert body["detail"] == "Lỗi máy chủ nội bộ"


def test_global_exception_handler_logs_error_type_and_message(api_client):
    request = _make_request("/api/crash-detail")
    asyncio.run(global_exception_handler(request, ValueError("bad value")))
    from baker.db.connection import get_db

    with get_db() as conn:
        row = conn.execute(
            "SELECT detail, message FROM server_logs ORDER BY id DESC LIMIT 1"
        ).fetchone()
        detail = json.loads(row["detail"])
        assert detail["error_type"] == "ValueError"
        assert detail["error_message"] == "bad value"
        assert "ValueError" in row["message"]
        assert "bad value" in row["message"]


def test_global_exception_handler_does_not_leak_traceback(api_client):
    request = _make_request()
    asyncio.run(global_exception_handler(request, RuntimeError("trace-test")))
    from baker.db.connection import get_db

    with get_db() as conn:
        row = conn.execute(
            "SELECT detail FROM server_logs ORDER BY id DESC LIMIT 1"
        ).fetchone()
        detail = json.loads(row["detail"])
        assert "traceback" not in detail
        assert "tb" not in detail


def test_global_exception_handler_captures_device_headers(api_client):
    request = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/crash-headers",
            "headers": [
                (b"x-device-model", b"iPhone 15"),
                (b"x-app-version", b"1.0.0"),
                (b"x-os-version", b"iOS 17"),
            ],
            "client": ("10.0.0.1", 54321),
            "scheme": "http",
            "server": ("testserver", 80),
            "query_string": b"",
            "root_path": "",
            "http_version": "1.1",
        }
    )
    asyncio.run(global_exception_handler(request, RuntimeError("device crash")))
    from baker.db.connection import get_db

    with get_db() as conn:
        row = conn.execute(
            "SELECT device_model, app_version, os_version, client_ip FROM server_logs ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row["device_model"] == "iPhone 15"
        assert row["app_version"] == "1.0.0"
        assert row["os_version"] == "iOS 17"
        assert row["client_ip"] == "10.0.0.1"