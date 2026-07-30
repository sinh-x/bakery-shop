"""Migration v065: _migrate_v65_journal_sync_failure_log (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v65_journal_sync_failure_log(conn):
    """Create journal_sync_failure_log table for per-source audit records (DG-226 Phase 1).

    Idempotent: uses CREATE TABLE IF NOT EXISTS and CREATE INDEX IF NOT EXISTS.
    """
    conn.executescript(JOURNAL_SYNC_FAILURE_LOG_SCHEMA)
