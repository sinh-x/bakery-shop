"""Migration v092: _migrate_v92_cash_drawer_sub_accounts (DG-330 Phase 2)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v92_cash_drawer_sub_accounts(conn):
    """Insert cash drawer sub-accounts 1101/1102 and transfer the existing 1100
    balance to 1101 via a one-time balanced journal entry (DG-330 Phase 2, FR9).

    Two sub-accounts are added under 1100 (Cash on Hand):

      * 1101 — Tiền mặt tại quầy (Cash in Drawer) — all cash touching the POS
      * 1102 — Tiền mặt chủ sở hữu (Owner's Cash) — cash the owner holds personally

    The rows were added to ``SEED_CHART_OF_ACCOUNTS`` in Phase 1; this migration
    materializes them on existing databases via ``_seed_chart_of_accounts()``,
    which uses ``INSERT OR IGNORE`` for every account (idempotent — re-running
    on an already-migrated DB is a no-op for the account rows).

    Balance transfer (FR9): the current 1100 balance is moved to 1101 via a
    single balanced journal entry (DR 1101, CR 1100). The transfer is guarded
    two ways to keep the migration idempotent (NFR1):

      1. Skip when the 1100 balance is <= 0 — nothing to transfer (also covers
         the fresh-DB case where 1100 has never been touched).
      2. Skip when a ``migration_balance_transfer`` journal entry with
         ``source_id = 92`` already exists — the one-time transfer has already
         run, so re-running the migration must not duplicate it.

    All journal entries remain balanced (NFR2): the transfer uses
    ``_insert_journal_entry``, which enforces ``total_debit == total_credit``
    and raises on violation.
    """
    # 1. Idempotently seed 1101 and 1102 (INSERT OR IGNORE via _seed_chart_of_accounts).
    _seed_chart_of_accounts(conn)

    # 2. Guard: skip the balance transfer if it has already been recorded.
    existing_transfer = conn.execute(
        "SELECT 1 FROM journal_entries "
        "WHERE source_type = 'migration_balance_transfer' AND source_id = 92"
    ).fetchone()
    if existing_transfer:
        return

    # 3. Compute the current 1100 balance (asset account: debit - credit).
    balance_row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) AS balance
        FROM accounts a
        LEFT JOIN journal_lines jl ON jl.account_id = a.id
        WHERE a.code = '1100'
        GROUP BY a.id
        """
    ).fetchone()
    balance = float(balance_row["balance"]) if balance_row is not None else 0.0

    # 4. Only transfer a positive balance (zero/negative means nothing to move;
    #    this also covers the fresh-DB case where 1100 has no journal lines).
    if balance <= 0:
        return

    # 5. Insert the balanced transfer entry: DR 1101, CR 1100.
    cash_drawer_id = _account_id_by_code(conn, "1101")
    cash_on_hand_id = _account_id_by_code(conn, "1100")
    _insert_journal_entry(
        conn,
        description="Migration v092: transfer 1100 balance to 1101 (cash drawer sub-accounts)",
        source_type="migration_balance_transfer",
        source_id=92,
        lines=[
            (cash_drawer_id, balance, 0.0, "Tiền mặt tại quầy — nhận từ 1100"),
            (cash_on_hand_id, 0.0, balance, "Tiền mặt tại quầy — chuyển từ 1100"),
        ],
    )