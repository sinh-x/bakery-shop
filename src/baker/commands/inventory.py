import click

from baker.db.connection import get_db
from baker.models.inventory import InventoryItem
from baker.formatters.tables import console, print_inventory_table


@click.group("inv")
def inv_cmd():
    """Track inventory and supplies."""


@inv_cmd.command("add")
@click.argument("name")
@click.option("--unit", default="kg", help="Unit of measure (kg, g, L, units, bags, boxes)")
@click.option("--category", default="ingredient", help="Category (ingredient, packaging, equipment, other)")
@click.option("--low", "low_threshold", type=float, default=0, help="Low stock alert threshold")
@click.option("--cost", "cost_per_unit", type=float, default=0, help="Cost per unit")
@click.option("--supplier", default="", help="Supplier name")
@click.option("--qty", "quantity", type=float, default=0, help="Initial quantity")
def inv_add(name, unit, category, low_threshold, cost_per_unit, supplier, quantity):
    """Add a new inventory item."""
    item = InventoryItem(
        name=name, unit=unit, category=category,
        low_threshold=low_threshold, cost_per_unit=cost_per_unit,
        supplier=supplier, quantity=quantity,
    )
    with get_db() as conn:
        item.save(conn)
        console.print(f"  [green]Added[/green] {name} ({quantity} {unit})")


@inv_cmd.command("receive")
@click.argument("name")
@click.argument("amount", type=float)
@click.option("--cost", type=float, default=None, help="Update cost per unit")
@click.option("--note", default="", help="Note about the delivery")
def inv_receive(name, amount, cost, note):
    """Record receiving supplies."""
    with get_db() as conn:
        try:
            new_qty = InventoryItem.receive(conn, name, amount, note, cost)
            row = conn.execute("SELECT unit FROM inventory WHERE name = ?", (name,)).fetchone()
            console.print(f"  [green]Received[/green] {amount} {row['unit']} {name} (now: {new_qty:.1f})")
        except ValueError as e:
            console.print(f"  [red]{e}[/red]")


@inv_cmd.command("use")
@click.argument("name")
@click.argument("amount", type=float)
@click.option("--for", "purpose", default="", help="What it was used for")
def inv_use(name, amount, purpose):
    """Record using supplies."""
    with get_db() as conn:
        try:
            new_qty = InventoryItem.use(conn, name, amount, purpose)
            row = conn.execute("SELECT unit FROM inventory WHERE name = ?", (name,)).fetchone()
            console.print(f"  [yellow]Used[/yellow] {amount} {row['unit']} {name} (now: {new_qty:.1f})")
        except ValueError as e:
            console.print(f"  [red]{e}[/red]")


@inv_cmd.command("set")
@click.argument("name")
@click.argument("quantity", type=float)
@click.option("--reason", default="", help="Reason for adjustment")
def inv_set(name, quantity, reason):
    """Set inventory to exact quantity (for corrections)."""
    with get_db() as conn:
        try:
            InventoryItem.set_quantity(conn, name, quantity, reason)
            console.print(f"  [green]Set[/green] {name} to {quantity:.1f}")
        except ValueError as e:
            console.print(f"  [red]{e}[/red]")


@inv_cmd.command("list")
@click.option("--low", is_flag=True, help="Only show low-stock items")
@click.option("--category", help="Filter by category")
def inv_list(low, category):
    """List inventory items."""
    with get_db() as conn:
        conditions = []
        params = []

        if low:
            conditions.append("low_threshold > 0 AND quantity <= low_threshold")
        if category:
            conditions.append("category = ?")
            params.append(category)

        where = " AND ".join(conditions) if conditions else "1=1"
        rows = conn.execute(
            f"SELECT * FROM inventory WHERE {where} ORDER BY category, name",
            params,
        ).fetchall()

        title = "Low Stock" if low else "Inventory"
        print_inventory_table(rows, title=title)


@inv_cmd.command("check")
@click.argument("name")
def inv_check(name):
    """Quick-check one inventory item."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM inventory WHERE name = ?", (name,)).fetchone()
        if not row:
            console.print(f"  [red]Item '{name}' not found[/red]")
            return

        item = InventoryItem.from_row(row)
        status = "[red bold]LOW[/red bold]" if item.is_low else "[green]OK[/green]"
        threshold = f" (threshold: {item.low_threshold:.1f})" if item.low_threshold else ""
        console.print(f"  {item.name}: {item.quantity:.1f} {item.unit}{threshold} -- {status}")
