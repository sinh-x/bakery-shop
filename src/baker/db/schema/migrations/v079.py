"""Migration v079: _migrate_v79_add_staff_name_to_orders (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v79_add_staff_name_to_orders(conn):
    """Add created_staff_name and work_ticket_printed_staff_name to orders table (DG-259 Cycle 5).

    Idempotent via PRAGMA-guarded ALTER TABLE (orders is in ALLOWED_TABLES).
    """
    _guard_add_column(conn, "orders", "created_staff_name", "created_staff_name TEXT DEFAULT ''")
    _guard_add_column(conn, "orders", "work_ticket_printed_staff_name", "work_ticket_printed_staff_name TEXT DEFAULT ''")
