"""Migration v083: _migrate_v83_order_item_blanks (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v83_order_item_blanks(conn):
    """Replace the single ``order_items.blank_id`` FK with the
    ``order_item_blanks`` junction table (DG-294 Phase 1).

    Steps (idempotent, NFR3):

    1. Create the ``order_item_blanks`` table (``CREATE TABLE IF NOT EXISTS``).
    2. Migrate existing ``order_items.blank_id`` values into the new table,
       one row per work item with a non-null ``blank_id``. Re-runs are
       no-ops because of the unique index on ``(order_item_id, blank_id)``
       and the ``INSERT OR IGNORE`` qualifier.
    3. Drop the now-redundant ``blank_id`` column from ``order_items`` via
       the PRAGMA-guarded ``_guard_drop_column`` helper (``order_items`` is
       in ``ALLOWED_TABLES`` and the host SQLite is >= 3.35.0). The
       ``idx_order_items_blank`` index created by v82 is dropped first
       because SQLite refuses to drop a column that an index references.

    The junction table supports multiple blanks per work item (FR7) with
    per-assignment ``quantity`` and ``notes`` (FR8/FR9). The unique index
    prevents duplicate (order_item, blank) pairs and makes the data
    migration idempotent (FR11).
    """
    conn.executescript(ORDER_ITEM_BLANKS_SCHEMA)

    # Migrate existing single blank_id values into the junction table.
    # Only run while the legacy column still exists; on already-migrated DBs
    # the column is gone and this block is skipped (idempotent, NFR3).
    existing = [r[1] for r in conn.execute("PRAGMA table_info(order_items)").fetchall()]
    if "blank_id" in existing:
        rows = conn.execute(
            "SELECT id, blank_id FROM order_items WHERE blank_id IS NOT NULL"
        ).fetchall()
        for row in rows:
            order_item_id = int(row["id"])
            blank_id = int(row["blank_id"])
            conn.execute(
                """INSERT OR IGNORE INTO order_item_blanks
                   (order_item_id, blank_id, quantity, notes, created_at)
                   VALUES (?, ?, 1, '', strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')""",
                (order_item_id, blank_id),
            )
        # Drop the v82 index before dropping the column it references.
        conn.execute("DROP INDEX IF EXISTS idx_order_items_blank")

    _guard_drop_column(conn, "order_items", "blank_id")
