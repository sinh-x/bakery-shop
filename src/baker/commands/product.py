import click

from baker.db.connection import get_db
from baker.formatters.tables import console

from rich.table import Table


@click.group("product")
def product_cmd():
    """Manage product catalog."""


@product_cmd.command("add")
@click.argument("name")
@click.option("--category", default="bread", help="Category (bread, pastry, cake, cookie, other)")
@click.option("--price", "base_price", type=float, default=0, help="Selling price")
@click.option("--cost", type=float, default=0, help="Production cost")
@click.option("--notes", "recipe_notes", default="", help="Recipe or production notes")
def product_add(name, category, base_price, cost, recipe_notes):
    """Add a product to the catalog."""
    with get_db() as conn:
        conn.execute(
            "INSERT INTO products (name, category, base_price, cost, recipe_notes) VALUES (?, ?, ?, ?, ?)",
            (name, category, base_price, cost, recipe_notes),
        )
        margin = base_price - cost if base_price and cost else 0
        console.print(f"  [green]Added[/green] {name} (price: {base_price:.2f}, cost: {cost:.2f}, margin: {margin:.2f})")


@product_cmd.command("list")
@click.option("--category", help="Filter by category")
def product_list(category):
    """List products."""
    with get_db() as conn:
        if category:
            rows = conn.execute("SELECT * FROM products WHERE category = ? AND active = 1 ORDER BY category, name", (category,)).fetchall()
        else:
            rows = conn.execute("SELECT * FROM products WHERE active = 1 ORDER BY category, name").fetchall()

        if not rows:
            console.print("  [dim]No products found.[/dim]")
            return

        table = Table(title="Products", show_lines=False, padding=(0, 1))
        table.add_column("Name", style="bold")
        table.add_column("Category", style="dim")
        table.add_column("Price", justify="right")
        table.add_column("Cost", justify="right")
        table.add_column("Margin", justify="right")

        for row in rows:
            margin = row["base_price"] - row["cost"] if row["base_price"] and row["cost"] else 0
            margin_style = "green" if margin > 0 else "red" if margin < 0 else ""
            table.add_row(
                row["name"],
                row["category"],
                f"{row['base_price']:.2f}" if row["base_price"] else "-",
                f"{row['cost']:.2f}" if row["cost"] else "-",
                f"[{margin_style}]{margin:.2f}[/{margin_style}]" if margin else "-",
            )
        console.print(table)


@product_cmd.command("edit")
@click.argument("name")
@click.option("--price", "base_price", type=float, help="Update price")
@click.option("--cost", type=float, help="Update cost")
@click.option("--notes", "recipe_notes", help="Update recipe notes")
@click.option("--category", help="Update category")
def product_edit(name, base_price, cost, recipe_notes, category):
    """Edit a product."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM products WHERE name = ?", (name,)).fetchone()
        if not row:
            console.print(f"  [red]Product '{name}' not found[/red]")
            return

        updates = []
        params = []
        if base_price is not None:
            updates.append("base_price = ?")
            params.append(base_price)
        if cost is not None:
            updates.append("cost = ?")
            params.append(cost)
        if recipe_notes is not None:
            updates.append("recipe_notes = ?")
            params.append(recipe_notes)
        if category is not None:
            updates.append("category = ?")
            params.append(category)

        if not updates:
            console.print("  [dim]Nothing to update[/dim]")
            return

        params.append(row["id"])
        conn.execute(f"UPDATE products SET {', '.join(updates)} WHERE id = ?", params)
        console.print(f"  [green]Updated[/green] {name}")
