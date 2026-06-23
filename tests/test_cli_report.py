"""Tests for ``baker report`` CLI group — Phase 4.3 (DG-189, FR5/AC5).

Covers the six report subcommands:

- ``trial-balance``
- ``income-statement``
- ``balance-sheet``
- ``general-ledger``
- ``account-ledger``
- ``expense-by-category``

Each test seeds a small known dataset (one sale, one COGS, one operating
expense) and asserts the expected totals appear in the CLI output. The
clean-DB case (no journal entries) is also covered for each command.
"""

import json

import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


def _insert_entry(
    conn,
    *,
    debit_account_id: int,
    credit_account_id: int,
    amount: float,
    source_type: str = "manual",
    source_id=None,
    description: str = "Test entry",
    created_at: str | None = None,
) -> int:
    """Insert a balanced two-line journal entry."""
    if created_at:
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id, created_at) "
            "VALUES (?, ?, ?, ?)",
            (description, source_type, source_id, created_at),
        )
    else:
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            (description, source_type, source_id),
        )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, debit_account_id, amount, 0.0, "d"),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, credit_account_id, 0.0, amount, "c"),
    )
    return entry_id


def _insert_expense_event(conn, *, category: str, amount: float = 10000,
                          created_at: str | None = None) -> int:
    """Insert an expense event with a category and return its id."""
    data = json.dumps({
        "amount_vnd": amount,
        "category": category,
        "payment_source": "Shop tiền mặt",
    })
    if created_at:
        cur = conn.execute(
            "INSERT INTO events (type, summary, data, timestamp) VALUES (?, ?, ?, ?)",
            ("expense", f"Expense: {category}", data, created_at),
        )
    else:
        cur = conn.execute(
            "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
            ("expense", f"Expense: {category}", data),
        )
    return int(cur.lastrowid)


def _seed_known_dataset(conn):
    """Seed a known dataset used across report tests.

    Layout (all dated 2026-06-15):
      - Sale:           DR 1100 (Cash) 200000  / CR 4100 (Revenue) 200000
      - COGS:           DR 5900 (COGS) 80000   / CR 1300 (Inventory) 80000
      - Operating exp:  DR 5300 (Vận chuyển) 10000 / CR 1100 (Cash) 10000
                        (source_type='expense', source_id=expense event id,
                         event category = 'Vận chuyển')

    Expected report values:
      - trial balance totals: debit = credit = 290000
      - income statement: revenue 200000, COGS 80000, opex 10000, net 110000
      - expense-by-category: 'Vận chuyển' = 10000
    """
    cash = _account_id(conn, "1100")
    revenue = _account_id(conn, "4100")
    cogs = _account_id(conn, "5900")
    inventory = _account_id(conn, "1300")
    transport = _account_id(conn, "5300")
    ts = "2026-06-15T10:00:00"

    _insert_entry(
        conn,
        debit_account_id=cash,
        credit_account_id=revenue,
        amount=200000.0,
        source_type="order",
        source_id=1,
        description="Sale order #1",
        created_at=ts,
    )
    _insert_entry(
        conn,
        debit_account_id=cogs,
        credit_account_id=inventory,
        amount=80000.0,
        source_type="order_cogs",
        source_id=1,
        description="COGS for order #1",
        created_at=ts,
    )
    event_id = _insert_expense_event(conn, category="Vận chuyển", amount=10000, created_at=ts)
    _insert_entry(
        conn,
        debit_account_id=transport,
        credit_account_id=cash,
        amount=10000.0,
        source_type="expense",
        source_id=event_id,
        description="Expense: Vận chuyển",
        created_at=ts,
    )


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


# ---------------------------------------------------------------------------
# trial-balance
# ---------------------------------------------------------------------------


def test_trial_balance_known_totals():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke(["report", "trial-balance", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Trial Balance" in result.output
    # Cash (1100) debit = 200000, credit = 10000 → debit column 200000, credit column 10000
    assert "1100" in result.output
    assert "200,000.00" in result.output
    assert "10,000.00" in result.output
    # Totals: debit = credit = 290000
    assert "290,000.00" in result.output


def test_trial_balance_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "trial-balance", "--since", "2026-01-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    # Empty range message OR zero totals; accounts still listed with zero balances.
    assert "Trial Balance" in result.output


def test_trial_balance_date_filter_excludes_out_of_range():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    # Range outside the seeded 2026-06-15 entries.
    result = _invoke(["report", "trial-balance", "--since", "2026-07-01", "--until", "2026-07-31"])
    assert result.exit_code == 0, result.output
    # No journal entries fall in July → empty-range message.
    assert "no journal entries in range" in result.output


# ---------------------------------------------------------------------------
# income-statement
# ---------------------------------------------------------------------------


def test_income_statement_known_totals():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke(["report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Income Statement" in result.output
    assert "Revenue" in result.output
    assert "200,000.00" in result.output
    assert "Cost of Goods Sold" in result.output
    assert "80,000.00" in result.output
    assert "Gross Profit" in result.output
    assert "120,000.00" in result.output
    assert "Operating Expenses" in result.output
    assert "10,000.00" in result.output
    assert "Net Income" in result.output
    assert "110,000.00" in result.output


def test_income_statement_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Net Income" in result.output
    assert "0.00" in result.output


# ---------------------------------------------------------------------------
# balance-sheet
# ---------------------------------------------------------------------------


def test_balance_sheet_known_totals():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke(["report", "balance-sheet", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Balance Sheet" in result.output
    assert "Assets" in result.output
    assert "Liabilities" in result.output
    assert "Equity" in result.output
    # Cash 1100 balance = 200000 - 10000 = 190000 (debit - credit)
    assert "190,000.00" in result.output
    # Inventory 1300 balance = 0 - 80000 = -80000
    assert "80,000.00" in result.output
    # Total Assets = 190000 - 80000 = 110000
    assert "110,000.00" in result.output


def test_balance_sheet_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "balance-sheet", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Balance Sheet" in result.output
    assert "Total Assets" in result.output


# ---------------------------------------------------------------------------
# general-ledger
# ---------------------------------------------------------------------------


def test_general_ledger_known_entries():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke(["report", "general-ledger", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "General Ledger" in result.output
    assert "Sale order #1" in result.output
    assert "COGS for order #1" in result.output
    assert "Expense: Vận chuyển" in result.output
    # Lines: DR / CR markers
    assert "DR" in result.output
    assert "CR" in result.output
    # Account codes appear in line output
    assert "1100" in result.output
    assert "4100" in result.output
    assert "5900" in result.output


def test_general_ledger_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "general-ledger", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "no journal entries in range" in result.output


# ---------------------------------------------------------------------------
# account-ledger
# ---------------------------------------------------------------------------


def test_account_ledger_requires_account_code():
    result = _invoke(["report", "account-ledger", "--since", "2026-06-01", "--until", "2026-06-30"])
    # Missing required option → non-zero exit (UsageError).
    assert result.exit_code != 0


def test_account_ledger_unknown_code_errors():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "account-ledger", "--account-code", "9999"])
    assert result.exit_code != 0


def test_account_ledger_known_history():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke([
        "report", "account-ledger", "--account-code", "1100",
        "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Account Ledger" in result.output
    assert "1100" in result.output
    assert "Tiền mặt" in result.output
    # Cash received 200000 (DR) then paid out 10000 (CR) → running balances
    assert "200,000.00" in result.output
    assert "190,000.00" in result.output


def test_account_ledger_empty_for_unused_account():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    # Account 2100 (Customer Deposits) is never touched in the seed dataset.
    result = _invoke([
        "report", "account-ledger", "--account-code", "2100",
        "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "no journal lines for this account" in result.output


# ---------------------------------------------------------------------------
# expense-by-category
# ---------------------------------------------------------------------------


def test_expense_by_category_known_totals():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke([
        "report", "expense-by-category", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Expense by Category" in result.output
    assert "Vận chuyển" in result.output
    assert "10,000.00" in result.output
    assert "TOTAL" in result.output


def test_expense_by_category_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke([
        "report", "expense-by-category", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "no expense journal entries in range" in result.output


# ---------------------------------------------------------------------------
# Group registration sanity
# ---------------------------------------------------------------------------


def test_report_group_registered():
    result = _invoke(["report", "--help"])
    assert result.exit_code == 0, result.output
    assert "trial-balance" in result.output
    assert "income-statement" in result.output
    assert "balance-sheet" in result.output
    assert "general-ledger" in result.output
    assert "account-ledger" in result.output
    assert "expense-by-category" in result.output


# ---------------------------------------------------------------------------
# date format validation (DG-189 Phase 5.6-c1, CQ-3)
# ---------------------------------------------------------------------------


def test_trial_balance_rejects_invalid_since_date():
    """Non-date ``--since`` values must exit non-zero with a clear message."""
    result = _invoke(
        ["report", "trial-balance", "--since", "invalid-date", "--until", "2026-06-30"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output


def test_trial_balance_rejects_invalid_until_date():
    """Non-date ``--until`` values must exit non-zero with a clear message."""
    result = _invoke(
        ["report", "trial-balance", "--since", "2026-06-01", "--until", "30/06/2026"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output


def test_account_ledger_rejects_invalid_date():
    """Date validation applies to all report commands with --since/--until."""
    result = _invoke(
        ["report", "account-ledger", "--account-code", "1100", "--since", "not-a-date"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output