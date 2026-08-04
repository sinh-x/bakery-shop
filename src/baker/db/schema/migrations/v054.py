"""Migration v054: _migrate_v54_add_account_2400 (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v54_add_account_2400(conn):
    """Ensure account 2400 (Tien Rut Held) exists in chart of accounts.

    DG-199 Phase 4.2. This calls the existing _seed_chart_of_accounts() which
    uses INSERT OR IGNORE for every account, so re-running v54 on an
    already-migrated DB is a no-op (idempotent by design).
    """
    _seed_chart_of_accounts(conn)
