"""Migration v096: _migrate_v96_cash_drawer_counted_opening_balance (DG-354 Phase 1).

Adds the ``counted_opening_balance`` INTEGER column to ``cash_drawer`` so the
user's physical cash count at drawer-open time can be stored separately from
the accounting-derived ``opening_balance`` (which, after Phase 2, will hold
the 1101 accounting balance at open time).

Two schema changes, both idempotent (NFR2):

1. Add ``counted_opening_balance`` INTEGER DEFAULT NULL to ``cash_drawer``.
    Nullable so existing rows — and rows created by code that has not yet been
    updated to pass the physical count — remain valid (FR2). Phase 2 model
    logic will populate it for new drawers; Phase 1 is schema-only.

2. Backfill existing rows with ``counted_opening_balance = opening_balance``.
    Preserves historical data integrity (NFR3): for drawers created before
    this migration, the physical count is assumed to equal the opening
    balance that was recorded at open time. The backfill only touches rows
    where ``counted_opening_balance IS NULL``, so re-running on an
    already-migrated DB is a no-op.

This phase is schema-only — no model, API, or Flutter code is modified. The
``opening_balance`` column semantics do not change yet (Phase 2 updates the
model and API to store the 1101 accounting balance there).
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v96_cash_drawer_counted_opening_balance(conn):
    """Add counted_opening_balance to cash_drawer and backfill existing rows.

    Adds the nullable ``counted_opening_balance`` INTEGER column to
    ``cash_drawer`` (FR2), then backfills every existing row with
    ``counted_opening_balance = opening_balance`` so historical drawer data
    remains intact and consistent (NFR3).

    Idempotent (NFR2): ``_guard_add_column`` skips the ALTER when the column
    already exists, and the backfill UPDATE only touches rows where
    ``counted_opening_balance IS NULL``, so re-running on an already-migrated
    DB is a no-op.
    """
    # 1. Add counted_opening_balance to cash_drawer (FR2).
    _guard_add_column(
        conn,
        "cash_drawer",
        "counted_opening_balance",
        "counted_opening_balance INTEGER DEFAULT NULL",
    )

    # 2. Backfill existing rows so counted_opening_balance = opening_balance
    # (NFR3). Only rows where counted_opening_balance IS NULL are touched,
    # so this is idempotent on re-run.
    conn.execute(
        "UPDATE cash_drawer SET counted_opening_balance = opening_balance "
        "WHERE counted_opening_balance IS NULL"
    )