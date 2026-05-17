"""Tests for server logging system (DG-018)."""

import asyncio
import json

import pytest
from starlette.requests import Request

from baker.api.exception_handlers import global_exception_handler


class TestLoggingMiddleware:
    """AC1: Every API request produces a row in server_logs."""

    def test_request_creates_log_entry(self, api_client):
        """Health check request should produce a server_logs row."""
        api_client.get("/api/health")

        from baker.db.connection import get_db
        with get_db() as conn:
            rows = conn.execute("SELECT * FROM server_logs").fetchall()
            assert len(rows) >= 1
            row = rows[-1]
            assert row["method"] == "GET"
            assert row["path"] == "/api/health"
            assert row["status_code"] == 200
            assert row["duration_ms"] >= 0

    def test_device_headers_logged(self, api_client):
        """AC2: Device headers are captured in server_logs."""
        api_client.get(
            "/api/health",
            headers={
                "X-App-Version": "0.2.2+8",
                "X-Device-Model": "Samsung Galaxy S24",
                "X-OS-Version": "Android 14",
            },
        )

        from baker.db.connection import get_db
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM server_logs ORDER BY id DESC LIMIT 1"
            ).fetchone()
            assert row["app_version"] == "0.2.2+8"
            assert row["device_model"] == "Samsung Galaxy S24"
            assert row["os_version"] == "Android 14"

    def test_error_response_logged_as_warning(self, api_client):
        """4xx responses logged at WARNING level."""
        api_client.get("/api/orders/nonexistent")

        from baker.db.connection import get_db
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM server_logs ORDER BY id DESC LIMIT 1"
            ).fetchone()
            assert row["level"] == "WARNING"
            assert row["status_code"] == 404


class TestLogContext:
    """AC3: Order creation produces a log entry with ref_type and ref_id."""

    def test_create_order_has_ref(self, api_client):
        """Creating an order logs ref_type=order, ref_id=<id>."""
        resp = api_client.post(
            "/api/orders",
            json={
                "customerName": "Test Customer",
                "customerPhone": "0123456789",
                "items": [
                    {
                        "productName": "Bánh mì",
                        "quantity": 1,
                        "unitPrice": 10000,
                    }
                ],
            },
        )
        assert resp.status_code == 201
        order_id = resp.json()["id"]

        from baker.db.connection import get_db
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM server_logs WHERE ref_type = 'order' AND ref_id = ?",
                (order_id,),
            ).fetchone()
            assert row is not None
            assert row["method"] == "POST"
            assert "/api/orders" in row["path"]


class TestFileLogging:
    """AC9: Log files appear in JSON-lines format."""

    def test_log_file_created(self, api_client, tmp_path):
        """API request creates a JSON-lines log file."""
        api_client.get("/api/health")

        import baker.config
        log_dir = baker.config.LOG_DIR
        log_files = list(log_dir.glob("server-*.log"))
        assert len(log_files) >= 1

        with open(log_files[0]) as f:
            lines = f.readlines()
            assert len(lines) >= 1
            entry = json.loads(lines[-1])
            assert "timestamp" in entry
            assert entry["method"] == "GET"
            assert entry["path"] == "/api/health"


class TestServerLogCLI:
    """AC5, AC6: baker server-log list shows entries with filters."""

    def test_list_shows_entries(self, api_client):
        """server-log list shows recent entries."""
        # Generate some log entries
        api_client.get("/api/health")
        api_client.get("/api/health")

        from click.testing import CliRunner
        from baker.cli import app

        runner = CliRunner()
        result = runner.invoke(app, ["server-log", "list"])
        assert result.exit_code == 0
        assert "Server Logs" in result.output

    def test_list_filter_by_level(self, api_client):
        """server-log list --level filters correctly."""
        api_client.get("/api/health")
        api_client.get("/api/orders/nonexistent")  # 404 → WARNING

        from click.testing import CliRunner
        from baker.cli import app

        runner = CliRunner()
        result = runner.invoke(app, ["server-log", "list", "--level", "WARNING"])
        assert result.exit_code == 0

    def test_search(self, api_client):
        """server-log search finds matching entries."""
        api_client.get("/api/health")

        from click.testing import CliRunner
        from baker.cli import app

        runner = CliRunner()
        result = runner.invoke(app, ["server-log", "search", "health"])
        assert result.exit_code == 0


class TestMigrationV15:
    """Migration creates server_logs and log_triggers tables."""

    def test_tables_exist(self, api_client):
        """Both tables should exist after migration."""
        from baker.db.connection import get_db
        with get_db() as conn:
            tables = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name IN ('server_logs', 'log_triggers') ORDER BY name"
            ).fetchall()
            names = [t["name"] for t in tables]
            assert "log_triggers" in names
            assert "server_logs" in names


class TestTriggerSystem:
    """AC8: Trigger rules fire when conditions match."""

    def test_trigger_evaluation(self, api_client):
        """A trigger matching ERROR level fires (logged, no Zalo in test)."""
        from baker.db.connection import get_db

        # Insert a log-type trigger for ERROR level
        with get_db() as conn:
            conn.execute(
                "INSERT INTO log_triggers (name, condition, action, active) "
                "VALUES (?, ?, ?, 1)",
                (
                    "test-error-trigger",
                    json.dumps({"level": "ERROR"}),
                    json.dumps({"type": "log"}),
                ),
            )

        from baker.triggers import evaluate_triggers
        entry = {
            "timestamp": "2026-03-24T10:00:00",
            "level": "ERROR",
            "method": "POST",
            "path": "/api/orders",
            "status_code": 500,
            "duration_ms": 100,
            "client_ip": "127.0.0.1",
            "message": "Test error",
        }
        # Should not raise
        evaluate_triggers(entry)

        # Check last_fired was updated
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM log_triggers WHERE name = 'test-error-trigger'"
            ).fetchone()
            assert row["last_fired"] is not None

    def test_trigger_cooldown(self, api_client):
        """Trigger respects cooldown — does not fire twice within cooldown period."""
        from baker.db.connection import get_db

        with get_db() as conn:
            conn.execute(
                "INSERT INTO log_triggers (name, condition, action, active, cooldown_seconds) "
                "VALUES (?, ?, ?, 1, 3600)",
                (
                    "cooldown-trigger",
                    json.dumps({"level": "ERROR"}),
                    json.dumps({"type": "log"}),
                ),
            )

        from baker.triggers import evaluate_triggers
        entry = {"level": "ERROR", "method": "GET", "path": "/test", "status_code": 500, "message": "err"}

        evaluate_triggers(entry)

        from baker.db.connection import get_db
        with get_db() as conn:
            row = conn.execute("SELECT last_fired FROM log_triggers WHERE name = 'cooldown-trigger'").fetchone()
            first_fired = row["last_fired"]

        # Fire again — should be suppressed by cooldown
        evaluate_triggers(entry)

        with get_db() as conn:
            row = conn.execute("SELECT last_fired FROM log_triggers WHERE name = 'cooldown-trigger'").fetchone()
            assert row["last_fired"] == first_fired  # Unchanged because of cooldown


def test_global_exception_handler_persists_sanitized_detail(api_client):
    request = Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/api/test-crash",
            "headers": [],
            "client": ("127.0.0.1", 12345),
            "scheme": "http",
            "server": ("testserver", 80),
            "query_string": b"",
            "root_path": "",
            "http_version": "1.1",
        }
    )

    response = asyncio.run(global_exception_handler(request, RuntimeError("boom")))
    assert response.status_code == 500

    from baker.db.connection import get_db

    with get_db() as conn:
        row = conn.execute("SELECT detail FROM server_logs ORDER BY id DESC LIMIT 1").fetchone()
        detail = json.loads(row["detail"])
        assert detail["error_type"] == "RuntimeError"
        assert detail["error_message"] == "boom"
        assert "traceback" not in detail
