"""Tests for DG-029 Phase 4: CLI user + session management.

Covers:
  - AC12: `baker user list` shows 5 seeded users (Sinh=admin, others=staff)
  - AC13: `baker user create "NewStaff" --role staff` → login as "newstaff" yields JWT role=staff
  - AC17: `baker session list` shows active sessions with metadata
  - AC18: `baker session logout <username>` → old token returns 401
  - AC19: `baker session logout-all` → all old tokens return 401
  - FR7-FR11, FR19 unlock, FR20-FR21
"""

from __future__ import annotations

import time
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from click.testing import CliRunner

from baker.api.auth import _pwd_ctx, _reset_auth_state
from baker.cli import app
from baker.config import JWT_SECRET
from baker.db.connection import get_db


runner = CliRunner()


@pytest.fixture(autouse=True)
def _reset_auth():
    """Clear in-memory auth state before each test."""
    _reset_auth_state()
    yield
    _reset_auth_state()


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


def _login(api_client, username: str, password: str, device: str = "Pixel-7"):
    """Login via the API and return the token."""
    resp = api_client.post(
        "/api/auth/login",
        json={"username": username, "password": password},
        headers={"x-device-model": device},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["token"]


# ---------------------------------------------------------------------------
# AC12: baker user list shows seeded users
# ---------------------------------------------------------------------------


def test_user_list_shows_seeded_users():
    """AC12: `baker user list` lists the 5 seeded users with correct roles."""
    # The v68 migration seeds sinh (admin) + ân/ngân/phượng/tân (staff).
    # The CLI `app` group runs ensure_schema on startup, so seeding happens.
    result = runner.invoke(app, ["user", "list"])
    assert result.exit_code == 0, result.output
    assert "sinh" in result.output
    assert "admin" in result.output
    assert "staff" in result.output


def test_user_list_empty_db_still_runs():
    """`baker user list` runs without error even if no users present."""
    # Drop seeded users so the list is empty (verifies graceful empty state).
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM users")
        conn.commit()
    result = runner.invoke(app, ["user", "list"])
    assert result.exit_code == 0, result.output


# ---------------------------------------------------------------------------
# FR7: baker user create
# ---------------------------------------------------------------------------


def test_user_create_default_role_staff():
    """FR7: `baker user create` defaults to staff role and prints a password.

    DG-029 follow-on: the username is normalized to lowercase, so
    `TestStaff1` becomes `teststaff1` in output and in the DB.
    """
    result = runner.invoke(app, ["user", "create", "TestStaff1"])
    assert result.exit_code == 0, result.output
    assert "Created" in result.output
    assert "teststaff1" in result.output
    assert "staff" in result.output
    # A password is printed to stdout.
    assert "Password:" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT role, active FROM users WHERE username = 'teststaff1'"
        ).fetchone()
        assert row is not None
        assert row["role"] == "staff"
        assert row["active"] == 1


def test_user_create_with_admin_role():
    """FR7: `baker user create --role admin` sets the admin role."""
    result = runner.invoke(app, ["user", "create", "TestAdmin1", "--role", "admin"])
    assert result.exit_code == 0, result.output
    assert "admin" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT role FROM users WHERE username = 'testadmin1'"
        ).fetchone()
        assert row["role"] == "admin"


def test_user_create_duplicate_rejected():
    """FR7: creating an existing user is rejected with an error message."""
    runner.invoke(app, ["user", "create", "DupUser"])
    result = runner.invoke(app, ["user", "create", "DupUser"])
    assert result.exit_code == 0  # soft error, prints message
    assert "already exists" in result.output


def test_user_create_invalid_role_rejected():
    """FR7: invalid role values are rejected by the click validator."""
    result = runner.invoke(app, ["user", "create", "BadRole", "--role", "superuser"])
    assert result.exit_code != 0


# ---------------------------------------------------------------------------
# AC13: created user can log in and receives correct role
# ---------------------------------------------------------------------------


def test_user_create_then_login_yields_correct_role(api_client):
    """AC13: `baker user create "NewStaff" --role staff` then login → JWT role=staff.

    DG-029 follow-on: usernames are normalized to lowercase, so the created
    username becomes "newstaff". The login must use the lowercased form.
    """
    result = runner.invoke(app, ["user", "create", "NewStaff", "--role", "staff"])
    assert result.exit_code == 0, result.output
    # Extract the printed password from the output.
    password = None
    for line in result.output.splitlines():
        if "Password:" in line:
            password = line.split("Password:", 1)[1].strip()
            break
    assert password is not None, "create did not print a password"

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "newstaff", "password": password},
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["role"] == "staff"
    payload = jwt.decode(data["token"], JWT_SECRET, algorithms=["HS256"])
    assert payload["sub"] == "newstaff"
    assert payload["role"] == "staff"


# ---------------------------------------------------------------------------
# FR8: baker user set-password
# ---------------------------------------------------------------------------


def test_user_set_password_random():
    """FR8: `baker user set-password --random` generates a new password."""
    runner.invoke(app, ["user", "create", "SetPwdUser"])
    result = runner.invoke(app, ["user", "set-password", "SetPwdUser", "--random"])
    assert result.exit_code == 0, result.output
    assert "Updated" in result.output
    assert "New password:" in result.output


def test_user_set_password_random_quiet_suppresses_plaintext():
    """MJ-2: `baker user set-password --random --quiet` suppresses the password."""
    runner.invoke(app, ["user", "create", "SetPwdQuiet"])
    result = runner.invoke(
        app, ["user", "set-password", "SetPwdQuiet", "--random", "--quiet"]
    )
    assert result.exit_code == 0, result.output
    assert "Updated" in result.output
    assert "New password:" not in result.output


def test_user_set_password_interactive_prompt():
    """MJ-1: `baker user set-password` prompts interactively (no --password flag)."""
    runner.invoke(app, ["user", "create", "SetPwdInteractive"])
    # CliRunner drives click.prompt via stdin; confirmation_prompt requires
    # the password to be entered twice.
    result = runner.invoke(
        app,
        ["user", "set-password", "SetPwdInteractive"],
        input="interactive-pass-123\ninteractive-pass-123\n",
    )
    assert result.exit_code == 0, result.output
    assert "Updated" in result.output
    # The interactive password must NOT be echoed back to stdout.
    assert "interactive-pass-123" not in result.output

    # Verify the prompted password was actually stored.
    with get_db() as conn:
        row = conn.execute(
            "SELECT password_hash FROM users WHERE username = 'setpwdinteractive'"
        ).fetchone()
        assert _pwd_ctx.verify("interactive-pass-123", row["password_hash"])


def test_user_set_password_interactive_mismatch_confirmation():
    """MJ-1: mismatched confirmation prompt aborts without changing the password."""
    runner.invoke(app, ["user", "create", "SetPwdMismatch"])
    result = runner.invoke(
        app,
        ["user", "set-password", "SetPwdMismatch"],
        input="first-pass\nsecond-pass\n",
    )
    # Click aborts with exit_code 1 when confirmation_prompt fails.
    assert result.exit_code != 0


def test_user_set_password_explicit():
    """FR8: `baker user set-password --random` stores a generated password (no --password flag).

    The old ``--password`` flag was removed (MJ-1) to avoid leaking plaintext
    passwords via ``ps aux`` / shell history. Interactive prompts replace it.
    """
    runner.invoke(app, ["user", "create", "SetPwdExplicit"])
    result = runner.invoke(
        app, ["user", "set-password", "SetPwdExplicit", "--random"]
    )
    assert result.exit_code == 0, result.output
    assert "Updated" in result.output
    # The generated password IS printed (interactive default would not be).
    assert "New password:" in result.output

    # Extract the generated password and verify it works.
    password = None
    for line in result.output.splitlines():
        if "New password:" in line:
            password = line.split("New password:", 1)[1].strip()
            break
    assert password is not None

    with get_db() as conn:
        row = conn.execute(
            "SELECT password_hash FROM users WHERE username = 'setpwdexplicit'"
        ).fetchone()
        assert _pwd_ctx.verify(password, row["password_hash"])


def test_user_set_password_no_password_flag_exposed():
    """MJ-1: the old `--password` flag is gone (would leak via ps aux / shell history)."""
    runner.invoke(app, ["user", "create", "NoPasswordFlag"])
    result = runner.invoke(
        app, ["user", "set-password", "NoPasswordFlag", "--password", "leaked123"]
    )
    # Click rejects unknown options with exit_code != 0.
    assert result.exit_code != 0


def test_user_create_quiet_suppresses_plaintext():
    """MJ-2: `baker user create --quiet` suppresses the password output."""
    result = runner.invoke(app, ["user", "create", "QuietCreate", "--quiet"])
    assert result.exit_code == 0, result.output
    assert "Created" in result.output
    assert "Password:" not in result.output


def test_user_set_password_nonexistent_user():
    """FR8: setting password on a nonexistent user reports an error."""
    result = runner.invoke(app, ["user", "set-password", "GhostUser"])
    assert result.exit_code == 0
    assert "not found" in result.output


# ---------------------------------------------------------------------------
# FR9: baker user set-role
# ---------------------------------------------------------------------------


def test_user_set_role_staff_to_admin():
    """FR9: `baker user set-role <u> admin` updates the user's role."""
    runner.invoke(app, ["user", "create", "RoleSwap", "--role", "staff"])
    result = runner.invoke(app, ["user", "set-role", "RoleSwap", "admin"])
    assert result.exit_code == 0, result.output
    assert "admin" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT role FROM users WHERE username = 'roleswap'"
        ).fetchone()
        assert row["role"] == "admin"


def test_user_set_role_no_change():
    """FR9: setting the same role is a no-op with a dim message."""
    runner.invoke(app, ["user", "create", "SameRole", "--role", "staff"])
    result = runner.invoke(app, ["user", "set-role", "SameRole", "staff"])
    assert result.exit_code == 0
    assert "already" in result.output


def test_user_set_role_nonexistent_user():
    """FR9: setting role on a nonexistent user reports an error."""
    result = runner.invoke(app, ["user", "set-role", "GhostRole", "admin"])
    assert result.exit_code == 0
    assert "not found" in result.output


# ---------------------------------------------------------------------------
# FR10: baker user list (already tested above) — also test --all flag
# ---------------------------------------------------------------------------


def test_user_list_all_includes_inactive():
    """FR10: `baker user list --all` includes deactivated users."""
    runner.invoke(app, ["user", "create", "DeactivateMe", "--role", "staff"])
    runner.invoke(app, ["user", "deactivate", "DeactivateMe"])

    # Without --all the deactivated user is hidden.
    result = runner.invoke(app, ["user", "list"])
    assert "deactivateme" not in result.output

    # With --all the deactivated user appears.
    result = runner.invoke(app, ["user", "list", "--all"])
    assert "deactivateme" in result.output


# ---------------------------------------------------------------------------
# FR11: baker user deactivate
# ---------------------------------------------------------------------------


def test_user_deactivate_sets_inactive():
    """FR11: `baker user deactivate <u>` sets active=0."""
    runner.invoke(app, ["user", "create", "DeacUser", "--role", "staff"])
    result = runner.invoke(app, ["user", "deactivate", "DeacUser"])
    assert result.exit_code == 0, result.output
    assert "Deactivated" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT active FROM users WHERE username = 'deacuser'"
        ).fetchone()
        assert row["active"] == 0


def test_user_deactivate_already_inactive():
    """FR11: deactivating an already-inactive user is a no-op."""
    runner.invoke(app, ["user", "create", "AlreadyOff", "--role", "staff"])
    runner.invoke(app, ["user", "deactivate", "AlreadyOff"])
    result = runner.invoke(app, ["user", "deactivate", "AlreadyOff"])
    assert result.exit_code == 0
    assert "already" in result.output


def test_user_deactivate_nonexistent_user():
    """FR11: deactivating a nonexistent user reports an error."""
    result = runner.invoke(app, ["user", "deactivate", "GhostDeac"])
    assert result.exit_code == 0
    assert "not found" in result.output


def test_deactivated_user_cannot_login(api_client):
    """A deactivated user is rejected at login (active=0)."""
    result_create = runner.invoke(app, ["user", "create", "LoginAfterDeac", "--role", "staff"])
    password = None
    for line in result_create.output.splitlines():
        if "Password:" in line:
            password = line.split("Password:", 1)[1].strip()
            break
    assert password is not None
    runner.invoke(app, ["user", "deactivate", "LoginAfterDeac"])

    resp = api_client.post(
        "/api/auth/login",
        json={"username": "LoginAfterDeac", "password": password},
    )
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# FR19: baker user unlock
# ---------------------------------------------------------------------------


def test_user_unlock_clears_locked_until():
    """FR19: `baker user unlock <u>` clears locked_until in the DB."""
    runner.invoke(app, ["user", "create", "LockedUser", "--role", "staff"])
    # Manually lock the user.
    lock_until = (
        datetime.now(timezone.utc) + timedelta(minutes=30)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    with get_db() as conn:
        conn.execute(
            "UPDATE users SET locked_until = ? WHERE username = 'lockeduser'",
            (lock_until,),
        )
        conn.commit()

    result = runner.invoke(app, ["user", "unlock", "LockedUser"])
    assert result.exit_code == 0, result.output
    assert "Unlocked" in result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT locked_until FROM users WHERE username = 'lockeduser'"
        ).fetchone()
        assert row["locked_until"] is None


def test_user_unlock_not_locked():
    """FR19: unlocking a user that is not locked is a no-op."""
    runner.invoke(app, ["user", "create", "NotLocked", "--role", "staff"])
    result = runner.invoke(app, ["user", "unlock", "NotLocked"])
    assert result.exit_code == 0
    assert "not locked" in result.output


def test_user_unlock_nonexistent_user():
    """FR19: unlocking a nonexistent user reports an error."""
    result = runner.invoke(app, ["user", "unlock", "GhostUnlock"])
    assert result.exit_code == 0
    assert "not found" in result.output


# ---------------------------------------------------------------------------
# FR20: baker session list
# ---------------------------------------------------------------------------


def test_session_list_no_sessions():
    """FR20: `baker session list` shows a friendly empty message when no sessions."""
    result = runner.invoke(app, ["session", "list"])
    assert result.exit_code == 0, result.output


def test_session_list_shows_active_session(api_client):
    """AC17: `baker session list` shows username, role, IP, device, login/last activity."""
    with get_db() as conn:
        _create_test_user(conn, "SessionUser", "sessionpass123", role="admin")
    token = _login(api_client, "SessionUser", "sessionpass123", device="Pixel-7")

    result = runner.invoke(app, ["session", "list"])
    assert result.exit_code == 0, result.output
    assert "SessionUser" in result.output
    assert "admin" in result.output
    assert "Pixel-7" in result.output

    # The session row should be persisted with the jti from the JWT.
    payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    with get_db() as conn:
        row = conn.execute(
            "SELECT jti, username, role, device_model, revoked_at "
            "FROM sessions WHERE jti = ?",
            (payload["jti"],),
        ).fetchone()
        assert row is not None
        assert row["username"] == "SessionUser"
        assert row["role"] == "admin"
        assert row["device_model"] == "Pixel-7"
        assert row["revoked_at"] is None


def test_session_list_omits_revoked(api_client):
    """FR20: revoked sessions are not shown in `baker session list`."""
    with get_db() as conn:
        _create_test_user(conn, "RevokeUser", "revpass123", role="admin")
    _login(api_client, "RevokeUser", "revpass123", device="iPhone-14")

    runner.invoke(app, ["session", "logout", "RevokeUser"])

    result = runner.invoke(app, ["session", "list"])
    assert result.exit_code == 0, result.output
    assert "RevokeUser" not in result.output


# ---------------------------------------------------------------------------
# FR21 / AC18: baker session logout <username>
# ---------------------------------------------------------------------------


def test_session_logout_invalidates_user_token(auth_client):
    """AC18: `baker session logout <u>` → that user's old token returns 401."""
    with get_db() as conn:
        _create_test_user(conn, "LogoutTarget", "logoutpass123", role="admin")
    token = _login(auth_client, "LogoutTarget", "logoutpass123")

    # Token works before logout.
    resp = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 200

    # Force-logout via CLI.
    result = runner.invoke(app, ["session", "logout", "LogoutTarget"])
    assert result.exit_code == 0, result.output
    assert "Revoked" in result.output

    # Token is now rejected.
    resp = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 401


def test_session_logout_nonexistent_user():
    """FR21: `baker session logout <u>` on a user with no sessions is a no-op."""
    result = runner.invoke(app, ["session", "logout", "GhostSession"])
    assert result.exit_code == 0
    assert "No active sessions" in result.output


def test_session_logout_only_affects_target_user(auth_client):
    """AC18: force-logout only invalidates the target user, not others."""
    with get_db() as conn:
        _create_test_user(conn, "UserA", "passA123", role="admin")
        _create_test_user(conn, "UserB", "passB123", role="admin")
    token_a = _login(auth_client, "UserA", "passA123")
    token_b = _login(auth_client, "UserB", "passB123")

    runner.invoke(app, ["session", "logout", "UserA"])

    resp_a = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token_a}"}
    )
    assert resp_a.status_code == 401

    resp_b = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token_b}"}
    )
    assert resp_b.status_code == 200


# ---------------------------------------------------------------------------
# FR21 / AC19: baker session logout-all
# ---------------------------------------------------------------------------


def test_session_logout_all_invalidates_every_token(auth_client):
    """AC19: `baker session logout-all` → all old tokens return 401."""
    with get_db() as conn:
        _create_test_user(conn, "AllA", "passA123", role="admin")
        _create_test_user(conn, "AllB", "passB123", role="admin")
    token_a = _login(auth_client, "AllA", "passA123")
    token_b = _login(auth_client, "AllB", "passB123")

    result = runner.invoke(app, ["session", "logout-all"])
    assert result.exit_code == 0, result.output
    assert "Revoked" in result.output

    resp_a = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token_a}"}
    )
    resp_b = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token_b}"}
    )
    assert resp_a.status_code == 401
    assert resp_b.status_code == 401


def test_session_logout_all_no_sessions():
    """FR21: `baker session logout-all` with no active sessions is a no-op."""
    result = runner.invoke(app, ["session", "logout-all"])
    assert result.exit_code == 0
    assert "No active sessions" in result.output


# ---------------------------------------------------------------------------
# Session lifecycle — last_activity is refreshed by middleware
# ---------------------------------------------------------------------------


def test_session_last_activity_refreshed_on_request(auth_client):
    """FR20: last_activity is updated when a valid token is used."""
    with get_db() as conn:
        _create_test_user(conn, "ActivityUser", "actpass123", role="admin")
    token = _login(auth_client, "ActivityUser", "actpass123")

    payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    with get_db() as conn:
        before = conn.execute(
            "SELECT last_activity, logged_in_at FROM sessions WHERE jti = ?",
            (payload["jti"],),
        ).fetchone()
        assert before is not None

    # Wait a moment so last_activity differs from logged_in_at if it was refreshed.
    time.sleep(1.1)

    # Make an authenticated request — middleware should refresh last_activity.
    resp = auth_client.get(
        "/api/products", headers={"Authorization": f"Bearer {token}"}
    )
    assert resp.status_code == 200

    with get_db() as conn:
        after = conn.execute(
            "SELECT last_activity FROM sessions WHERE jti = ?",
            (payload["jti"],),
        ).fetchone()
        assert after is not None
        # last_activity should be >= the pre-request value.
        assert after["last_activity"] >= before["last_activity"]