import click
from datetime import datetime

from baker.db.connection import get_db
from baker.db.queries import today_range, count_events_by_type
from baker.formatters.tables import console, print_dashboard


@click.command("daily")
def daily_cmd():
    """Show today's dashboard."""
    with get_db() as conn:
        today = datetime.now().strftime("%Y-%m-%d")
        since, until = today_range()

        # Orders due today
        orders_due = conn.execute(
            "SELECT * FROM orders WHERE due_date = ? AND status NOT IN ('completed', 'cancelled') ORDER BY due_time",
            (today,),
        ).fetchall()

        # Low stock items
        low_stock = conn.execute(
            "SELECT * FROM inventory WHERE low_threshold > 0 AND quantity <= low_threshold ORDER BY name",
        ).fetchall()

        # Event counts
        event_counts = count_events_by_type(conn, since=since, until=until)
        total_events = sum(r["cnt"] for r in event_counts)

        print_dashboard(orders_due, low_stock, event_counts, total_events)
