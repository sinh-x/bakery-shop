"""Reusable query helpers."""

import json
from datetime import datetime, timedelta


def today_range():
    """Return (start, end) ISO strings for today."""
    today = datetime.now().strftime("%Y-%m-%d")
    return f"{today}T00:00:00", f"{today}T23:59:59"


def week_range():
    """Return (start, end) ISO strings for the current week (Mon-Sun)."""
    now = datetime.now()
    monday = now - timedelta(days=now.weekday())
    sunday = monday + timedelta(days=6)
    return monday.strftime("%Y-%m-%dT00:00:00"), sunday.strftime("%Y-%m-%dT23:59:59")


def month_range():
    """Return (start, end) ISO strings for the current month."""
    now = datetime.now()
    start = now.replace(day=1)
    if now.month == 12:
        end = now.replace(year=now.year + 1, month=1, day=1) - timedelta(days=1)
    else:
        end = now.replace(month=now.month + 1, day=1) - timedelta(days=1)
    return start.strftime("%Y-%m-%dT00:00:00"), end.strftime("%Y-%m-%dT23:59:59")


def fetch_events(conn, *, event_type=None, tags=None, since=None, until=None,
                 search=None, untagged=False, limit=50):
    """Fetch events with optional filters."""
    conditions = []
    params = []

    if event_type:
        conditions.append("type = ?")
        params.append(event_type)
    if tags:
        for tag in tags:
            conditions.append("(',' || tags || ',') LIKE ?")
            params.append(f"%,{tag},%")
    if since:
        conditions.append("timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("timestamp <= ?")
        params.append(until)
    if search:
        conditions.append("summary LIKE ?")
        params.append(f"%{search}%")
    if untagged:
        conditions.append("(tags = '' OR tags IS NULL)")

    where = " AND ".join(conditions) if conditions else "1=1"
    query = f"SELECT * FROM events WHERE {where} ORDER BY timestamp DESC LIMIT ?"
    params.append(limit)

    return conn.execute(query, params).fetchall()


def count_events_by_type(conn, since=None, until=None):
    """Count events grouped by type within a time range."""
    conditions = []
    params = []
    if since:
        conditions.append("timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("timestamp <= ?")
        params.append(until)

    where = " AND ".join(conditions) if conditions else "1=1"
    query = f"SELECT type, COUNT(*) as cnt FROM events WHERE {where} GROUP BY type"
    return conn.execute(query, params).fetchall()


def sum_sales(conn, since=None, until=None):
    """Sum up sale amounts from event data JSON."""
    conditions = ["type = 'sale'"]
    params = []
    if since:
        conditions.append("timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("timestamp <= ?")
        params.append(until)

    where = " AND ".join(conditions)
    query = f"""SELECT COALESCE(SUM(
        CASE WHEN json_valid(data) THEN json_extract(data, '$.amount') ELSE 0 END
    ), 0) as total FROM events WHERE {where}"""
    row = conn.execute(query, params).fetchone()
    return row[0] if row else 0
