"""Migration v076: _migrate_v76_add_transaction_bank_sub_accounts (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v76_add_transaction_bank_sub_accounts(conn):
    """Ensure bank sub-accounts 1210/1220/1290 exist (DG-244 Phase 4).

    Adds three sub-accounts under 1200 (Tài khoản ngân hàng) so payment
    transactions can be routed to distinct bank accounts:

      * 1210 — TK Phượng VCB (Bank — Phượng)
      * 1220 — TK Ân VCB (Bank — Ân)
      * 1290 — TK ngân hàng chưa phân bổ (Un-allocated Bank)

    Idempotent via ``_seed_chart_of_accounts()`` which uses ``INSERT OR IGNORE``
    for every account. Re-running on an already-migrated DB is a no-op.

    The historical backfill (Phase 5) will reassign existing transfer journal
    entries from 1200 to 1290 in a separate migration; this migration only
    ensures the accounts exist so live routing can target them.
    """
    _seed_chart_of_accounts(conn)
    _guard_add_column(
        conn, "payment_transactions", "payment_source", "payment_source TEXT DEFAULT ''"
    )
