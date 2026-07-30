"""Migration v073: _migrate_v73_add_account_2500 (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v73_add_account_2500(conn):
    """Ensure account 2500 (Phải trả người bán / Accounts Payable) exists in chart of accounts.

    DG-245 Phase 2 (migration v73). This mirrors ``_migrate_v54_add_account_2400``:
    it calls the existing ``_seed_chart_of_accounts()`` which uses
    ``INSERT OR IGNORE`` for every account, so re-running v73 on an
    already-migrated DB is a no-op (idempotent by design).
    """
    _seed_chart_of_accounts(conn)
