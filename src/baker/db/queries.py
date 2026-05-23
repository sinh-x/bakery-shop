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


def fetch_staff(conn, *, active_only=True):
    """Fetch staff members."""
    if active_only:
        return conn.execute(
            "SELECT * FROM staff WHERE active = 1 ORDER BY name"
        ).fetchall()
    return conn.execute("SELECT * FROM staff ORDER BY name").fetchall()


def find_staff_by_name(conn, name):
    """Find a staff member by name (case-insensitive)."""
    return conn.execute(
        "SELECT * FROM staff WHERE LOWER(name) = LOWER(?)", (name,)
    ).fetchone()


def link_event_person(conn, event_id, staff_id, role="involved"):
    """Create an event_people link."""
    conn.execute(
        "INSERT OR IGNORE INTO event_people (event_id, staff_id, role) VALUES (?, ?, ?)",
        (event_id, staff_id, role),
    )


def fetch_events_by_person(conn, staff_name, *, limit=50):
    """Fetch events where a person was logger or involved."""
    return conn.execute(
        """SELECT DISTINCT e.* FROM events e
           LEFT JOIN event_people ep ON e.id = ep.event_id
           LEFT JOIN staff s ON ep.staff_id = s.id
           WHERE LOWER(e.logged_by) = LOWER(?)
              OR LOWER(s.name) = LOWER(?)
           ORDER BY e.timestamp DESC LIMIT ?""",
        (staff_name, staff_name, limit),
    ).fetchall()


def count_events_by_logger(conn, since=None, until=None):
    """Count events grouped by logged_by within a time range."""
    conditions = ["logged_by != ''"]
    params = []
    if since:
        conditions.append("timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("timestamp <= ?")
        params.append(until)

    where = " AND ".join(conditions)
    return conn.execute(
        f"SELECT logged_by, COUNT(*) as cnt FROM events WHERE {where} GROUP BY logged_by",
        params,
    ).fetchall()


def fetch_events(conn, *, event_type=None, tags=None, since=None, until=None,
                 search=None, untagged=False, logged_by=None, involving=None,
                 expense_category=None, expense_payment_method=None,
                 expense_staff_name=None, expense_search=None, limit=50):
    """Fetch events with optional filters."""
    joins = []
    conditions = []
    params = []

    if involving:
        joins.append("JOIN event_people ep ON e.id = ep.event_id")
        joins.append("JOIN staff s ON ep.staff_id = s.id")
        conditions.append("LOWER(s.name) = LOWER(?)")
        params.append(involving)

    if event_type:
        conditions.append("e.type = ?")
        params.append(event_type)
    if tags:
        for tag in tags:
            conditions.append("(',' || e.tags || ',') LIKE ?")
            params.append(f"%,{tag},%")
    if since:
        conditions.append("e.timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("e.timestamp <= ?")
        params.append(until)
    if search:
        conditions.append("e.summary LIKE ?")
        params.append(f"%{search}%")
    if untagged:
        conditions.append("(e.tags = '' OR e.tags IS NULL)")
    if logged_by:
        conditions.append("LOWER(e.logged_by) = LOWER(?)")
        params.append(logged_by)

    if expense_category:
        conditions.append(
            "LOWER(COALESCE(json_extract(e.data, '$.category'), '')) = LOWER(?)"
        )
        params.append(expense_category)
    if expense_payment_method:
        conditions.append(
            "LOWER(COALESCE(json_extract(e.data, '$.payment_method'), '')) = LOWER(?)"
        )
        params.append(expense_payment_method)
    if expense_staff_name:
        conditions.append(
            "LOWER(COALESCE(json_extract(e.data, '$.staff_name'), '')) = LOWER(?)"
        )
        params.append(expense_staff_name)
    if expense_search:
        conditions.append(
            "("
            "LOWER(e.summary) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.vendor'), '')) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.note'), '')) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.staff_name'), '')) LIKE LOWER(?)"
            ")"
        )
        like = f"%{expense_search}%"
        params.extend([like, like, like, like])

    where = " AND ".join(conditions) if conditions else "1=1"
    join_clause = " ".join(joins)
    query = f"SELECT DISTINCT e.* FROM events e {join_clause} WHERE {where} ORDER BY e.timestamp DESC LIMIT ?"
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
