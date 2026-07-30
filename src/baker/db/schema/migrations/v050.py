"""Migration v050: _migrate_v50_journal_transaction_date (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v50_journal_transaction_date(conn):
    """Add the ``transaction_date`` column to ``journal_entries`` and create an
    index on it.

    The column records the business event date an entry relates to (distinct
    from the audit-only ``created_at`` INSERT timestamp). Existing rows get
    ``transaction_date = ''`` here; migration v51 backfills them from their
    source record dates. The default empty string keeps the column ``NOT NULL``
    while allowing a deferred backfill, and the index supports the report/API/
    lock queries that switch onto ``transaction_date`` in later phases.

    Idempotent: uses ``_guard_add_column`` so re-running on an already-migrated
    DB is a no-op, and ``CREATE INDEX IF NOT EXISTS`` guards the index.
    """
    _guard_add_column(
        conn,
        "journal_entries",
        "transaction_date",
        "transaction_date TEXT NOT NULL DEFAULT ''",
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_journal_entries_transaction_date "
        "ON journal_entries(transaction_date)"
    )
