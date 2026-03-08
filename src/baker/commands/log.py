import click

from baker.db.connection import get_db
from baker.models.event import Event
from baker.formatters.tables import console


@click.command("log")
@click.argument("message")
@click.option("-t", "--type", "event_type", default="note", help="Event type (note, prod, sale, inv, exp, del, ord)")
@click.option("--tag", multiple=True, help="Tags for filtering (repeatable)")
@click.option("-d", "--data", "data_pairs", multiple=True, help="Key=value data pairs (repeatable)")
def log_cmd(message, event_type, tag, data_pairs):
    """Log an event quickly. Just type what happened."""
    data = {}
    for pair in data_pairs:
        if "=" in pair:
            k, v = pair.split("=", 1)
            # Try to parse numbers
            try:
                v = float(v) if "." in v else int(v)
            except ValueError:
                pass
            data[k] = v

    event = Event(summary=message, type=event_type, data=data, tags=list(tag))

    with get_db() as conn:
        event.save(conn)
        console.print(f"  [green]Logged[/green] #{event.id} \\[{event.type}] {message}")
