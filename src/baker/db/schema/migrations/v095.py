"""Migration v095: _migrate_v95_cash_drawer_journal_balance (DG-347 Phase 1).

Refactors the cash drawer balance model so the drawer's expected balance is
derived from 1101 journal lines linked via a new ``cash_drawer_journal_entries``
join table (open drawers) or a persisted ``closing_balance`` (closed drawers),
instead of independent accumulator columns.

Three schema changes, all idempotent (NFR2):

1. Add ``closing_balance`` INTEGER DEFAULT NULL to ``cash_drawer``. The column
   is persisted at close/auto-close time so historical drawer data remains
   accurate even after the accumulator columns are dropped (FR2).

2. Create the ``cash_drawer_journal_entries`` join table with a UNIQUE
   constraint on ``(cash_drawer_id, journal_entry_id)`` (FR3). Both columns
   are INTEGER NOT NULL FK references. Indexes on each FK column support
   per-drawer journal lookups and per-entry drawer lookups.

3. Drop the six accumulator columns from ``cash_drawer`` (FR5):
   ``cash_sales``, ``tien_rut_in``, ``tien_rut_out``, ``owner_in``,
   ``owner_out``, ``cash_expenses``. These are redundant with the 1101 journal
   entries; removing them eliminates the dual-system single-source-of-truth
   problem. Before dropping, ``closing_balance`` is backfilled for all already-
   closed drawers by computing the legacy ``expected_balance()`` formula from
   the accumulator columns — a one-time migration step so historical closed
   drawers continue to report an accurate balance after the columns are gone.

4. Drop the ``cash_drawer_id`` FK column from ``payment_transactions`` and
   ``events`` (FR6). The join table replaces this link.

NFR3: no journal entry creation logic changes in this phase, so all existing
journal entries remain balanced (debit = credit).
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v95_cash_drawer_journal_balance(conn):
    """Refactor cash drawer balance to derive from journal (DG-347 Phase 1).

    Adds ``closing_balance`` to ``cash_drawer``, creates the
    ``cash_drawer_journal_entries`` join table, backfills
    ``closing_balance`` for already-closed drawers from the legacy accumulator
    formula, then drops the accumulator columns and the ``cash_drawer_id`` FK
    from ``payment_transactions`` and ``events``.

    Idempotent (NFR2): ``_guard_add_column`` / ``_guard_drop_column`` skip
    columns that already exist / are already gone, and
    ``CREATE TABLE IF NOT EXISTS`` makes the join-table creation a no-op on
    re-run. The ``closing_balance`` backfill only touches rows where
    ``status = 'closed'`` AND ``closing_balance IS NULL``, so re-running on an
    already-migrated DB is a no-op.
    """
    # 1. Add closing_balance to cash_drawer (FR2).
    _guard_add_column(
        conn,
        "cash_drawer",
        "closing_balance",
        "closing_balance INTEGER DEFAULT NULL",
    )

    # 2. Create the cash_drawer_journal_entries join table (FR3).
    conn.executescript(CASH_DRAWER_JOURNAL_ENTRIES_SCHEMA)

    # 3. Backfill closing_balance for already-closed drawers before dropping
    # the accumulator columns. The legacy expected_balance() formula is
    # opening_balance + cash_sales + tien_rut_in + owner_in
    #   - tien_rut_out - owner_out - cash_expenses.
    # Only rows where status = 'closed' AND closing_balance IS NULL are
    # touched, so this is idempotent on re-run.
    #
    # Fresh-DB guard: on a DB created after this migration shipped, the
    # accumulator columns never existed (the updated CASH_DRAWER_SCHEMA in
    # _constants.py no longer declares them), so the backfill UPDATE would
    # fail with "no such column". Only run the backfill when ``cash_sales``
    # still exists — i.e. on DBs that were migrated through v94 before v95
    # shipped. This keeps the migration idempotent on both fresh and
    # already-migrated DBs (NFR2).
    existing_cols = {
        r[1] for r in conn.execute("PRAGMA table_info(cash_drawer)").fetchall()
    }
    if "cash_sales" in existing_cols:
        conn.execute(
            "UPDATE cash_drawer SET closing_balance = ("
            "  opening_balance + cash_sales + tien_rut_in + owner_in"
            "  - tien_rut_out - owner_out - cash_expenses"
            ") WHERE status = 'closed' AND closing_balance IS NULL"
        )

    # 4. Drop accumulator columns from cash_drawer (FR5).
    for col in (
        "cash_sales",
        "tien_rut_in",
        "tien_rut_out",
        "owner_in",
        "owner_out",
        "cash_expenses",
    ):
        _guard_drop_column(conn, "cash_drawer", col)

    # 5. Drop cash_drawer_id from payment_transactions and events (FR6).
    _guard_drop_column(conn, "payment_transactions", "cash_drawer_id")
    _guard_drop_column(conn, "events", "cash_drawer_id")