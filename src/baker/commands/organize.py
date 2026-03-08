import click

from baker.db.connection import get_db
from baker.db.queries import fetch_events, today_range
from baker.models.event import Event, TYPE_ALIASES
from baker.formatters.tables import console, print_events_table


@click.group("organize", invoke_without_command=True)
@click.option("--today", "today_only", is_flag=True, help="Only show today's events")
@click.option("--type", "event_type", help="Filter by event type")
@click.option("--untagged", is_flag=True, help="Show only untagged events")
@click.option("-n", "--limit", default=20, help="Number of events to show")
@click.pass_context
def organize_cmd(ctx, today_only, event_type, untagged, limit):
    """Review and organize past events. Shows events that need categorizing."""
    if ctx.invoked_subcommand is not None:
        return

    with get_db() as conn:
        since, until = (today_range() if today_only else (None, None))

        # Default: show untagged notes (events needing organization)
        if not event_type and not untagged:
            untagged = True
            event_type = "note"

        rows = fetch_events(conn, event_type=event_type, since=since,
                           until=until, untagged=untagged, limit=limit)

        title = "Events to organize"
        if event_type:
            title += f" (type: {event_type})"
        if today_only:
            title += " (today)"

        print_events_table(rows, title=title)

        if rows:
            console.print(f"\n  [dim]Use 'baker tag <id> <tags>' or 'baker retype <id> <type>' to organize[/dim]")


@click.command("tag")
@click.argument("event_id", type=int)
@click.argument("tags")
def tag_cmd(event_id, tags):
    """Add tags to an event. Tags are comma-separated."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        if not row:
            console.print(f"  [red]Event #{event_id} not found[/red]")
            return

        existing = row["tags"] or ""
        new_tags = set(t.strip() for t in existing.split(",") if t.strip())
        new_tags.update(t.strip() for t in tags.split(",") if t.strip())
        tags_str = ",".join(sorted(new_tags))

        conn.execute("UPDATE events SET tags = ? WHERE id = ?", (tags_str, event_id))
        console.print(f"  [green]Tagged[/green] #{event_id} -> [{tags_str}]")


@click.command("retype")
@click.argument("event_id", type=int)
@click.argument("new_type")
def retype_cmd(event_id, new_type):
    """Change the type of an event."""
    resolved = TYPE_ALIASES.get(new_type, new_type)

    with get_db() as conn:
        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        if not row:
            console.print(f"  [red]Event #{event_id} not found[/red]")
            return

        old_type = row["type"]
        conn.execute("UPDATE events SET type = ? WHERE id = ?", (resolved, event_id))
        console.print(f"  [green]Retyped[/green] #{event_id}: {old_type} -> {resolved}")
