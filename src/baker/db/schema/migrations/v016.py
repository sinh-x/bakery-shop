"""Migration v016: _migrate_v16_staff_and_created_by (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v16_staff_and_created_by(conn):
    """Seed 5 staff members and add created_by column to orders."""
    for name, role in SEED_STAFF:
        conn.execute(
            "INSERT OR IGNORE INTO staff (name, role) VALUES (?, ?)",
            (name, role),
        )
    conn.execute(
        "ALTER TABLE orders ADD COLUMN created_by TEXT DEFAULT ''"
    )
