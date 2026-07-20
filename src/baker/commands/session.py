"""CLI command group for active session management (DG-029 Phase 4).

Implements FR20/FR21:
  - ``baker session list``        — show active sessions (FR20)
  - ``baker session logout <u>``  — invalidate a user's tokens (FR21)
  - ``baker session logout-all``  — invalidate all tokens (FR21)

Force-logout adds each affected session's jti to the in-memory denylist
checked by ``AuthMiddleware`` (FR21). Revoked sessions are stamped with
``revoked_at`` so future ``list`` runs omit them. The denylist lives in
memory in the API process; the CLI shares the same Python process module so
the two stay in sync when run from the same interpreter. In a multi-process
deployment the CLI must be run on the API host (the in-memory denylist is not
shared across processes — same trade-off as rate limiting, NFR7).
"""

from __future__ import annotations

import click
from rich.console import Console
from rich.table import Table

from baker.api.auth import (
    fetch_active_sessions,
    revoke_all_sessions,
    revoke_user_sessions,
)
from baker.db.connection import get_db
from baker.utils.time import utc_to_local

# Use a wide console so the 7-column session table renders fully even in
# non-tty contexts (e.g. CI logs, CliRunner). Rich auto-detects a narrower
# real terminal and will still wrap gracefully.
console = Console(width=180)


@click.group("session")
def session_cmd():
    """Manage active login sessions (DG-029 RBAC)."""


@session_cmd.command("list")
def session_list():
    """List all active sessions (FR20).

    Shows username, role, client IP, device info, login time, and last
    activity time for each non-revoked session row.
    """
    with get_db() as conn:
        rows = fetch_active_sessions(conn)

    if not rows:
        console.print("[dim]Không có phiên đăng nhập nào đang hoạt động.[/dim]")
        return

    table = Table(title=f"Active Sessions ({len(rows)})", show_lines=False, padding=(0, 1))
    table.add_column("Username", style="bold", no_wrap=False, overflow="fold")
    table.add_column("Role", width=8)
    table.add_column("Staff Name", width=16)
    table.add_column("Staff Role", width=12)
    table.add_column("IP", width=15)
    table.add_column("Device", width=18)
    table.add_column("App Ver", width=10)
    table.add_column("Login Time", width=18)
    table.add_column("Last Activity", width=18)

    for row in rows:
        device = row["device_model"] or ""
        if len(device) > 18:
            device = device[:18]
        app_ver = row["app_version"] or ""
        if len(app_ver) > 10:
            app_ver = app_ver[:10]
        staff_name = row["staff_name"] or "-"
        staff_role = row["staff_role"] or "-"
        table.add_row(
            row["username"],
            row["role"],
            staff_name,
            staff_role,
            row["client_ip"] or "",
            device,
            app_ver,
            utc_to_local(row["logged_in_at"]),
            utc_to_local(row["last_activity"]),
        )

    console.print(table)


@session_cmd.command("logout")
@click.argument("username")
def session_logout(username: str):
    """Invalidate all active tokens for ``username`` (FR21).

    Adds each of the user's active session jti values to the denylist and
    stamps ``revoked_at`` in the DB. Any subsequent request with one of those
    tokens is rejected by ``AuthMiddleware`` with HTTP 401.
    """
    with get_db() as conn:
        count = revoke_user_sessions(conn, username)
    if count == 0:
        console.print(f"  [dim]No active sessions for '{username}'.[/dim]")
        return
    console.print(
        f"  [green]Revoked[/green] {count} session(s) for '{username}'. "
        "Their old tokens will now return 401."
    )


@session_cmd.command("logout-all")
def session_logout_all():
    """Invalidate all active tokens for all users (FR21)."""
    with get_db() as conn:
        count = revoke_all_sessions(conn)
    if count == 0:
        console.print("[dim]No active sessions to revoke.[/dim]")
        return
    console.print(
        f"  [green]Revoked[/green] {count} session(s) across all users. "
        "All old tokens will now return 401."
    )