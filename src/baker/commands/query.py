import csv
import io
import json

import click

from baker.db.connection import get_db
from baker.db.queries import fetch_events, today_range, week_range, month_range, sum_sales
from baker.formatters.tables import console, print_events_table


@click.group("query")
def query_cmd():
    """Search events and generate reports."""


@query_cmd.command("events")
@click.option("--type", "event_type", help="Filter by event type")
@click.option("--tag", multiple=True, help="Filter by tag")
@click.option("--search", help="Search in summary text")
@click.option("--since", help="From date (YYYY-MM-DD)")
@click.option("--until", help="To date (YYYY-MM-DD)")
@click.option("--today", "today_only", is_flag=True, help="Today's events only")
@click.option("--week", "week_only", is_flag=True, help="This week's events only")
@click.option("--untagged", is_flag=True, help="Only untagged events")
@click.option("-n", "--limit", default=50, help="Max results")
@click.option("--format", "fmt", type=click.Choice(["table", "csv", "json"]), default="table")
def query_events(event_type, tag, search, since, until, today_only, week_only, untagged, limit, fmt):
    """Search and filter events."""
    if today_only:
        since, until = today_range()
    elif week_only:
        since, until = week_range()

    with get_db() as conn:
        rows = fetch_events(
            conn, event_type=event_type, tags=list(tag) if tag else None,
            search=search, since=since, until=until, untagged=untagged, limit=limit,
        )

        if fmt == "table":
            print_events_table(rows)
        elif fmt == "csv":
            output = io.StringIO()
            writer = csv.writer(output)
            writer.writerow(["id", "timestamp", "type", "summary", "data", "tags"])
            for r in rows:
                writer.writerow([r["id"], r["timestamp"], r["type"], r["summary"], r["data"], r["tags"]])
            click.echo(output.getvalue())
        elif fmt == "json":
            result = []
            for r in rows:
                result.append({
                    "id": r["id"], "timestamp": r["timestamp"], "type": r["type"],
                    "summary": r["summary"], "data": json.loads(r["data"]) if r["data"] else {},
                    "tags": r["tags"],
                })
            click.echo(json.dumps(result, indent=2))


@query_cmd.command("sales")
@click.option("--today", "today_only", is_flag=True, help="Today")
@click.option("--week", "week_only", is_flag=True, help="This week")
@click.option("--month", "month_only", is_flag=True, help="This month")
@click.option("--since", help="From date")
@click.option("--until", help="To date")
def query_sales(today_only, week_only, month_only, since, until):
    """Sales summary."""
    if today_only:
        since, until = today_range()
        period = "Today"
    elif week_only:
        since, until = week_range()
        period = "This week"
    elif month_only:
        since, until = month_range()
        period = "This month"
    else:
        period = "All time"

    with get_db() as conn:
        total = sum_sales(conn, since=since, until=until)
        rows = fetch_events(conn, event_type="sale", since=since, until=until, limit=100)

        console.print(f"\n  [bold]Sales Summary: {period}[/bold]")
        console.print(f"  Total (from data.amount): {total:.2f}")
        console.print(f"  Sale events: {len(rows)}")

        if rows:
            console.print("")
            print_events_table(rows, title="Sale Events")
