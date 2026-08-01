"""Tests for DG-319 Phase 2: admin CLI force-change flag.

Covers FR7: ``baker user set-password --force-change`` sets
``force_password_change = 1`` on the user row. The flag is cleared by the
self-service password change endpoint (FR10, implemented in Phase 1).
"""

from __future__ import annotations

import pytest
from click.testing import CliRunner

from baker.api.auth import _pwd_ctx, _reset_auth_state
from baker.cli import app
from baker.db.connection import get_db

pytestmark = pytest.mark.critical

runner = CliRunner()


@pytest.fixture(autouse=True)
def _reset_auth():
    """Clear in-memory auth state before each test."""
    _reset_auth_state()
    yield
    _reset_auth_state()


def _create_test_user(conn, username: str, password: str = "initial-pass-1") -> None:
    """Insert a test user with a known bcrypt-hashed password."""
    hashed = _pwd_ctx.hash(password)
    conn.execute(
        "INSERT INTO users (username, password_hash, role, active) "
        "VALUES (?, ?, ?, 1)",
        (username, hashed, "staff"),
    )
    conn.commit()


def test_set_password_force_change_random_sets_flag():
    """FR7/AC7: `--force-change --random` updates the password AND sets the flag."""
    runner.invoke(app, ["user", "create", "ForceChgRand"])
    result = runner.invoke(
        app,
        ["user", "set-password", "ForceChgRand", "--random", "--force-change"],
    )
    assert result.exit_code == 0, result.output
    assert "Updated" in result.output
    assert "force_password_change=1" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT force_password_change FROM users WHERE username = 'forcechgrand'"
        ).fetchone()
        assert row is not None
        assert row["force_password_change"] == 1


def test_set_password_force_change_interactive_sets_flag():
    """FR7: `--force-change` with interactive prompt also sets the flag."""
    runner.invoke(app, ["user", "create", "ForceChgInter"])
    result = runner.invoke(
        app,
        ["user", "set-password", "ForceChgInter", "--force-change"],
        input="new-pass-123\nnew-pass-123\n",
    )
    assert result.exit_code == 0, result.output
    assert "force_password_change=1" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT force_password_change FROM users WHERE username = 'forcechginter'"
        ).fetchone()
        assert row is not None
        assert row["force_password_change"] == 1

        # Password should also be updated.
        hash_row = conn.execute(
            "SELECT password_hash FROM users WHERE username = 'forcechginter'"
        ).fetchone()
        assert _pwd_ctx.verify("new-pass-123", hash_row["password_hash"])


def test_set_password_without_force_change_leaves_flag_zero():
    """FR7: omitting `--force-change` leaves force_password_change at default 0."""
    runner.invoke(app, ["user", "create", "NoForceChg"])
    result = runner.invoke(
        app, ["user", "set-password", "NoForceChg", "--random"]
    )
    assert result.exit_code == 0, result.output
    assert "force_password_change=1" not in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT force_password_change FROM users WHERE username = 'noforcechg'"
        ).fetchone()
        assert row is not None
        assert row["force_password_change"] == 0


def test_set_password_force_change_nonexistent_user():
    """FR7: `--force-change` on a nonexistent user reports an error, no DB write."""
    result = runner.invoke(
        app, ["user", "set-password", "GhostForce", "--random", "--force-change"]
    )
    assert result.exit_code == 0
    assert "not found" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM users WHERE username = 'ghostforce'"
        ).fetchone()
        assert row is None


def test_set_password_force_change_idempotent_when_already_set():
    """FR7: re-running `--force-change` keeps force_password_change = 1."""
    runner.invoke(app, ["user", "create", "ForceChgTwice"])
    runner.invoke(
        app,
        ["user", "set-password", "ForceChgTwice", "--random", "--force-change"],
    )
    result = runner.invoke(
        app,
        ["user", "set-password", "ForceChgTwice", "--random", "--force-change"],
    )
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT force_password_change FROM users WHERE username = 'forcechgtwice'"
        ).fetchone()
        assert row is not None
        assert row["force_password_change"] == 1


def test_set_password_force_change_with_quiet_still_sets_flag():
    """FR7: `--quiet` only suppresses stdout; the flag is still set in the DB."""
    runner.invoke(app, ["user", "create", "ForceChgQuiet"])
    result = runner.invoke(
        app,
        [
            "user",
            "set-password",
            "ForceChgQuiet",
            "--random",
            "--force-change",
            "--quiet",
        ],
    )
    assert result.exit_code == 0, result.output
    assert "New password:" not in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT force_password_change FROM users WHERE username = 'forcechgquiet'"
        ).fetchone()
        assert row is not None
        assert row["force_password_change"] == 1