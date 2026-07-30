"""Migration v035: _migrate_v35_reconciliation_line_waste_reason (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v35_reconciliation_line_waste_reason(conn):
    """Repair DBs that created reconciliation_lines before per-line waste reasons."""
    _guard_add_column(
        conn,
        "reconciliation_lines",
        "waste_reason",
        "waste_reason TEXT DEFAULT ''",
    )
