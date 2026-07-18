"""CLI command group for user account management (DG-029 Phase 4).

Implements FR7-FR11 + FR19 unlock extension:
  - ``baker user create <username> --role <admin|staff>``  (FR7)
  - ``baker user set-password <username>``                 (FR8)
  - ``baker user set-role <username> <admin|staff>``       (FR9)
  - ``baker user list``                                    (FR10)
  - ``baker user deactivate <username>``                   (FR11)
  - ``baker user unlock <username>``                       (FR19)

Passwords are hashed with bcrypt (cost factor 12, NFR4) via passlib.
``create`` generates a random password and prints it to stdout so the
admin can distribute credentials (unless ``--quiet`` is passed for
CI/scripted runs). ``set-password`` prompts for a new password
interactively (hidden input + confirmation) matching standard ``passwd``
UX; when ``--random`` is passed instead, a random password is generated
and printed. Both commands accept ``--quiet`` to suppress the plaintext
password stdout output for CI/scripted use (MJ-1/MJ-2, DG-029 phase 5.6-c1).
"""

from __future__ import annotations

import os
import secrets
import sqlite3
from datetime import datetime, timezone

import click
from passlib.context import CryptContext
from rich.console import Console
from rich.table import Table

from baker.config import BCRYPT_ROUNDS
from baker.db.connection import get_db
from baker.db.schema import _strip_diacritics

console = Console()

# bcrypt password hashing context (NFR4: cost factor 12 in prod). Kept in sync
# with the auth module and v68 migration seeding. BCRYPT_ROUNDS defaults to 12
# in production; tests override it via BAKER_BCRYPT_ROUNDS (DG-029 Post-UAT
# Follow-up Item 1).
_pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=BCRYPT_ROUNDS)

_VALID_ROLES = ("admin", "staff")


def _normalize_username(username: str) -> str:
    """Normalize a username to lowercase (DG-029 follow-on).

    All users.username values are stored lowercase. CLI commands accept
    mixed-case input for ergonomics but look up/insert the lowercased form.
    Uses Python str.lower() (Unicode-aware, correct for Vietnamese
    diacritics like Â→â, Ư→ư).
    """
    return username.lower()


def _validate_role(ctx, param, value):
    """Click callback that validates the ``--role`` option."""
    if value is None:
        return value
    if value not in _VALID_ROLES:
        raise click.BadParameter(
            f"vai trò phải là một trong: {', '.join(_VALID_ROLES)} (nhận được '{value}')"
        )
    return value


def _generate_password() -> str:
    """Generate a random URL-safe password (matches v68 seeding length)."""
    return secrets.token_urlsafe(12)


def _hash(password: str) -> str:
    """Return a bcrypt hash for ``password`` (cost factor 12, NFR4)."""
    return _pwd_ctx.hash(password)


@click.group("user")
def user_cmd():
    """Manage system user accounts (DG-029 RBAC)."""


@user_cmd.command("create")
@click.argument("username")
@click.option(
    "--role",
    default="staff",
    callback=_validate_role,
    help="System role: admin or staff (default: staff).",
)
@click.option(
    "--staff",
    "staff_name",
    default=None,
    help="Link to a staff member by name (case+diacritic-insensitive).",
)
@click.option(
    "--quiet",
    is_flag=True,
    help="Suppress plaintext password output (for CI/scripted use).",
)
def user_create(username: str, role: str, staff_name: str | None, quiet: bool):
    """Create a new user account with a random password (FR7).

    The generated password is printed to stdout so it can be distributed to
    the user. The password is bcrypt-hashed before storage (NFR4). Pass
    ``--quiet`` to suppress the plaintext password output (CI/scripted use).

    Pass ``--staff <name>`` to link the new user to an existing staff member
    by case+diacritic-insensitive name matching (FR10/DG-259).
    """
    username = _normalize_username(username)

    resolved_staff_id: int | None = None
    with get_db() as conn:
        if staff_name:
            staff_rows = conn.execute(
                "SELECT id, name FROM staff ORDER BY id"
            ).fetchall()
            target_norm = _strip_diacritics(staff_name.strip())
            for srow in staff_rows:
                if _strip_diacritics(srow["name"]) == target_norm:
                    # Check if this staff member is already linked to another user
                    linked = conn.execute(
                        "SELECT id, username FROM users "
                        "WHERE staff_id = ? AND staff_id IS NOT NULL",
                        (int(srow["id"]),),
                    ).fetchone()
                    if linked:
                        console.print(
                            f"  [red]Staff '{srow['name']}' is already linked to "
                            f"user '{linked['username']}'.[/red]"
                        )
                        return
                    resolved_staff_id = int(srow["id"])
                    break
            if resolved_staff_id is None:
                console.print(
                    f"  [red]No staff member found matching '{staff_name}'.[/red]"
                )
                return

        existing = conn.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()
        if existing:
            console.print(f"  [red]User '{username}' already exists (#{existing['id']})[/red]")
            return

        plain = _generate_password()
        hashed = _hash(plain)
        try:
            conn.execute(
                "INSERT INTO users (username, password_hash, role, active, staff_id) "
                "VALUES (?, ?, ?, 1, ?)",
                (username, hashed, role, resolved_staff_id),
            )
        except sqlite3.IntegrityError:
            console.print(
                "  [red]Failed to create user: database integrity error. "
                "The staff member may already be linked to another user.[/red]"
            )
            return
        console.print(f"  [green]Created[/green] user '{username}' (role={role})")
        if staff_name:
            console.print("  [green]Linked[/green] to staff member.")
        if not quiet:
            console.print(f"  [bold]Password:[/bold] {plain}")
            console.print("[dim]Distribute this password to the user.[/dim]")


@user_cmd.command("set-password")
@click.argument("username")
@click.option(
    "--random",
    "use_random",
    is_flag=True,
    help="Generate a random password instead of prompting interactively.",
)
@click.option(
    "--quiet",
    is_flag=True,
    help="Suppress plaintext password output (for CI/scripted use).",
)
def user_set_password(username: str, use_random: bool, quiet: bool):
    """Set a new password for an existing user (FR8).

    By default prompts for a new password interactively with hidden input
    and confirmation (matching standard ``passwd`` UX) — passwords are no
    longer accepted via ``--password`` to avoid exposing them via
    ``ps aux`` / shell history (MJ-1, DG-029 phase 5.6-c1).

    Pass ``--random`` to generate a random password instead of prompting;
    the generated password is printed to stdout unless ``--quiet`` is also
    passed (MJ-2, for CI/scripted use).
    """
    username = _normalize_username(username)
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()
        if not row:
            console.print(f"  [red]User '{username}' not found.[/red]")
            return

        generated = False
        if use_random:
            password = _generate_password()
            generated = True
        else:
            # Interactive prompt — hidden input + confirmation (MJ-1).
            # Click's CliRunner drives this via `input=...` in tests.
            password = click.prompt(
                "New password",
                hide_input=True,
                confirmation_prompt=True,
            )
        hashed = _hash(password)
        conn.execute(
            "UPDATE users SET password_hash = ? WHERE username = ?",
            (hashed, username),
        )
        console.print(f"  [green]Updated[/green] password for '{username}'.")
        if generated and not quiet:
            console.print(f"  [bold]New password:[/bold] {password}")
            console.print("[dim]Distribute this password to the user.[/dim]")


@user_cmd.command("set-role")
@click.argument("username")
@click.argument("role", callback=_validate_role)
def user_set_role(username: str, role: str):
    """Change an existing user's system role (FR9)."""
    username = _normalize_username(username)
    with get_db() as conn:
        row = conn.execute(
            "SELECT id, role FROM users WHERE username = ?", (username,)
        ).fetchone()
        if not row:
            console.print(f"  [red]User '{username}' not found.[/red]")
            return
        if row["role"] == role:
            console.print(f"  [dim]User '{username}' is already role={role}.[/dim]")
            return
        conn.execute(
            "UPDATE users SET role = ? WHERE username = ?",
            (role, username),
        )
        console.print(
            f"  [green]Updated[/green] '{username}' role: {row['role']} → {role}"
        )


@user_cmd.command("list")
@click.option("--all", "show_all", is_flag=True, help="Include inactive users.")
def user_list(show_all: bool):
    """List all users with username, role, and active status (FR10).

    Also shows whether an account is currently locked (locked_until in the
    future). Inactive users are omitted unless ``--all`` is passed.
    """
    with get_db() as conn:
        rows = conn.execute(
            "SELECT username, role, active, locked_until, created_at "
            "FROM users "
            + ("" if show_all else "WHERE active = 1 ")
            + "ORDER BY username"
        ).fetchall()

    if not rows:
        console.print("[dim]Không có user nào.[/dim]")
        return

    table = Table(title=f"Users ({len(rows)})", show_lines=False, padding=(0, 1))
    table.add_column("Username", style="bold")
    table.add_column("Role", width=8)
    table.add_column("Active", width=7)
    table.add_column("Locked", width=8)
    table.add_column("Created", style="dim", width=20)

    now = datetime.now(timezone.utc)
    for row in rows:
        active_str = "[green]yes[/green]" if row["active"] else "[red]no[/red]"
        locked_str = "[red]yes[/red]"
        if not row["locked_until"]:
            locked_str = "[dim]no[/dim]"
        else:
            try:
                lock_dt = datetime.fromisoformat(row["locked_until"].replace("Z", "+00:00"))
                if now >= lock_dt:
                    locked_str = "[dim]no[/dim]"
            except (ValueError, TypeError):
                locked_str = "[dim]?[/dim]"
        created = row["created_at"][:19] if row["created_at"] else ""
        table.add_row(row["username"], row["role"], active_str, locked_str, created)

    console.print(table)


@user_cmd.command("deactivate")
@click.argument("username")
def user_deactivate(username: str):
    """Deactivate a user account (soft delete, active=0) (FR11)."""
    username = _normalize_username(username)
    with get_db() as conn:
        row = conn.execute(
            "SELECT id, active FROM users WHERE username = ?", (username,)
        ).fetchone()
        if not row:
            console.print(f"  [red]User '{username}' not found.[/red]")
            return
        if not row["active"]:
            console.print(f"  [dim]User '{username}' is already inactive.[/dim]")
            return
        conn.execute(
            "UPDATE users SET active = 0 WHERE username = ?",
            (username,),
        )
        console.print(f"  [green]Deactivated[/green] user '{username}'.")


@user_cmd.command("unlock")
@click.argument("username")
def user_unlock(username: str):
    """Clear the brute-force lock on a user account (FR19 admin override).

    Resets ``locked_until`` to NULL so the user can log in again immediately,
    and clears the in-memory consecutive-failure counter for that username so
    a fresh attempt does not carry over residual state.
    """
    username = _normalize_username(username)
    with get_db() as conn:
        row = conn.execute(
            "SELECT id, locked_until FROM users WHERE username = ?", (username,)
        ).fetchone()
        if not row:
            console.print(f"  [red]User '{username}' not found.[/red]")
            return
        if not row["locked_until"]:
            console.print(f"  [dim]User '{username}' is not locked.[/dim]")
            return
        conn.execute(
            "UPDATE users SET locked_until = NULL WHERE username = ?",
            (username,),
        )
        # Clear in-memory failure counter so the next login attempt starts fresh.
        from baker.api.auth import _clear_login_failures
        _clear_login_failures(username)
        console.print(f"  [green]Unlocked[/green] user '{username}'.")