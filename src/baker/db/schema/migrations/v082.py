"""Migration v082: _migrate_v82_add_blank_id_to_order_items (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v82_add_blank_id_to_order_items(conn):
    """Add nullable ``blank_id`` FK column to ``order_items`` (DG-293 Phase 1).

    The column links a work item (order_items row) to a single blank
    (semi-finished good). Nullable: NULL/empty means no blank assigned
    (FR1). Idempotent via PRAGMA-guarded ALTER TABLE (order_items is in
    ALLOWED_TABLES). An index supports the reverse-lookup
    ``GET /api/blanks/{id}/products`` query.
    """
    _guard_add_column(
        conn,
        "order_items",
        "blank_id",
        "blank_id INTEGER REFERENCES blanks(id)",
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_order_items_blank ON order_items(blank_id)"
    )
