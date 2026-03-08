import click

from baker.db.connection import get_db
from baker.db.queries import find_staff_by_name, link_event_person
from baker.models.event import Event
from baker.formatters.tables import console


@click.command("log")
@click.argument("message")
@click.option("-t", "--type", "event_type", default="note", help="Event type (note, prod, sale, inv, exp, del, ord)")
@click.option("--tag", multiple=True, help="Tags for filtering (repeatable)")
@click.option("-d", "--data", "data_pairs", multiple=True, help="Key=value data pairs (repeatable)")
@click.option("--by", "logged_by", default="", help="Who is logging this event")
@click.option("--with", "with_people", multiple=True, help="People involved (repeatable)")
def log_cmd(message, event_type, tag, data_pairs, logged_by, with_people):
    """Log an event quickly. Just type what happened."""
    data = {}
    for pair in data_pairs:
        if "=" in pair:
            k, v = pair.split("=", 1)
            try:
                v = float(v) if "." in v else int(v)
            except ValueError:
                pass
            data[k] = v

    event = Event(summary=message, type=event_type, data=data, tags=list(tag),
                  logged_by=logged_by)

    with get_db() as conn:
        event.save(conn)

        # Link logger to event_people if they exist in staff table
        if logged_by:
            staff = find_staff_by_name(conn, logged_by)
            if staff:
                link_event_person(conn, event.id, staff["id"], "logged_by")

        # Link involved people
        for person in with_people:
            staff = find_staff_by_name(conn, person)
            if staff:
                link_event_person(conn, event.id, staff["id"], "involved")

        by_str = f" [dim]by {logged_by}[/dim]" if logged_by else ""
        console.print(f"  [green]Logged[/green] #{event.id} \\[{event.type}] {message}{by_str}")
