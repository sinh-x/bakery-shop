"""Rich formatters for terminal output."""

import json
from rich.console import Console, Group
from rich.table import Table
from rich.panel import Panel
from rich.text import Text

from . import format_phone
from baker.utils.time import utc_to_local

console = Console()


def _row_get(row, key, default=""):
    """Safely get a column from a sqlite3.Row."""
    try:
        val = row[key]
        return val if val else default
    except (IndexError, KeyError):
        return default


def print_event(row):
    """Print a single event row."""
    tags = row["tags"] if row["tags"] else ""
    tag_str = f" [{tags}]" if tags else ""
    data = json.loads(row["data"]) if row["data"] and row["data"] != "{}" else None
    data_str = f"  {data}" if data else ""

    ts = utc_to_local(row["timestamp"])
    type_color = {
        "note": "white", "production": "green", "sale": "yellow",
        "inventory": "cyan", "expense": "red", "delivery": "blue", "order": "magenta",
    }.get(row["type"], "white")

    by_val = _row_get(row, "staff_name") or _row_get(row, "logged_by")
    by_str = f"  by {by_val}" if by_val else ""

    console.print(
        f"  [dim]{row['id']:>4}[/dim]  [dim]{ts}[/dim]  "
        f"[{type_color}]{row['type']:>12}[/{type_color}]  "
        f"{row['summary']}"
        f"[dim]{tag_str}{data_str}{by_str}[/dim]"
    )


def print_events_table(rows, title="Events"):
    """Print events as a table."""
    if not rows:
        console.print(f"  [dim]No {title.lower()} found.[/dim]")
        return

    has_logged_by = any(_row_get(row, "logged_by") for row in rows)

    table = Table(title=title, show_lines=False, padding=(0, 1))
    table.add_column("#", style="dim", width=5)
    table.add_column("Time", style="dim", width=16)
    table.add_column("Type", width=12)
    table.add_column("Summary")
    if has_logged_by:
        table.add_column("By", style="cyan")
    table.add_column("Tags", style="dim")

    type_colors = {
        "note": "white", "production": "green", "sale": "yellow",
        "inventory": "cyan", "expense": "red", "delivery": "blue", "order": "magenta",
    }

    for row in rows:
        color = type_colors.get(row["type"], "white")
        tags = row["tags"] if row["tags"] else ""
        cells = [
            str(row["id"]),
            utc_to_local(row["timestamp"]),
            f"[{color}]{row['type']}[/{color}]",
            row["summary"],
        ]
        if has_logged_by:
            by = _row_get(row, "staff_name") or _row_get(row, "logged_by")
            cells.append(by)
        cells.append(tags)
        table.add_row(*cells)
    console.print(table)


def print_staff_table(rows, title="Staff"):
    """Print staff members as a table."""
    from baker.models.staff import ROLES

    if not rows:
        console.print(f"  [dim]No staff found.[/dim]")
        return

    table = Table(title=title, show_lines=False, padding=(0, 1))
    table.add_column("#", style="dim", width=4)
    table.add_column("Name", style="bold")
    table.add_column("Role")
    table.add_column("Phone", style="dim")

    for row in rows:
        raw_roles = row["role"] or ""
        # Show Vietnamese labels for known roles
        labels = []
        for r in raw_roles.split(","):
            r = r.strip()
            if r in ROLES:
                labels.append(ROLES[r])
            elif r:
                labels.append(r)
        table.add_row(
            str(row["id"]),
            row["name"],
            ", ".join(labels),
            format_phone(row["phone"] or ""),
        )
    console.print(table)


def print_orders_table(rows, title="Orders"):
    """Print orders as a table."""
    if not rows:
        console.print(f"  [dim]No orders found.[/dim]")
        return

    table = Table(title=title, show_lines=False, padding=(0, 1))
    table.add_column("Ref", style="bold")
    table.add_column("Customer")
    table.add_column("Items")
    table.add_column("Total", justify="right")
    table.add_column("Status")
    table.add_column("Due")
    table.add_column("Type")

    status_colors = {
        "new": "white", "confirmed": "cyan", "in_progress": "yellow",
        "ready": "green", "delivered": "blue", "completed": "dim green",
        "cancelled": "dim red",
    }

    for row in rows:
        items_data = json.loads(row["items"]) if row["items"] else []
        items_str = ", ".join(f"{i['product']} x{i['qty']}" for i in items_data)
        if len(items_str) > 30:
            items_str = items_str[:27] + "..."

        color = status_colors.get(row["status"], "white")
        due = row["due_date"] or ""
        if row["due_time"]:
            due += f" {row['due_time']}"

        table.add_row(
            row["order_ref"],
            row["customer_name"],
            items_str,
            f"{row['total_price']:.2f}" if row["total_price"] else "-",
            f"[{color}]{row['status']}[/{color}]",
            due,
            row["delivery_type"],
        )
    console.print(table)


def print_inventory_table(rows, title="Inventory"):
    """Print inventory as a table."""
    if not rows:
        console.print(f"  [dim]No inventory items found.[/dim]")
        return

    table = Table(title=title, show_lines=False, padding=(0, 1))
    table.add_column("Item", style="bold")
    table.add_column("Category", style="dim")
    table.add_column("Quantity", justify="right")
    table.add_column("Unit")
    table.add_column("Low @", justify="right", style="dim")
    table.add_column("Status")

    for row in rows:
        is_low = row["low_threshold"] > 0 and row["quantity"] <= row["low_threshold"]
        status = "[red bold]LOW[/red bold]" if is_low else "[green]OK[/green]"
        qty_style = "red bold" if is_low else ""

        table.add_row(
            row["name"],
            row["category"],
            f"[{qty_style}]{row['quantity']:.1f}[/{qty_style}]" if qty_style else f"{row['quantity']:.1f}",
            row["unit"],
            f"{row['low_threshold']:.1f}" if row["low_threshold"] else "-",
            status if row["low_threshold"] > 0 else "",
        )
    console.print(table)


def print_order_detail(row):
    """Print detailed view of a single order."""
    items_data = json.loads(row["items"]) if row["items"] else []

    lines = []
    lines.append(f"[bold]Order {row['order_ref']}[/bold]")
    lines.append(f"Customer: {row['customer_name']}")
    if row["customer_phone"]:
        lines.append(f"Phone: {format_phone(row['customer_phone'])}")
    lines.append("")
    lines.append("[bold]Items:[/bold]")
    for i in items_data:
        price_str = f" @ {i['price']:.2f}" if i.get("price") else ""
        note_str = f" ({i['notes']})" if i.get("notes") else ""
        lines.append(f"  - {i['product']} x{i['qty']}{price_str}{note_str}")

    lines.append("")
    lines.append(f"Total: [bold]{row['total_price']:.2f}[/bold]")
    lines.append(f"Status: [bold]{row['status']}[/bold]")

    due = row["due_date"] or "not set"
    if row["due_time"]:
        due += f" {row['due_time']}"
    lines.append(f"Due: {due}")
    lines.append(f"Delivery: {row['delivery_type']}")
    if row["delivery_address"]:
        lines.append(f"Address: {row['delivery_address']}")
    if row["notes"]:
        lines.append(f"\nNotes: {row['notes']}")
    lines.append(f"\n[dim]Created: {utc_to_local(row['created_at'])}  Updated: {utc_to_local(row['updated_at'])}[/dim]")

    console.print(Panel("\n".join(lines), title=row["order_ref"], border_style="blue"))


def print_order_accounting(entries):
    """Print accounting journal entries for an order.

    Args:
        entries: Output from JournalEntry.list_for_order().
    """
    if not entries:
        console.print("  [dim]Không có bút toán kế toán cho đơn hàng này[/dim]")
        return

    source_type_groups = {
        "order": "Doanh thu",
        "order_cogs": "Giá vốn",
        "order_shipping_hold": "Ship",
        "order_shipping_release": "Ship",
        "payment_transaction": "Thanh toán",
    }

    account_totals: dict[str, dict] = {}
    for entry in entries:
        for line in entry["lines"]:
            code = line["account_code"]
            if code not in account_totals:
                account_totals[code] = {"name": line["account_name"], "debit": 0.0, "credit": 0.0}
            account_totals[code]["debit"] += line["debit"]
            account_totals[code]["credit"] += line["credit"]

    summary_table = Table(title="Tóm tắt theo tài khoản", show_lines=False, padding=(0, 1), box=None)
    summary_table.add_column("Mã TK", style="bold", width=8)
    summary_table.add_column("Tên tài khoản", width=22)
    summary_table.add_column("Nợ", justify="right", width=12)
    summary_table.add_column("Có", justify="right", width=12)

    grand_debit = grand_credit = 0.0
    for code in sorted(account_totals):
        d = account_totals[code]["debit"]
        c = account_totals[code]["credit"]
        summary_table.add_row(
            code,
            account_totals[code]["name"],
            f"{d:,.0f}" if d else "",
            f"{c:,.0f}" if c else "",
        )
        grand_debit += d
        grand_credit += c
    summary_table.add_row("", "", "", "")
    summary_table.add_row("Tổng", "", f"{grand_debit:,.0f}", f"{grand_credit:,.0f}")

    console.print()
    console.print(summary_table)
    console.print()

    for entry in entries:
        header_lines = [
            f"[bold]Bút toán #{entry['id']}[/bold]  "
            f"[dim]{entry['description']}[/dim]",
        ]
        if entry.get("transaction_date"):
            header_lines.append(f"  Ngày: {utc_to_local(entry['transaction_date'])}")
        header_lines.append(
            f"  Nguồn: {source_type_groups.get(entry['source_type'], entry['source_type'])}"
        )
        header_lines.append("")

        table = Table(show_lines=False, padding=(0, 1), box=None)
        table.add_column("TK", style="bold", width=8)
        table.add_column("Tên tài khoản", width=22)
        table.add_column("Nợ", justify="right", width=12)
        table.add_column("Có", justify="right", width=12)
        table.add_column("Diễn giải", width=30)

        for line in entry["lines"]:
            table.add_row(
                line["account_code"],
                line["account_name"],
                f"{line['debit']:.2f}" if line["debit"] else "",
                f"{line['credit']:.2f}" if line["credit"] else "",
                line["description"],
            )

        console.print(Panel(Group("\n".join(header_lines), table), border_style="dim"))
        console.print()


def print_dashboard(orders_due, low_stock, event_counts, total_events, staff_counts=None):
    """Print the daily dashboard."""
    lines = []

    # Orders due today
    if orders_due:
        lines.append(f"[bold]ORDERS DUE TODAY[/bold]  {len(orders_due)} order(s)")
        for o in orders_due:
            time_str = f" {o['due_time']}" if o["due_time"] else ""
            lines.append(f"  {o['order_ref']}  {o['customer_name']:20s}  [{o['status']}]{time_str}")
    else:
        lines.append("[bold]ORDERS DUE TODAY[/bold]  [dim]none[/dim]")

    lines.append("")

    # Low stock
    if low_stock:
        lines.append(f"[bold red]LOW STOCK[/bold red]  {len(low_stock)} item(s)")
        for item in low_stock:
            lines.append(f"  [red]{item['name']}: {item['quantity']:.1f} {item['unit']}[/red] (threshold: {item['low_threshold']:.1f})")
    else:
        lines.append("[bold]STOCK[/bold]  [green]all OK[/green]")

    lines.append("")

    # Activity
    lines.append(f"[bold]TODAY'S ACTIVITY[/bold]  {total_events} event(s)")
    for row in event_counts:
        lines.append(f"  {row['type']:>12}: {row['cnt']}")

    # Staff activity
    if staff_counts:
        lines.append("")
        lines.append(f"[bold]STAFF ACTIVITY[/bold]")
        for row in staff_counts:
            lines.append(f"  {row['logged_by']:>12}: {row['cnt']} event(s)")

    from datetime import datetime
    title = f"Baker Dashboard: {datetime.now().strftime('%A, %B %d, %Y')}"
    console.print(Panel("\n".join(lines), title=title, border_style="green"))
