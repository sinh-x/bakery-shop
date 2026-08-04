"""Migration v051: _migrate_v51_backfill_journal_transaction_date (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v51_backfill_journal_transaction_date(conn):
    """Re-backfill existing journal entries with correct ``transaction_date``
    from their source record dates (FR10/AC10).

    Idempotent: only touches entries whose ``transaction_date`` is still empty.
    Runs after v50 (which added the column) so all existing rows are populated.
    """
    _backfill_journal_transaction_date(conn)
