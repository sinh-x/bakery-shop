import click
from rich.table import Table

from baker.db.connection import get_db
from baker.models.order import Order, OrderItem, allowed_transitions
from baker.models.journal_entry import JournalEntry
from baker.formatters.tables import console, print_orders_table, print_order_detail, print_order_accounting
from baker.utils.time import now_utc


def _resolve_order_ref(conn, ref):
    """Resolve a REF argument to a single order row.

    Lookup order (per FR1):
      1. ``public_order_code`` exact match.
      2. Exact match on ``order_ref``.
      3. Numeric ``id`` (``CAST(id AS TEXT) = ref``).

    When ``public_order_code`` matches multiple orders (FR2), display an
    interactive numbered list sorted by ``created_at`` descending (customer
    name, due date, status) and let the user select one via ``click.prompt``.

    Returns the selected ``sqlite3.Row`` or ``None`` when not found.
    """
    matches = conn.execute(
        "SELECT * FROM orders WHERE public_order_code = ? ORDER BY created_at DESC",
        (ref,),
    ).fetchall()

    if matches:
        if len(matches) == 1:
            return matches[0]
        return _pick_order(matches, ref)

    row = conn.execute(
        "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
        (ref, ref),
    ).fetchone()
    return row


def _pick_order(matches, ref):
    """Display an interactive numbered picker for multiple public_code matches."""
    console.print(f"  [cyan]Found {len(matches)} orders for public code '{ref}':[/cyan]")
    table = Table(show_lines=False, padding=(0, 1))
    table.add_column("#", style="dim", width=4)
    table.add_column("Customer")
    table.add_column("Due")
    table.add_column("Status")
    for idx, m in enumerate(matches, 1):
        due = m["due_date"] or ""
        if m["due_time"]:
            due += f" {m['due_time']}"
        table.add_row(str(idx), m["customer_name"], due, m["status"])
    console.print(table)

    while True:
        choice = click.prompt("Select order number", type=int)
        if 1 <= choice <= len(matches):
            return matches[choice - 1]
        console.print(f"  [red]Please enter a number between 1 and {len(matches)}[/red]")


@click.group("order")
def order_cmd():
    """Manage customer orders."""


@order_cmd.command("new")
@click.argument("customer")
@click.option("--item", "-i", "items", multiple=True, required=True,
              help="Item spec: 'Product x2 @45.00' (repeatable)")
@click.option("--due", "due_date", help="Due date (YYYY-MM-DD or 'today'/'tomorrow')")
@click.option("--due-time", help="Due time (HH:MM)")
@click.option("--delivery", is_flag=True, help="Mark as delivery (default: pickup)")
@click.option("--address", default="", help="Delivery address")
@click.option("--phone", default="", help="Customer phone")
@click.option("--note", "notes", default="", help="Order notes")
def order_new(customer, items, due_date, due_time, delivery, address, phone, notes):
    """Create a new order."""
    from datetime import datetime, timedelta

    parsed_items = [OrderItem.parse(spec) for spec in items]

    # Resolve relative dates
    if due_date == "today":
        due_date = datetime.now().strftime("%Y-%m-%d")
    elif due_date == "tomorrow":
        due_date = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")

    order = Order(
        customer_name=customer,
        items=parsed_items,
        due_date=due_date,
        due_time=due_time,
        delivery_type="delivery" if delivery else "pickup",
        delivery_address=address,
        customer_phone=phone,
        notes=notes,
    )

    with get_db() as conn:
        order.save(conn)
        console.print(f"  [green]Created[/green] {order.order_ref} for {customer}")
        if order.total_price:
            console.print(f"  Total: {order.total_price:.2f}")


@order_cmd.command("list")
@click.option("--all", "show_all", is_flag=True, help="Include completed/cancelled")
@click.option("--status", help="Filter by status")
@click.option("--due", help="Filter by due date (YYYY-MM-DD, 'today', 'tomorrow', 'overdue')")
def order_list(show_all, status, due):
    """List orders."""
    from datetime import datetime, timedelta

    with get_db() as conn:
        conditions = []
        params = []

        if status:
            conditions.append("status = ?")
            params.append(status)
        elif not show_all:
            conditions.append("status NOT IN ('completed', 'cancelled')")

        if due:
            if due == "today":
                due = datetime.now().strftime("%Y-%m-%d")
            elif due == "tomorrow":
                due = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
            elif due == "overdue":
                conditions.append("due_date < ? AND status NOT IN ('completed', 'cancelled', 'delivered')")
                params.append(datetime.now().strftime("%Y-%m-%d"))
                due = None

            if due:
                conditions.append("due_date = ?")
                params.append(due)

        where = " AND ".join(conditions) if conditions else "1=1"
        rows = conn.execute(
            f"SELECT * FROM orders WHERE {where} ORDER BY due_date, due_time",  # nosec B608
            params,
        ).fetchall()

        print_orders_table(rows)


@order_cmd.command("show")
@click.argument("ref")
@click.option("--accounting", is_flag=True, help="Show accounting journal entries")
def order_show(ref, accounting):
    """Show order details."""
    with get_db() as conn:
        row = _resolve_order_ref(conn, ref)
        if not row:
            console.print(f"  [red]Order '{ref}' not found[/red]")
            return
        print_order_detail(row)
        if accounting:
            entries = JournalEntry.list_for_order(conn, row["id"])
            print_order_accounting(entries)


@order_cmd.command("status")
@click.argument("ref")
@click.argument("new_status")
@click.option("--reason", default="", help="Reason for status change (especially for cancel)")
def order_status(ref, new_status, reason):
    """Update order status."""
    with get_db() as conn:
        row = _resolve_order_ref(conn, ref)
        if not row:
            console.print(f"  [red]Order '{ref}' not found[/red]")
            return

        current = row["status"]
        ok = Order.update_status(conn, row["order_ref"], new_status, reason)
        if ok:
            console.print(f"  [green]{row['order_ref']}[/green]: {current} -> {new_status}")
        else:
            allowed = allowed_transitions(current)
            console.print(f"  [red]Cannot change from '{current}' to '{new_status}'[/red]")
            if allowed:
                console.print(f"  Allowed: {', '.join(allowed)}")
            else:
                console.print(f"  Order is finalized ({current}).")


@order_cmd.command("edit")
@click.argument("ref")
@click.option("--note", "notes", help="Update notes")
@click.option("--due", "due_date", help="Update due date")
@click.option("--due-time", help="Update due time")
@click.option("--phone", help="Update phone")
@click.option("--address", help="Update delivery address")
def order_edit(ref, notes, due_date, due_time, phone, address):
    """Edit order details."""
    with get_db() as conn:
        row = _resolve_order_ref(conn, ref)
        if not row:
            console.print(f"  [red]Order '{ref}' not found[/red]")
            return

        updates = []
        params = []
        if notes is not None:
            updates.append("notes = ?")
            params.append(notes)
        if due_date is not None:
            updates.append("due_date = ?")
            params.append(due_date)
        if due_time is not None:
            updates.append("due_time = ?")
            params.append(due_time)
        if phone is not None:
            updates.append("customer_phone = ?")
            params.append(phone)
        if address is not None:
            updates.append("delivery_address = ?")
            params.append(address)

        if not updates:
            console.print("  [dim]Nothing to update[/dim]")
            return

        updates.append("updated_at = ?")
        params.append(now_utc())
        params.append(row["id"])

        conn.execute(f"UPDATE orders SET {', '.join(updates)} WHERE id = ?", params)  # nosec B608
        console.print(f"  [green]Updated[/green] {row['order_ref']}")


@order_cmd.command("backfill")
def order_backfill():
    """Backfill old order items to match terminal order statuses."""
    with get_db() as conn:
        delivered = conn.execute(
            "UPDATE order_items SET status = 'delivered' "
            "WHERE order_id IN (SELECT id FROM orders WHERE status IN ('delivered', 'completed')) "
            "AND is_extra = 0 AND is_gift = 0 AND status != 'cancelled' AND status != 'delivered'"
        ).rowcount
        cancelled = conn.execute(
            "UPDATE order_items SET status = 'cancelled' "
            "WHERE order_id IN (SELECT id FROM orders WHERE status = 'cancelled') "
            "AND is_extra = 0 AND is_gift = 0 AND status != 'cancelled'"
        ).rowcount
        console.print(f"  [green]Backfilled[/green]: {delivered} items → delivered, {cancelled} items → cancelled")
