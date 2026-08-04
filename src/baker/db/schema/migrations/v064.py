"""Migration v064: _migrate_v64_delivery_phone (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v64_delivery_phone(conn):
    """Add delivery_phone column to orders table — DG-211 Phase 4.1."""
    cols = [row[1] for row in conn.execute("PRAGMA table_info(orders)").fetchall()]
    if "delivery_phone" not in cols:
        conn.execute("ALTER TABLE orders ADD COLUMN delivery_phone TEXT DEFAULT ''")
