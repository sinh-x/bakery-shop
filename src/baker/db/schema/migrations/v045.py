"""Migration v045: _migrate_v45_cost_history_and_cost_at_sale (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v45_cost_history_and_cost_at_sale(conn):
    """Create cost_history table, add cost_at_sale column to order_items, and
    backfill existing delivered order_items with baseline costs.

    Idempotent: re-running on an already-migrated DB produces no errors and no
    duplicate data. The cost_history table uses CREATE TABLE IF NOT EXISTS; the
    cost_at_sale column is added via _guard_add_column; the backfill UPDATE only
    touches rows whose cost_at_sale is still 0 (NULL treated as 0)."""
    conn.executescript(COST_HISTORY_SCHEMA)
    _guard_add_column(conn, "order_items", "cost_at_sale", "cost_at_sale REAL DEFAULT 0")
    _backfill_order_items_cost_at_sale(conn)
