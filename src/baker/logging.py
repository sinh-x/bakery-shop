"""Server logging — file + DB structured logging for Baker API."""

import json
import logging
import sqlite3
from datetime import datetime
from pathlib import Path

from starlette.requests import Request

import baker.config
from baker.db.connection import get_db


logger = logging.getLogger("baker.server")


def setup_logging() -> None:
    """Configure Python logging with JSON-lines file handler."""
    log_dir = baker.config.LOG_DIR
    log_dir.mkdir(parents=True, exist_ok=True)

    level = getattr(logging, baker.config.LOG_LEVEL, logging.INFO)
    logger.setLevel(level)

    # Avoid duplicate handlers on reload
    if not logger.handlers:
        today = datetime.now().strftime("%Y-%m-%d")
        file_path = log_dir / f"server-{today}.log"
        handler = logging.FileHandler(str(file_path), encoding="utf-8")
        handler.setLevel(level)

        class JsonFormatter(logging.Formatter):
            def format(self, record):
                entry = {
                    "timestamp": datetime.now().isoformat(),
                    "level": record.levelname,
                    "message": record.getMessage(),
                }
                if hasattr(record, "extra_data"):
                    entry.update(record.extra_data)
                return json.dumps(entry, ensure_ascii=False)

        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)


def log_to_file(entry: dict) -> None:
    """Write a structured log entry to the daily JSON-lines file."""
    log_dir = baker.config.LOG_DIR
    log_dir.mkdir(parents=True, exist_ok=True)
    today = datetime.now().strftime("%Y-%m-%d")
    file_path = log_dir / f"server-{today}.log"
    line = json.dumps(entry, ensure_ascii=False)
    with open(file_path, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def log_to_db(entry: dict) -> None:
    """Insert a structured log entry into the server_logs table."""
    try:
        with get_db() as conn:
            conn.execute(
                """INSERT INTO server_logs
                   (timestamp, level, method, path, status_code, duration_ms,
                    client_ip, device_model, app_version, os_version,
                    ref_type, ref_id, message, detail)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    entry.get("timestamp", datetime.now().isoformat()),
                    entry.get("level", "INFO"),
                    entry.get("method", ""),
                    entry.get("path", ""),
                    entry.get("status_code", 0),
                    entry.get("duration_ms", 0),
                    entry.get("client_ip", ""),
                    entry.get("device_model", ""),
                    entry.get("app_version", ""),
                    entry.get("os_version", ""),
                    entry.get("ref_type", ""),
                    entry.get("ref_id"),
                    entry.get("message", ""),
                    json.dumps(entry.get("detail", {}), ensure_ascii=False),
                ),
            )
    except (sqlite3.Error, TypeError, ValueError):
        # Never let DB logging failure crash the request
        logger.warning("Failed to write log to DB", exc_info=True)


def log_context(request: Request, ref_type: str = "", ref_id: int | None = None) -> None:
    """Attach DB item reference to the current request for the logging middleware."""
    if not hasattr(request.state, "_log_ctx"):
        request.state._log_ctx = {}
    if ref_type:
        request.state._log_ctx["ref_type"] = ref_type
    if ref_id is not None:
        request.state._log_ctx["ref_id"] = ref_id
