"""CLI command group for user account management (DG-029 Phase 4).

Implements FR7-FR11 + FR19 unlock extension:
  - ``baker user create <username> --role <admin|staff>``  (FR7)
  - ``baker user set-password <username>``                 (FR8)
  - ``baker user set-role <username> <admin|staff>``       (FR9)
  - ``baker user list``                                    (FR10)
  - ``baker user deactivate <username>``                   (FR11)
  - ``baker user unlock <username>``                       (FR19)

Passwords are hashed with bcrypt (cost factor 12, NFR4) via passlib.
``create`` and ``set-password`` print a generated (or accepted) plaintext
password to stdout so the admin can distribute credentials. ``set-password``
accepts an optional ``--password`` flag; when omitted a random password is
generated and printed (matching the migration seeding behaviour).
"""

from __future__ import annotations

import secrets
from typing import Optional

import click
from passlib.context import CryptContext
from rich.console import Console
from rich.table import Table

from baker.db.connection import get_db

console = Console()

# bcrypt password hashing context (NFR4: cost factor 12). Kept in sync with
# the auth module and v68 migration seeding.
_pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=12)

_VALID_ROLES = ("admin", "staff")


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
def user_create(username: str, role: str):
    """Create a new user account with a random password (FR7).

    The generated password is printed to stdout so it can be distributed to
    the user. The password is bcrypt-hashed before storage (NFR4).
    """
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()
        if existing:
            console.print(f"  [red]User '{username}' already exists (#{existing['id']})[/red]")
            return

        plain = _generate_password()
        hashed = _hash(plain)
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES (?, ?, ?, 1)",
            (username, hashed, role),
        )
        console.print(f"  [green]Created[/green] user '{username}' (role={role})")
        console.print(f"  [bold]Password:[/bold] {plain}")
        console.print("[dim]Distribute this password to the user.[/dim]")


@user_cmd.command("set-password")
@click.argument("username")
@click.option(
    "--password",
    default=None,
    help="New password. If omitted, a random password is generated and printed.",
)
def user_set_password(username: str, password: Optional[str]):
    """Set a new password for an existing user (FR8).

    When ``--password`` is omitted, a random password is generated and printed
    to stdout (matching the create/migration behaviour). When provided, the
    password is hashed and stored silently.
    """
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()
        if not row:
            console.print(f"  [red]User '{username}' not found.[/red]")
            return

        generated = False
        if not password:
            password = _generate_password()
            generated = True
        hashed = _hash(password)
        conn.execute(
            "UPDATE users SET password_hash = ? WHERE username = ?",
            (hashed, username),
        )
        console.print(f"  [green]Updated[/green] password for '{username}'.")
        if generated:
            console.print(f"  [bold]New password:[/bold] {password}")
            console.print("[dim]Distribute this password to the user.[/dim]")


@user_cmd.command("set-role")
@click.argument("username")
@click.argument("role", callback=_validate_role)
def user_set_role(username: str, role: str):
    """Change an existing user's system role (FR9)."""
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

    from datetime import datetime, timezone

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