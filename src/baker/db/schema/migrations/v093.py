"""Migration v093: _migrate_v93_rename_quy_to_quay_in_journal_entries (DG-337 Phase 5).

Renames the legacy Vietnamese term "quỹ" → "quầy" in historical
``journal_entries.description`` rows so that reports and journal screens
display the updated terminology consistently with the code-level string
changes from Phase 1.

The UPDATE is idempotent: running it on an already-migrated DB is a no-op
because the ``WHERE description LIKE '%quỹ%'`` clause matches zero rows once
every description has been rewritten. Re-running on a DB that re-introduced
"quỹ" descriptions (only possible via legacy code paths) would rewrite them
again — this is safe and the intended behaviour.

Per NFR3 the query runs well under 5s on the current dataset (~10K rows):
a single ``UPDATE ... WHERE description LIKE '%quỹ%'`` on the
``journal_entries`` table scans the descriptions once and performs an
in-place ``REPLACE()``; there is no schema lock and no full-table rewrite.
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v93_rename_quy_to_quay_in_journal_entries(conn):
    """Replace "quỹ" with "quầy" in ``journal_entries.description`` (FR7).

    Only rows whose description contains "quỹ" are touched, and each
    occurrence within a description is replaced (not just the first). The
    replacement uses SQLite's built-in ``REPLACE()`` function so it is a
    single-statement, transaction-scoped update.
    """
    conn.execute(
        "UPDATE journal_entries "
        "SET description = REPLACE(description, 'quỹ', 'quầy') "
        "WHERE description LIKE '%quỹ%'"
    )