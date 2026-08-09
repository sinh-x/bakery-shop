"""Migration v099: _migrate_v99_cash_drawer_reconciled_column (DG-379 Phase 4.1).

Adds the ``reconciled`` INTEGER NOT NULL DEFAULT 0 column to the
``cash_drawer`` table. The column locks a drawer from further transaction
edits once it has been finalized/reconciled (FR7). The PATCH
``/api/cash-drawer/{id}/reconcile`` endpoint that flips the flag to 1 is
built in Phase 4.2 — this migration only provides the schema prerequisite
(FR8 / AC6 partial).

Backward compatible (NFR3): the column defaults to ``0`` (editable), so
existing drawers remain editable after the migration runs. Existing rows
pick up the default value because SQLite ``ALTER TABLE ... ADD COLUMN``
with a constant DEFAULT back-fills the default for all existing rows.

Idempotent: ``cash_drawer`` is in ``ALLOWED_TABLES``, so the migration
uses the shared ``_guard_add_column`` helper which skips the ALTER when
the column already exists (re-running v099 on an already-migrated DB is
a no-op). A covering index on ``reconciled`` is created alongside the
column to support the 409 guard lookup in Phase 4.2.
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v99_cash_drawer_reconciled_column(conn):
    """Add ``reconciled INTEGER NOT NULL DEFAULT 0`` to ``cash_drawer``.

    Idempotent via ``_guard_add_column`` (PRAGMA-guarded ALTER). The covering
    index ``idx_cash_drawer_reconciled`` is created with ``CREATE INDEX IF
    NOT EXISTS`` so re-running the migration is a no-op for the index as well.
    """
    _guard_add_column(
        conn,
        "cash_drawer",
        "reconciled",
        "reconciled INTEGER NOT NULL DEFAULT 0",
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_cash_drawer_reconciled ON cash_drawer(reconciled)"
    )