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
    if not code_prefix.isalpha() or not code_prefix.isupper() or not (2 <= len(code_prefix) <= 3):
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
