import sqlite3
from pathlib import Path

import pytest
from click.testing import CliRunner

from baker.cli import app
from baker.commands.db import db_cmd
from baker.db.schema import MIGRATIONS

runner = CliRunner()

LATEST_VERSION = max(MIGRATIONS.keys())


def test_db_status_fresh_db():
    """baker db status on a fresh DB (schema not yet applied) shows version 0 and all pending."""
    # Invoke db_cmd directly (bypasses app group which calls ensure_schema)
    result = runner.invoke(db_cmd, ["status"])
    assert result.exit_code == 0
    assert "Current schema version : 0" in result.output
    assert f"Latest available       : {LATEST_VERSION}" in result.output
    assert f"Pending migrations     : {LATEST_VERSION}" in result.output


def test_db_status_after_ensure_schema():
    """baker db status after ensure_schema shows current version and up to date."""
    # Invoke through app — group handler calls ensure_schema first
    result = runner.invoke(app, ["db", "status"])
    assert result.exit_code == 0
    assert f"Current schema version : {LATEST_VERSION}" in result.output
    assert f"Latest available       : {LATEST_VERSION}" in result.output
    assert "Status                 : up to date" in result.output
    assert "Applied migrations:" in result.output


def test_db_backup_creates_timestamped_file(tmp_path, use_memory_db):
    """baker db backup creates a file with the expected name pattern."""
    import baker.config

    # DB must exist first — invoke app to create it
    runner.invoke(app, ["db", "status"])
    assert baker.config.DB_PATH.exists()

    result = runner.invoke(app, ["db", "backup"])
    assert result.exit_code == 0
    assert "Backup created:" in result.output

    # Find the backup file in the same directory as DB
    backup_files = list(baker.config.DB_PATH.parent.glob("baker-backup-*.db"))
    assert len(backup_files) == 1, f"Expected 1 backup file, found: {backup_files}"


def test_db_backup_dest_option(tmp_path, use_memory_db):
    """baker db backup --dest /path/to/file creates backup at given path."""
    import baker.config

    # Create DB
    runner.invoke(app, ["db", "status"])
    assert baker.config.DB_PATH.exists()

    dest = tmp_path / "custom-backup.db"
    result = runner.invoke(app, ["db", "backup", "--dest", str(dest)])
    assert result.exit_code == 0
    assert "Backup created:" in result.output
    assert dest.exists()


def test_db_backup_is_valid_sqlite(tmp_path, use_memory_db):
    """The backup file is a valid SQLite database."""
    import baker.config

    # Create DB with schema
    runner.invoke(app, ["db", "status"])
    assert baker.config.DB_PATH.exists()

    dest = tmp_path / "backup.db"
    result = runner.invoke(app, ["db", "backup", "--dest", str(dest)])
    assert result.exit_code == 0
    assert dest.exists()

    # Connect and verify it's a valid SQLite DB with expected tables
    conn = sqlite3.connect(str(dest))
    tables = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()
    conn.close()

    table_names = {row[0] for row in tables}
    assert "events" in table_names
    assert "schema_version" in table_names
