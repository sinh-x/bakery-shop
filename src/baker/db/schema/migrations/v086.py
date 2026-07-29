"""Migration v086: _migrate_v86_expense_categories (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v86_expense_categories(conn):
    """Create ``expense_categories`` table and seed the parent + subcategory
    tree (DG-302 Phase 1).

    Also re-runs ``_seed_chart_of_accounts()`` so the new subcategory account
    codes (5110–5140, 5210–5230) are inserted into ``accounts`` — they were
    added to ``SEED_CHART_OF_ACCOUNTS`` as part of this phase. Both operations
    are idempotent (INSERT OR IGNORE / CREATE TABLE IF NOT EXISTS), so re-running
    v86 on an already-migrated DB is a no-op.
    """
    conn.executescript(EXPENSE_CATEGORIES_SCHEMA)
    _seed_chart_of_accounts(conn)
    _seed_expense_categories(conn)
