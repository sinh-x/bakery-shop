"""Reusable query helpers."""

import json
from datetime import datetime, timedelta, timezone

from baker.db.schema import EXPENSE_DEBT_PAYMENT_METHOD

_BS = "\\"


def _escape_like(value: str) -> str:
    return value.replace("%", _BS + "%").replace("_", _BS + "_")


def today_range():
    """Return (start, end) UTC ISO strings for the current UTC day.

    Bounds are ``Z``-suffixed so they compare correctly against the UTC
    timestamps stored in the database (DG-202 FR1).
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return f"{today}T00:00:00Z", f"{today}T23:59:59Z"


def week_range():
    """Return (start, end) UTC ISO strings for the current UTC week (Mon-Sun)."""
    now = datetime.now(timezone.utc)
    monday = now - timedelta(days=now.weekday())
    sunday = monday + timedelta(days=6)
    return monday.strftime("%Y-%m-%dT00:00:00Z"), sunday.strftime("%Y-%m-%dT23:59:59Z")


def month_range():
    """Return (start, end) UTC ISO strings for the current UTC month."""
    now = datetime.now(timezone.utc)
    start = now.replace(day=1)
    if now.month == 12:
        end = now.replace(year=now.year + 1, month=1, day=1) - timedelta(days=1)
    else:
        end = now.replace(month=now.month + 1, day=1) - timedelta(days=1)
    return start.strftime("%Y-%m-%dT00:00:00Z"), end.strftime("%Y-%m-%dT23:59:59Z")


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
           WHERE (LOWER(e.logged_by) = LOWER(?)
              OR LOWER(s.name) = LOWER(?))
             AND e.deleted_at IS NULL
           ORDER BY e.timestamp DESC LIMIT ?""",
        (staff_name, staff_name, limit),
    ).fetchall()


def count_events_by_logger(conn, since=None, until=None):
    """Count events grouped by logged_by within a time range."""
    conditions = ["logged_by != ''", "deleted_at IS NULL"]
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
                 expense_staff_name=None, expense_paid_by_name=None,
                 expense_payment_source=None,
                 expense_search=None, debt_status=None, limit=50):
    """Fetch events with optional filters.

    ``debt_status`` filters debt (``payment_method = 'Nợ'``) expenses by
    settlement state. Values: ``all`` (default — no filter applied), ``unpaid``
    (no settlements yet), ``paid`` (fully settled), ``partial`` (partially
    settled). Non-debt expenses are unaffected by this filter.
    """
    joins = []
    conditions = ["e.deleted_at IS NULL"]
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
            params.append(f"%,{_escape_like(tag)},%")
    if since:
        conditions.append("e.timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("e.timestamp <= ?")
        params.append(until)
    if search:
        conditions.append("e.summary LIKE ?")
        params.append(f"%{_escape_like(search)}%")
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
            "LOWER(COALESCE(e.logged_by, '')) = LOWER(?)"
        )
        params.append(expense_staff_name)
    if expense_paid_by_name:
        conditions.append(
            "LOWER(COALESCE(json_extract(e.data, '$.paid_by_name'), '')) = LOWER(?)"
        )
        params.append(expense_paid_by_name)
    if expense_payment_source:
        conditions.append(
            "LOWER(COALESCE(json_extract(e.data, '$.payment_source'), '')) = LOWER(?)"
        )
        params.append(expense_payment_source)
    if expense_search:
        conditions.append(
            "("
            "LOWER(e.summary) LIKE LOWER(?) OR "
            "LOWER(COALESCE(e.logged_by, '')) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.vendor'), '')) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.note'), '')) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.paid_by_name'), '')) LIKE LOWER(?) OR "
            "LOWER(COALESCE(json_extract(e.data, '$.payment_source'), '')) LIKE LOWER(?)"
            ")"
        )
        like = f"%{expense_search}%"
        params.extend([like, like, like, like, like, like])

    if debt_status and debt_status != "all":
        # Debt status filter (FR7, DG-212 Phase 2). Only applies to expenses
        # whose payment_method is "Nợ" — non-debt expenses always pass through.
        # Status is derived from the ``settlements`` array stored in the
        # expense data JSON: remaining = amount_vnd − sum(settlement amounts).
        debt_method = EXPENSE_DEBT_PAYMENT_METHOD
        if debt_status == "unpaid":
            # No settlements recorded yet (settlements array missing/empty)
            # AND payment_method = "Nợ".
            conditions.append(
                "(COALESCE(json_extract(e.data, '$.payment_method'), '') = ? "
                " AND (json_extract(e.data, '$.settlements') IS NULL "
                "      OR json_array_length(json_extract(e.data, '$.settlements')) = 0))"
            )
            params.append(debt_method)
        elif debt_status == "paid":
            # Fully settled: settlements exist and remaining <= 0.
            conditions.append(
                "(COALESCE(json_extract(e.data, '$.payment_method'), '') = ? "
                " AND json_array_length(json_extract(e.data, '$.settlements')) > 0 "
                " AND CAST(json_extract(e.data, '$.amount_vnd') AS REAL) "
                "     - COALESCE((SELECT SUM(CAST(json_extract(value, '$.amount') AS REAL) "
                "                  FROM json_each(json_extract(e.data, '$.settlements'))), 0) "
                "     <= 0)"
            )
            params.append(debt_method)
        elif debt_status == "partial":
            # Partial: settlements exist but remaining > 0.
            conditions.append(
                "(COALESCE(json_extract(e.data, '$.payment_method'), '') = ? "
                " AND json_array_length(json_extract(e.data, '$.settlements')) > 0 "
                " AND CAST(json_extract(e.data, '$.amount_vnd') AS REAL) "
                "     - COALESCE((SELECT SUM(CAST(json_extract(value, '$.amount') AS REAL) "
                "                  FROM json_each(json_extract(e.data, '$.settlements'))), 0) "
                "     > 0)"
            )
            params.append(debt_method)

    where = " AND ".join(conditions) if conditions else "1=1"
    join_clause = " ".join(joins)
    query = f"SELECT DISTINCT e.* FROM events e {join_clause} WHERE {where} ORDER BY e.timestamp DESC LIMIT ?"
    params.append(limit)

    return conn.execute(query, params).fetchall()


def count_events_by_type(conn, since=None, until=None):
    """Count events grouped by type within a time range."""
    conditions = ["deleted_at IS NULL"]
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
    conditions = ["type = 'sale'", "deleted_at IS NULL"]
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


def fetch_debts(conn, *, creditor=None, since=None, until=None, status=None):
    """Fetch outstanding debt expenses (FR5, DG-212 Phase 2).

    Returns a list of dicts with: ``event_id``, ``summary``, ``vendor``
    (creditor), ``amount_vnd``, ``settled_amount`` (sum of settlements),
    ``remaining`` (amount_vnd − settled), ``status`` (``unpaid`` /
    ``partial`` / ``paid``), and ``timestamp``.

    Optional filters:
      - ``creditor``: case-insensitive exact match on ``data.vendor``.
      - ``since`` / ``until``: timestamp range bounds (ISO strings).
      - ``status``: ``all`` (default — no filter), ``unpaid``, ``paid``,
        ``partial``.

    Only non-deleted expense events with ``payment_method = 'Nợ'`` are
    considered. Settlements are accumulated from the ``settlements`` array
    stored in the expense data JSON (each entry has an ``amount`` field).
    """
    conditions = [
        "e.type = 'expense'",
        "e.deleted_at IS NULL",
        "COALESCE(json_extract(e.data, '$.payment_method'), '') = ?",
    ]
    params: list = [EXPENSE_DEBT_PAYMENT_METHOD]
    if creditor:
        conditions.append(
            "LOWER(COALESCE(json_extract(e.data, '$.vendor'), '')) = LOWER(?)"
        )
        params.append(creditor)
    if since:
        conditions.append("e.timestamp >= ?")
        params.append(since)
    if until:
        conditions.append("e.timestamp <= ?")
        params.append(until)

    where = " AND ".join(conditions)
    query = (
        f"SELECT e.id AS event_id, e.summary, e.timestamp, "
        f"CAST(json_extract(e.data, '$.amount_vnd') AS REAL) AS amount_vnd, "
        f"COALESCE(json_extract(e.data, '$.vendor'), '') AS vendor, "
        f"COALESCE((SELECT SUM(CAST(json_extract(value, '$.amount') AS REAL)) "
        f"          FROM json_each(json_extract(e.data, '$.settlements'))), 0) "
        f"  AS settled_amount "
        f"FROM events e WHERE {where} "
        f"ORDER BY e.timestamp DESC, e.id DESC"
    )
    rows = conn.execute(query, params).fetchall()
    debts = []
    for r in rows:
        amount = float(r["amount_vnd"] or 0)
        settled = float(r["settled_amount"] or 0)
        remaining = max(0.0, amount - settled)
        if remaining <= 0:
            row_status = "paid"
        elif settled > 0:
            row_status = "partial"
        else:
            row_status = "unpaid"
        if status and status != "all" and row_status != status:
            continue
        debts.append({
            "event_id": int(r["event_id"]),
            "summary": r["summary"],
            "vendor": r["vendor"],
            "amount_vnd": amount,
            "settled_amount": settled,
            "remaining": remaining,
            "status": row_status,
            "timestamp": r["timestamp"],
        })
    return debts
