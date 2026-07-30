"""Migration v053: _migrate_v53_payment_transaction_invalidation (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v53_payment_transaction_invalidation(conn):
    """Add soft-delete (invalidation) columns to ``payment_transactions``.

    Mirrors the v43 events soft-delete pattern (``deleted_at``/``deleted_by``):
    invalidation is a soft-delete that preserves the row for audit while
    excluding it from payment totals, completion guards, and journal listings.

    Adds ``invalidated_at TEXT`` (NULL = valid) and ``invalidated_by TEXT
    DEFAULT ''`` plus an index on ``invalidated_at`` for fast filtering of
    valid (non-NULL) rows.

    Idempotent: re-running on an already-migrated DB is a no-op because
    ``_guard_add_column`` checks ``PRAGMA table_info`` before altering and
    ``CREATE INDEX IF NOT EXISTS`` skips existing indexes.
    """
    _guard_add_column(conn, "payment_transactions", "invalidated_at", "invalidated_at TEXT")
    _guard_add_column(
        conn, "payment_transactions", "invalidated_by", "invalidated_by TEXT DEFAULT ''"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_payment_transactions_invalidated_at "
        "ON payment_transactions(invalidated_at)"
    )
