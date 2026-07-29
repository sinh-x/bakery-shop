"""Migration v084: _migrate_v84_order_item_assigned_price (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v84_order_item_assigned_price(conn):
    """Add nullable ``assigned_price`` column to ``order_items`` (DG-296 Phase 1).

    The column stores the assigned price (base_price or selected price chip
    price) at time of sale for trưng bày products, so COGS can be anchored on
    it independently from ``unit_price`` (the marked-up selling price). It is
    nullable (DEFAULT NULL): existing rows are unaffected and readers treat
    NULL as equal to ``unit_price`` for backward compatibility (FR8).
    Idempotent via PRAGMA-guarded ``_guard_add_column`` (``order_items`` is in
    ALLOWED_TABLES). Traceability: FR6, FR8.
    """
    _guard_add_column(
        conn,
        "order_items",
        "assigned_price",
        "assigned_price REAL DEFAULT NULL",
    )
