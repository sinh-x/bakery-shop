import click

from baker.db.connection import get_db
from baker.db.queries import fetch_staff, find_staff_by_name, fetch_events_by_person
from baker.models.staff import Staff, ROLES, resolve_role
from baker.formatters.tables import console, print_events_table, print_staff_table


@click.group("staff")
def staff_cmd():
    """Manage bakery staff."""


@staff_cmd.command("add")
@click.argument("name")
@click.option("--role", multiple=True, help="Staff role(s) (repeatable)")
@click.option("--phone", default="", help="Phone number")
def staff_add(name, role, phone):
    """Register a new staff member."""
    with get_db() as conn:
        existing = find_staff_by_name(conn, name)
        if existing:
            console.print(f"  [red]Staff '{name}' already exists (#{existing['id']})[/red]")
            return

        resolved = [resolve_role(r) for r in role]
        staff = Staff(name=name, role=",".join(resolved), phone=phone)
        staff.save(conn)
        role_str = f" ({staff.role})" if staff.role else ""
        console.print(f"  [green]Added[/green] staff #{staff.id} {name}{role_str}")


@staff_cmd.command("roles")
def staff_roles():
    """List available bakery roles."""
    console.print("\n  [bold]Available roles:[/bold]\n")
    for role_id, label in ROLES.items():
        console.print(f"  {role_id:>12}  {label}")
    console.print("")


@staff_cmd.command("list")
@click.option("--all", "show_all", is_flag=True, help="Include inactive staff")
def staff_list(show_all):
    """List staff members."""
    with get_db() as conn:
        rows = fetch_staff(conn, active_only=not show_all)
        print_staff_table(rows)


@staff_cmd.command("report")
@click.argument("name")
@click.option("-n", "--limit", default=50, help="Max events")
def staff_report(name, limit):
    """Show events logged by or involving a person."""
    with get_db() as conn:
        staff = find_staff_by_name(conn, name)
        if not staff:
            console.print(f"  [dim]No staff member named '{name}' (showing events with logged_by match)[/dim]")

        rows = fetch_events_by_person(conn, name, limit=limit)
        title = f"Events for {name}"
        print_events_table(rows, title=title)
