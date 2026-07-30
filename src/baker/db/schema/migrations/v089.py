"""Migration v089: _migrate_v89_order_assigned_staff_id (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v89_order_assigned_staff_id(conn):
    """Add ``assigned_staff_id`` column to ``orders`` (DG-310 Phase 3).

    Adds a single nullable TEXT column to ``orders`` that references
    ``staff.id`` (logical FK; SQLite enforces via the application layer
    since ``staff.id`` is INTEGER). Defaults to NULL so existing orders
    remain backward-compatible (NFR4) — the Flutter model treats NULL as
    "unassigned". Single-assignee semantics are enforced by the assign
    endpoint (check-and-set before UPDATE), not by a schema constraint.

    Idempotent via PRAGMA-guarded ``_guard_add_column`` (``orders`` is in
    ALLOWED_TABLES).
    """
    _guard_add_column(
        conn, "orders", "assigned_staff_id", "assigned_staff_id TEXT DEFAULT NULL"
    )