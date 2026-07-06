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

import click
import click.testing
import pytest

from baker.cli import app
from baker.commands.report import _normalize_date
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
    transaction_date: str | None = None,
) -> int:
    """Insert a balanced two-line journal entry."""
    # transaction_date defaults to created_at when not provided (mirrors
    # _insert_journal_entry's behavior of falling back to current time).
    td = transaction_date or created_at
    if created_at or td:
        cur = conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, created_at, transaction_date) "
            "VALUES (?, ?, ?, ?, ?)",
            (description, source_type, source_id, created_at, td),
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


def _seed_cogs_audit_dataset(conn):
    """Seed four delivered orders exercising every cogs-audit status.

    All orders dated 2026-06-15:

      - #1 (ok):         revenue 200000, COGS 60000 → 30% ratio, no zero-cost
      - #2 (missing):     revenue 150000, NO order_cogs journal entry
      - #3 (zero-cost):  revenue 100000, has order_cogs 30000, but one
                         non-extra/non-gift order_item has cost_at_sale = 0
      - #4 (low):         revenue 500000, COGS 25000 → 5% ratio (below 15%)

    Revenue and COGS are written directly via journal_entries/journal_lines
    using ``source_type='order'`` and ``source_type='order_cogs'`` so the
    audit's per-order aggregation finds them.
    """
    cash = _account_id(conn, "1100")
    revenue = _account_id(conn, "4100")
    cogs = _account_id(conn, "5900")
    inventory = _account_id(conn, "1300")
    ts = "2026-06-15T10:00:00Z"

    def _make_order(order_id, total_price=0):
        conn.execute(
            "INSERT INTO orders "
            "(id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (order_id, f"ORD-{order_id}", f"Customer {order_id}", "[]",
             total_price, "delivered", "2026-06-15", ts),
        )

    def _add_order_item(order_id, product_name, qty, unit_price, cost_at_sale,
                        is_extra=0, is_gift=0):
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, "
            " position, status, cost_at_sale, is_extra, is_gift) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (order_id, "", product_name, qty, unit_price, 0, "delivered",
             cost_at_sale, is_extra, is_gift),
        )

    # --- Order #1: ok (revenue 200000, cogs 60000 → 30%) ---
    _make_order(1, total_price=200000)
    _add_order_item(1, "Banh mi", 2, 100000, 30000)
    _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                  amount=200000.0, source_type="order", source_id=1,
                  description="Order revenue: ORD-1", created_at=ts)
    _insert_entry(conn, debit_account_id=cogs, credit_account_id=inventory,
                  amount=60000.0, source_type="order_cogs", source_id=1,
                  description="Order COGS: ORD-1", created_at=ts)

    # --- Order #2: missing (revenue only, no order_cogs entry) ---
    _make_order(2, total_price=150000)
    _add_order_item(2, "Banh mi", 1, 150000, 45000)
    _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                  amount=150000.0, source_type="order", source_id=2,
                  description="Order revenue: ORD-2", created_at=ts)
    # No order_cogs entry → status missing

    # --- Order #3: zero-cost (cogs entry exists, but one item has cost_at_sale=0) ---
    _make_order(3, total_price=100000)
    _add_order_item(3, "Banh mi", 1, 100000, 30000)
    _add_order_item(3, "Banh cuon", 1, 50000, 0)  # zero-cost non-extra/gift item
    _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                  amount=100000.0, source_type="order", source_id=3,
                  description="Order revenue: ORD-3", created_at=ts)
    _insert_entry(conn, debit_account_id=cogs, credit_account_id=inventory,
                  amount=30000.0, source_type="order_cogs", source_id=3,
                  description="Order COGS: ORD-3", created_at=ts)

    # --- Order #4: low (revenue 500000, cogs 25000 → 5%, below 15% threshold) ---
    _make_order(4, total_price=500000)
    _add_order_item(4, "Banh mi", 1, 500000, 25000)
    _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                  amount=500000.0, source_type="order", source_id=4,
                  description="Order revenue: ORD-4", created_at=ts)
    _insert_entry(conn, debit_account_id=cogs, credit_account_id=inventory,
                  amount=25000.0, source_type="order_cogs", source_id=4,
                  description="Order COGS: ORD-4", created_at=ts)


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
    ts = "2026-06-15T10:00:00Z"

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


def test_income_statement_shows_cogs_ratio_alongside_amount():
    """AC7: COGS line shows the ratio alongside the amount (FR10)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    result = _invoke(["report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    # The COGS line must show the amount AND a parenthesized percentage.
    assert "Cost of Goods Sold (5900)" in result.output
    assert "80,000.00" in result.output
    # Revenue 200000, COGS 80000 → 40.0%
    assert "(40.0%)" in result.output


def test_income_statement_cogs_ratio_zero_revenue_no_division_error():
    """AC7: zero revenue must not crash the ratio display (shows 0.0%)."""
    with get_db() as conn:
        ensure_schema(conn)
        # Seed COGS only — no revenue → revenue == 0
        cogs = _account_id(conn, "5900")
        inventory = _account_id(conn, "1300")
        ts = "2026-06-15T10:00:00Z"
        _insert_entry(
            conn,
            debit_account_id=cogs,
            credit_account_id=inventory,
            amount=50000.0,
            source_type="order_cogs",
            source_id=99,
            description="COGS without revenue",
            created_at=ts,
        )
    result = _invoke(["report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Cost of Goods Sold (5900)" in result.output
    assert "(0.0%)" in result.output


def test_income_statement_cogs_ratio_reflects_selling_price_fix():
    """AC7 regression: after the selling-price fix, ratio reflects actual
    COGS (not the old base_price baseline). Seeds revenue 800000 with COGS
    240000 (30% of 800000 selling price) → 30.0% ratio. The pre-fix formula
    would have produced COGS 45000 (30% of 150000 base_price) → 5.6%."""
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        revenue_acc = _account_id(conn, "4100")
        cogs = _account_id(conn, "5900")
        inventory = _account_id(conn, "1300")
        ts = "2026-06-15T10:00:00Z"
        _insert_entry(
            conn,
            debit_account_id=cash,
            credit_account_id=revenue_acc,
            amount=800000.0,
            source_type="order",
            source_id=7,
            description="Custom-priced sale",
            created_at=ts,
        )
        _insert_entry(
            conn,
            debit_account_id=cogs,
            credit_account_id=inventory,
            amount=240000.0,
            source_type="order_cogs",
            source_id=7,
            description="COGS (selling-price anchored)",
            created_at=ts,
        )
    result = _invoke(["report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "800,000.00" in result.output
    assert "240,000.00" in result.output
    assert "(30.0%)" in result.output


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
# cogs-audit (DG-208 Phase 3, FR4/AC4)
# ---------------------------------------------------------------------------


def test_cogs_audit_flags_all_statuses():
    """The audit table reports one order per status (ok/missing/zero-cost/low)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cogs_audit_dataset(conn)
    result = _invoke([
        "report", "cogs-audit", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "COGS Audit" in result.output
    # Header columns
    assert "Revenue" in result.output
    assert "COGS" in result.output
    assert "Ratio" in result.output
    assert "Status" in result.output
    # One order per status flag
    assert "missing" in result.output
    assert "zero-cost" in result.output
    assert "low" in result.output
    assert "ok" in result.output
    # Summary line lists all four statuses with counts
    assert "ok=1, missing=1, zero-cost=1, low=1" in result.output
    # Total line: revenue 950000, cogs 115000, ratio 12.1%
    assert "950,000.00" in result.output
    assert "115,000.00" in result.output


def test_cogs_audit_excludes_non_delivered_orders():
    """Only delivered/completed orders appear; 'new'/'pending' orders do not."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cogs_audit_dataset(conn)
        # Add a 'new' order with revenue — must not appear in the audit.
        cash = _account_id(conn, "1100")
        revenue = _account_id(conn, "4100")
        cogs = _account_id(conn, "5900")
        inventory = _account_id(conn, "1300")
        ts = "2026-06-15T10:00:00Z"
        conn.execute(
            "INSERT INTO orders "
            "(id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (99, "ORD-99", "Pending customer", "[]", 999999, "new",
             "2026-06-15", ts),
        )
        _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                      amount=999999.0, source_type="order", source_id=99,
                      description="Order revenue: ORD-99", created_at=ts)
        _insert_entry(conn, debit_account_id=cogs, credit_account_id=inventory,
                      amount=999999.0, source_type="order_cogs", source_id=99,
                      description="Order COGS: ORD-99", created_at=ts)
    result = _invoke([
        "report", "cogs-audit", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # The pending order's id must not appear in any data row.
    assert "ORD-99" not in result.output
    assert "ok=1, missing=1, zero-cost=1, low=1" in result.output


def test_cogs_audit_date_filter():
    """Orders outside the --since/--until window are excluded."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cogs_audit_dataset(conn)
    # July range excludes all June-dated seed orders.
    result = _invoke([
        "report", "cogs-audit", "--since", "2026-07-01", "--until", "2026-07-31",
    ])
    assert result.exit_code == 0, result.output
    assert "no delivered/completed orders in range" in result.output


def test_cogs_audit_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "cogs-audit", "--since", "2026-06-01"])
    assert result.exit_code == 0, result.output
    assert "no delivered/completed orders in range" in result.output


def test_cogs_audit_registered_in_report_group():
    result = _invoke(["report", "--help"])
    assert result.exit_code == 0, result.output
    assert "cogs-audit" in result.output


def test_cogs_audit_rejects_invalid_since_date():
    result = _invoke(
        ["report", "cogs-audit", "--since", "not-a-date", "--until", "2026-06-30"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output


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
    assert "cogs-audit" in result.output


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


# ---------------------------------------------------------------------------
# _normalize_date unit tests (DG-189 Phase 5.6-c2, M-2)
# ---------------------------------------------------------------------------


def test_normalize_date_valid_returns_same_string():
    """A valid ``YYYY-MM-DD`` date is returned unchanged without ``end_of_day``."""
    assert _normalize_date("2026-06-30") == "2026-06-30"


def test_normalize_date_invalid_format_raises_bad_parameter():
    """A non-date string raises ``click.BadParameter`` with a helpful message."""
    with pytest.raises(click.BadParameter) as exc_info:
        _normalize_date("30/06/2026")
    assert "YYYY-MM-DD" in str(exc_info.value)


def test_normalize_date_empty_string_returns_none():
    """An empty string is treated as no bound (returns ``None``)."""
    assert _normalize_date("") is None


def test_normalize_date_none_returns_none():
    """A ``None`` date string is treated as no bound (returns ``None``)."""
    assert _normalize_date(None) is None


def test_normalize_date_end_of_day_appends_timestamp():
    """``end_of_day=True`` appends ``T23:59:59`` to an inclusive until bound."""
    assert _normalize_date("2026-06-30", end_of_day=True) == "2026-06-30T23:59:59"


def test_normalize_date_end_of_day_false_returns_plain_date():
    """``end_of_day=False`` (default) returns the bare date string."""
    assert _normalize_date("2026-06-30", end_of_day=False) == "2026-06-30"


def test_normalize_date_partial_invalid_raises_bad_parameter():
    """Partial strings that don't match ``YYYY-MM-DD`` raise ``BadParameter``."""
    for bad in ("20260630", "2026-13-01", "2026-02-31", "abc"):
        with pytest.raises(click.BadParameter):
            _normalize_date(bad)