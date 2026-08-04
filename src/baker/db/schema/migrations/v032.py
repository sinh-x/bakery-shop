"""Migration v032: _migrate_v32_print_tracking (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v32_print_tracking(conn):
    """Add print tracking schema with idempotent orders column migration."""
    _guard_add_column(conn, "orders", "work_ticket_printed_by", "work_ticket_printed_by TEXT DEFAULT ''")
