"""Migration v078: _migrate_v78_add_staff_name_to_events (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v78_add_staff_name_to_events(conn):
    """Add staff_name column to events table (DG-259 Cycle 4).

    Idempotent via PRAGMA-guarded ALTER TABLE (events is in ALLOWED_TABLES).
    """
    _guard_add_column(conn, "events", "staff_name", "staff_name TEXT DEFAULT ''")
