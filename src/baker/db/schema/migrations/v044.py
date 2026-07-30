"""Migration v044: _migrate_v44_double_entry_accounting (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v44_double_entry_accounting(conn):
    """Create accounting schema, seed chart of accounts, and backfill journal
    entries for historical expenses, payment_transactions, and delivered orders."""
    conn.executescript(ACCOUNTING_SCHEMA)
    _seed_chart_of_accounts(conn)
    _backfill_expense_journal_entries(conn)
    _backfill_payment_transaction_journal_entries(conn)
    _backfill_delivered_order_journal_entries(conn)
