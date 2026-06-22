"""Tests for accounting — Phase 1 stub.

Phase 1 (DG-175) covers schema, chart of accounts seed, and backfill only.
Full API tests are added in Phase 2 once the accounts router is registered.
These tests verify the accounting foundation is in place and queryable via
the Account / JournalEntry models so Phase 2 can build on a known-good base.
"""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.account import Account
from baker.models.journal_entry import JournalEntry


def test_accounts_seeded_after_migrate():
    with get_db() as conn:
        ensure_schema(conn)
        accounts = Account.list_all(conn)
        assert len(accounts) >= 21
        codes = {a.code for a in accounts}
        # Core required accounts per AC8
        for required in (
            "1100",  # Cash on Hand
            "1200",  # Bank Account
            "1300",  # Inventory
            "1400",  # Staff Advances (parent)
            "2100",  # Customer Deposits
            "3100",  # Owner's Equity
            "4100",  # Order Revenue
            "5900",  # COGS
            "5100",  # Ingredients expense
            "5800",  # Other Expenses
        ):
            assert required in codes, f"Required account {required} missing"


def test_journal_balances_empty_on_fresh_db():
    with get_db() as conn:
        ensure_schema(conn)
        balances = JournalEntry.get_balances(conn)
        assert len(balances) >= 21
        for b in balances:
            assert b["balance"] == 0