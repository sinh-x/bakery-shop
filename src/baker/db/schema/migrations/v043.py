"""Migration v043: _migrate_v43_event_history_and_soft_delete (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v43_event_history_and_soft_delete(conn):
    """Create event_history table, add soft-delete columns to events,
    backfill expense staff_name values as audit entries."""
    import json

    conn.executescript(EVENT_HISTORY_AND_SOFT_DELETE_SCHEMA)

    _guard_add_column(conn, "events", "deleted_at", "deleted_at TEXT")
    _guard_add_column(conn, "events", "deleted_by", "deleted_by TEXT DEFAULT ''")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_events_deleted_at ON events(deleted_at)"
    )

    rows = conn.execute(
        "SELECT id, data, logged_by, timestamp FROM events WHERE type = 'expense'"
    ).fetchall()

    for row in rows:
        try:
            data = json.loads(row["data"]) if row["data"] else {}
        except (json.JSONDecodeError, TypeError):
            data = {}

        event_timestamp = row["timestamp"] or ""
        logged_by = (row["logged_by"] or "").strip()

        if isinstance(data, dict) and "staff_name" in data:
            staff_name = data.pop("staff_name")
            if isinstance(staff_name, str) and staff_name.strip():
                staff_name = staff_name.strip()
                conn.execute(
                    """INSERT INTO event_history
                       (event_id, action_type, actor, field_name, old_value, new_value, timestamp)
                       VALUES (?, 'create', ?, 'staff_name', NULL, ?, ?)""",
                    (row["id"], staff_name, staff_name, event_timestamp),
                )

            if not logged_by:
                logged_by = staff_name.strip() if isinstance(staff_name, str) else ""
                if logged_by:
                    conn.execute(
                        "UPDATE events SET logged_by = ? WHERE id = ?",
                        (logged_by, row["id"]),
                    )

        conn.execute(
            "UPDATE events SET data = ? WHERE id = ?",
            (json.dumps(data), row["id"]),
        )
