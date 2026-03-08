import click

from baker.db.connection import get_db
from baker.models.order import Order, OrderItem, allowed_transitions
from baker.formatters.tables import console, print_orders_table, print_order_detail


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
            f"SELECT * FROM orders WHERE {where} ORDER BY due_date, due_time",
            params,
        ).fetchall()

        print_orders_table(rows)


@order_cmd.command("show")
@click.argument("ref")
def order_show(ref):
    """Show order details."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            console.print(f"  [red]Order '{ref}' not found[/red]")
            return
        print_order_detail(row)


@order_cmd.command("status")
@click.argument("ref")
@click.argument("new_status")
@click.option("--reason", default="", help="Reason for status change (especially for cancel)")
def order_status(ref, new_status, reason):
    """Update order status."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            console.print(f"  [red]Order '{ref}' not found[/red]")
            return

        current = row["status"]
        ok = Order.update_status(conn, ref, new_status, reason)
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
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
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

        updates.append("updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')")
        params.append(row["id"])

        conn.execute(f"UPDATE orders SET {', '.join(updates)} WHERE id = ?", params)
        console.print(f"  [green]Updated[/green] {row['order_ref']}")
