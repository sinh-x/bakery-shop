"""CLI command for viewing server logs."""

import json
import time
from typing import Optional

import click
from rich.console import Console
from rich.table import Table

from baker.db.connection import get_db

console = Console()


@click.group("server-log")
def server_log_cmd():
    """View and search server API logs."""
    pass


@server_log_cmd.command("list")
@click.option("--level", default=None, help="Filter by log level (INFO, WARNING, ERROR)")
@click.option("--path", "path_filter", default=None, help="Filter by request path (contains)")
@click.option("--status", "status_code", default=None, type=int, help="Filter by status code")
@click.option("--since", default=None, help="Show logs since (YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS)")
@click.option("--ref-type", default=None, help="Filter by ref_type (order, event, product)")
@click.option("--ref-id", default=None, type=int, help="Filter by ref_id")
@click.option("--device", default=None, help="Filter by device_model (contains)")
@click.option("--limit", default=50, help="Max rows to show")
def list_logs(
    level: Optional[str],
    path_filter: Optional[str],
    status_code: Optional[int],
    since: Optional[str],
    ref_type: Optional[str],
    ref_id: Optional[int],
    device: Optional[str],
    limit: int,
):
    """Show recent server log entries."""
    conditions = []
    params: list = []

    if level:
        conditions.append("level = ?")
        params.append(level.upper())
    if path_filter:
        conditions.append("path LIKE ?")
        params.append(f"%{path_filter}%")
    if status_code is not None:
        conditions.append("status_code = ?")
        params.append(status_code)
    if since:
        conditions.append("timestamp >= ?")
        params.append(since)
    if ref_type:
        conditions.append("ref_type = ?")
        params.append(ref_type)
    if ref_id is not None:
        conditions.append("ref_id = ?")
        params.append(ref_id)
    if device:
        conditions.append("device_model LIKE ?")
        params.append(f"%{device}%")

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    with get_db() as conn:
        rows = conn.execute(
            f"SELECT * FROM server_logs {where} ORDER BY id DESC LIMIT ?",
            params + [limit],
        ).fetchall()

    if not rows:
        console.print("[dim]Không có log nào.[/dim]")
        return

    table = Table(title=f"Server Logs ({len(rows)} entries)")
    table.add_column("ID", style="dim", width=6)
    table.add_column("Time", width=19)
    table.add_column("Level", width=7)
    table.add_column("Method", width=7)
    table.add_column("Path", width=25)
    table.add_column("Status", width=6)
    table.add_column("Duration", width=8)
    table.add_column("Client IP", width=15)
    table.add_column("Device", width=15)
    table.add_column("Ref", width=12)

    level_colors = {"INFO": "green", "WARNING": "yellow", "ERROR": "red", "DEBUG": "blue"}

    for row in rows:
        level_str = row["level"]
        color = level_colors.get(level_str, "white")
        ref = f"{row['ref_type']}#{row['ref_id']}" if row["ref_type"] else ""
        table.add_row(
            str(row["id"]),
            row["timestamp"][:19],
            f"[{color}]{level_str}[/{color}]",
            row["method"],
            row["path"][:25],
            str(row["status_code"]),
            f"{row['duration_ms']:.0f}ms",
            row["client_ip"],
            row["device_model"][:15] if row["device_model"] else "",
            ref,
        )

    console.print(table)


@server_log_cmd.command("tail")
@click.option("--interval", default=1.0, help="Poll interval in seconds")
def tail_logs(interval: float):
    """Live-tail the server log file."""
    import baker.config
    from datetime import datetime

    log_dir = baker.config.LOG_DIR
    today = datetime.now().strftime("%Y-%m-%d")
    log_file = log_dir / f"server-{today}.log"

    if not log_file.exists():
        console.print(f"[dim]Log file not found: {log_file}[/dim]")
        console.print("[dim]Start the server to generate logs.[/dim]")
        return

    console.print(f"[bold]Tailing {log_file}[/bold] (Ctrl+C to stop)")

    with open(log_file, "r") as f:
        # Seek to end
        f.seek(0, 2)
        try:
            while True:
                line = f.readline()
                if line:
                    try:
                        entry = json.loads(line.strip())
                        level = entry.get("level", "INFO")
                        color = {"ERROR": "red", "WARNING": "yellow", "INFO": "green"}.get(level, "white")
                        msg = entry.get("message", line.strip())
                        console.print(f"[{color}]{entry.get('timestamp', '')[:19]} [{level}][/{color}] {msg}")
                    except json.JSONDecodeError:
                        console.print(line.strip())
                else:
                    time.sleep(interval)
        except KeyboardInterrupt:
            console.print("\n[dim]Stopped.[/dim]")


@server_log_cmd.command("search")
@click.argument("query")
@click.option("--limit", default=50, help="Max results")
def search_logs(query: str, limit: int):
    """Full-text search across log messages and details."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM server_logs "
            "WHERE message LIKE ? OR detail LIKE ? "
            "ORDER BY id DESC LIMIT ?",
            (f"%{query}%", f"%{query}%", limit),
        ).fetchall()

    if not rows:
        console.print(f"[dim]Không tìm thấy kết quả cho '{query}'.[/dim]")
        return

    console.print(f"[bold]Found {len(rows)} results for '{query}':[/bold]")
    for row in rows:
        level = row["level"]
        color = {"ERROR": "red", "WARNING": "yellow", "INFO": "green"}.get(level, "white")
        console.print(
            f"  [{color}][{row['timestamp'][:19]}] [{level}][/{color}] "
            f"{row['method']} {row['path']} → {row['status_code']} "
            f"| {row['message']}"
        )
        detail = row["detail"]
        if detail and detail != "{}":
            try:
                d = json.loads(detail)
                if "traceback" in d:
                    console.print(f"    [red]{d['traceback'][:200]}...[/red]")
            except json.JSONDecodeError:
                pass
