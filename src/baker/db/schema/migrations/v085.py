"""Migration v085: _migrate_v85_add_account_1600 (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v85_add_account_1600(conn):
    """Ensure account 1600 (Tài sản cố định / Fixed Assets) exists (DG-300 Phase 1).

    Mirrors ``_migrate_v54_add_account_2400`` and ``_migrate_v73_add_account_2500``:
    calls the existing ``_seed_chart_of_accounts()`` which uses
    ``INSERT OR IGNORE`` for every account, so re-running v85 on an
    already-migrated DB is a no-op (idempotent by design). The 1600 row was
    added to ``SEED_CHART_OF_ACCOUNTS`` as part of this phase.
    """
    _seed_chart_of_accounts(conn)
