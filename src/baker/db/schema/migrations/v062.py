"""Migration v062: _migrate_v62_negative_balance (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v62_negative_balance(conn):
    """Create negative_balance table for tracking oversold stock (DG-200 Phase 1).

    Idempotent: uses CREATE TABLE IF NOT EXISTS and CREATE INDEX IF NOT EXISTS,
    so re-running on an already-migrated DB is a no-op.
    """
    conn.executescript(NEGATIVE_BALANCE_SCHEMA)
