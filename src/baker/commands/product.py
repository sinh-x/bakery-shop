import click

from baker.db.connection import get_db
from baker.formatters.tables import console
from baker.code_gen import generate_code, get_category_prefix
from baker.utils.time import InvalidEffectiveFrom, format_effective_from

from rich.table import Table

_BS = "\\"


def _escape_like(value: str) -> str:
    return value.replace("%", _BS + "%").replace("_", _BS + "_")


@click.group("product")
def product_cmd():
    """Manage product catalog."""


@product_cmd.command("add")
@click.argument("name")
@click.option("--category", default="bread", help="Category slug (banh_mi, banh_kem, banh_ngot, cookie, khac)")
@click.option("--price", "base_price", type=float, default=0, help="Selling price")
@click.option("--cost", type=float, default=0, help="Production cost")
@click.option("--notes", "recipe_notes", default="", help="Recipe or production notes")
@click.option("--code", "product_code", default=None, help="Product code (e.g. BMI-01); auto-generated if omitted")
def product_add(name, category, base_price, cost, recipe_notes, product_code):
    """Add a product to the catalog."""
    with get_db() as conn:
        if product_code:
            prefix = get_category_prefix(conn, category)
            if "-" not in product_code:
                # Suffix-only — auto-prefix from category
                product_code = f"{prefix}-{product_code}" if prefix else product_code
            existing = conn.execute("SELECT id FROM products WHERE product_code = ?", (product_code,)).fetchone()
            if existing:
                console.print(f"  [red]Mã '{product_code}' đã tồn tại[/red]")
                return
            code = product_code
        else:
            code = generate_code(conn, category) or ""

        conn.execute(
            "INSERT INTO products (name, category, base_price, cost, recipe_notes, product_code) VALUES (?, ?, ?, ?, ?, ?)",
            (name, category, base_price, cost, recipe_notes, code),
        )
        margin = base_price - cost if base_price and cost else 0
        code_display = f" [{code}]" if code else ""
        console.print(f"  [green]Added[/green] {name}{code_display} (price: {base_price:.2f}, cost: {cost:.2f}, margin: {margin:.2f})")


@product_cmd.command("list")
@click.option("--category", help="Filter by category")
@click.option("--code", "code_filter", default=None, help="Filter by product code (partial match)")
def product_list(category, code_filter):
    """List products."""
    with get_db() as conn:
        conditions = ["active = 1"]
        params = []

        if category:
            conditions.append("category = ?")
            params.append(category)
        if code_filter:
            conditions.append("product_code LIKE ?")
            params.append(f"%{_escape_like(code_filter)}%")

        where = " AND ".join(conditions)
        rows = conn.execute(
            f"SELECT * FROM products WHERE {where} ORDER BY category, name",
            params,
        ).fetchall()

        if not rows:
            console.print("  [dim]No products found.[/dim]")
            return

        table = Table(title="Products", show_lines=False, padding=(0, 1))
        table.add_column("Code", style="cyan")
        table.add_column("Name", style="bold")
        table.add_column("Category", style="dim")
        table.add_column("Price", justify="right")
        table.add_column("Cost", justify="right")
        table.add_column("Margin", justify="right")

        for row in rows:
            margin = row["base_price"] - row["cost"] if row["base_price"] and row["cost"] else 0
            margin_style = "green" if margin > 0 else "red" if margin < 0 else ""
            table.add_row(
                row["product_code"] or "-",
                row["name"],
                row["category"],
                f"{row['base_price']:.2f}" if row["base_price"] else "-",
                f"{row['cost']:.2f}" if row["cost"] else "-",
                f"[{margin_style}]{margin:.2f}[/{margin_style}]" if margin else "-",
            )
        console.print(table)


@product_cmd.command("edit")
@click.argument("identifier")
@click.option("--price", "base_price", type=float, help="Update price")
@click.option("--cost", type=float, help="Update cost")
@click.option("--notes", "recipe_notes", help="Update recipe notes")
@click.option("--category", help="Update category")
@click.option("--code", "product_code", help="Update product code")
def product_edit(identifier, base_price, cost, recipe_notes, category, product_code):
    """Edit a product. IDENTIFIER can be a product code (e.g. BMI-01) or product name."""
    with get_db() as conn:
        # Try by code first, then by name
        row = conn.execute("SELECT * FROM products WHERE product_code = ?", (identifier,)).fetchone()
        if not row:
            row = conn.execute("SELECT * FROM products WHERE name = ?", (identifier,)).fetchone()
        if not row:
            console.print(f"  [red]Product '{identifier}' not found (tried code and name)[/red]")
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

        # Resolve effective category for prefix lookups
        effective_category = category if category is not None else row["category"]

        if product_code is not None:
            if "-" not in product_code:
                # Suffix-only — auto-prefix from effective category
                prefix = get_category_prefix(conn, effective_category)
                if prefix:
                    product_code = f"{prefix}-{product_code}"
            existing = conn.execute(
                "SELECT id FROM products WHERE product_code = ? AND id != ?",
                (product_code, row["id"]),
            ).fetchone()
            if existing:
                console.print(f"  [red]Mã '{product_code}' đã tồn tại[/red]")
                return
            updates.append("product_code = ?")
            params.append(product_code)
        elif category is not None and category != row["category"]:
            # Category changed, no explicit code — update prefix
            new_prefix = get_category_prefix(conn, category)
            current_code = row["product_code"] or ""
            if new_prefix and current_code and "-" in current_code:
                old_suffix = current_code.split("-", 1)[1]
                new_code = f"{new_prefix}-{old_suffix}"
                dup = conn.execute(
                    "SELECT id FROM products WHERE product_code = ? AND id != ?",
                    (new_code, row["id"]),
                ).fetchone()
                if dup:
                    console.print(f"  [yellow]Cảnh báo: Mã '{new_code}' đã tồn tại, giữ mã cũ[/yellow]")
                else:
                    updates.append("product_code = ?")
                    params.append(new_code)

        if not updates:
            console.print("  [dim]Nothing to update[/dim]")
            return

        params.append(row["id"])
        conn.execute(f"UPDATE products SET {', '.join(updates)} WHERE id = ?", params)
        display = row["product_code"] or row["name"]
        console.print(f"  [green]Updated[/green] {display}")


def _resolve_product(conn, identifier: str):
    """Resolve a product row by id, product_code, or name. Returns the row or None."""
    # Try numeric id first
    if identifier.isdigit():
        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (int(identifier),)
        ).fetchone()
        if row:
            return row
    # Then product_code
    row = conn.execute(
        "SELECT * FROM products WHERE product_code = ?", (identifier,)
    ).fetchone()
    if row:
        return row
    # Then name
    row = conn.execute(
        "SELECT * FROM products WHERE name = ?", (identifier,)
    ).fetchone()
    return row


def _normalize_effective_from(date_str):
    """Normalize a YYYY-MM-DD effective_from into a comparable UTC timestamp.

    Accepts YYYY-MM-DD (treated as start-of-day UTC) or a full ISO-8601 string.
    Raises click.BadParameter on invalid formats.
    """
    try:
        return format_effective_from(date_str)
    except InvalidEffectiveFrom as exc:
        raise click.BadParameter(str(exc))


@product_cmd.command("set-cost")
@click.argument("identifier")
@click.argument("cost", type=float)
@click.option(
    "--effective-from",
    "effective_from",
    default=None,
    help="Ngày hiệu lực (YYYY-MM-DD). Mặc định: hiện tại.",
)
def product_set_cost(identifier, cost, effective_from):
    """Đặt chi phí sản phẩm (cost_history CRUD).

    IDENTIFIER là product id, product code, hoặc tên sản phẩm.
    COST là chi phí sản xuất (VND).

    Idempotent: chạy lại với cùng --effective-from sẽ cập nhật chi phí
    thay vì tạo dòng mới. Bỏ --effective-from để tạo bản ghi tại thời điểm hiện tại.
    """
    if cost < 0:
        console.print("  [red]Chi phí không được âm[/red]")
        raise click.Abort()

    effective_ts = _normalize_effective_from(effective_from)

    with get_db() as conn:
        row = _resolve_product(conn, identifier)
        if not row:
            console.print(
                f"  [red]Không tìm thấy sản phẩm '{identifier}'[/red]"
            )
            raise click.Abort()

        product_id = row["id"]
        # Idempotent upsert: same (product_id, effective_from) → update cost.
        existing = conn.execute(
            "SELECT id FROM cost_history "
            "WHERE product_id = ? AND effective_from = ?",
            (product_id, effective_ts),
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE cost_history SET cost = ? WHERE id = ?",
                (cost, existing["id"]),
            )
            action = "Updated"
        else:
            conn.execute(
                "INSERT INTO cost_history (product_id, cost, effective_from) "
                "VALUES (?, ?, ?)",
                (product_id, cost, effective_ts),
            )
            action = "Created"

        display = row["product_code"] or row["name"]
        console.print(
            f"  [green]{action}[/green] cost_history for {display} "
            f"(id={product_id}): cost={cost:.2f} effective_from={effective_ts}"
        )

        # Show current effective cost for confirmation.
        from baker.services.cost_resolver import resolve_product_cost

        current = resolve_product_cost(conn, product_id)
        console.print(f"  [dim]Current effective cost: {current:.2f}[/dim]")
