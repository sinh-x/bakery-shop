import click

from baker.db.connection import get_db
from baker.formatters.tables import console

from rich.table import Table


@click.group("category")
def category_cmd():
    """Manage product categories."""


@category_cmd.command("list")
def category_list():
    """List all categories."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT slug, name, code_prefix, active FROM categories ORDER BY slug"
        ).fetchall()

        if not rows:
            console.print("  [dim]No categories found.[/dim]")
            return

        table = Table(title="Categories", show_lines=False, padding=(0, 1))
        table.add_column("Slug", style="cyan")
        table.add_column("Name", style="bold")
        table.add_column("Code Prefix", justify="center")
        table.add_column("Active", justify="center")

        for row in rows:
            active_display = "[green]yes[/green]" if row["active"] else "[dim]no[/dim]"
            table.add_row(row["slug"], row["name"], row["code_prefix"], active_display)

        console.print(table)


@category_cmd.command("add")
@click.argument("slug")
@click.argument("name")
@click.argument("code_prefix")
def category_add(slug, name, code_prefix):
    """Add a new category. SLUG is the identifier (e.g. banh_mi), NAME is display name, CODE_PREFIX is 2-3 uppercase letters (e.g. BMI)."""
    if not code_prefix.isalpha() or not code_prefix.isupper() or not (2 <= len(code_prefix) <= 4):
        console.print(f"  [red]Code prefix must be 2-3 uppercase letters (e.g. BMI, BKS)[/red]")
        return

    with get_db() as conn:
        existing = conn.execute("SELECT id FROM categories WHERE slug = ?", (slug,)).fetchone()
        if existing:
            console.print(f"  [red]Category '{slug}' already exists[/red]")
            return

        conn.execute(
            "INSERT INTO categories (slug, name, code_prefix) VALUES (?, ?, ?)",
            (slug, name, code_prefix),
        )
        console.print(f"  [green]Added[/green] category '{slug}' ({name}, prefix: {code_prefix})")


@category_cmd.command("edit")
@click.argument("slug")
@click.option("--name", help="New display name")
@click.option("--prefix", "code_prefix", help="New code prefix (2-4 uppercase letters); cascades to all products")
def category_edit(slug, name, code_prefix):
    """Edit a category. Changing --prefix cascades to all products in the category."""
    if code_prefix is not None:
        if not code_prefix.isalpha() or not code_prefix.isupper() or not (2 <= len(code_prefix) <= 4):
            console.print("  [red]Code prefix must be 2-4 uppercase letters (e.g. BMI, BKSC)[/red]")
            return

    with get_db() as conn:
        row = conn.execute("SELECT * FROM categories WHERE slug = ?", (slug,)).fetchone()
        if not row:
            console.print(f"  [red]Category '{slug}' not found[/red]")
            return

        updates = []
        params = []
        if name is not None:
            updates.append("name = ?")
            params.append(name)

        old_prefix = row["code_prefix"]
        prefix_changed = code_prefix is not None and code_prefix != old_prefix
        if code_prefix is not None:
            updates.append("code_prefix = ?")
            params.append(code_prefix)

        if not updates:
            console.print("  [dim]Nothing to update[/dim]")
            return

        params.append(row["id"])
        conn.execute(f"UPDATE categories SET {', '.join(updates)} WHERE id = ?", params)

        if prefix_changed:
            result = conn.execute(
                "UPDATE products "
                "SET product_code = ? || substr(product_code, length(?)+1) "
                "WHERE category = ? AND product_code LIKE ?",
                (code_prefix, old_prefix, slug, f"{old_prefix}-%"),
            )
            if result.rowcount:
                console.print(f"  [dim]Cập nhật mã cho {result.rowcount} sản phẩm[/dim]")

        console.print(f"  [green]Updated[/green] category '{slug}'")
