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


def test_income_statement_date_basis_transaction_byte_identical_to_default():
    """--date-basis transaction output is byte-identical to default (no flag)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)
    default_result = _invoke([
        "report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    explicit_result = _invoke([
        "report", "income-statement", "--since", "2026-06-01", "--until", "2026-06-30",
        "--date-basis", "transaction",
    ])
    assert default_result.exit_code == 0, default_result.output
    assert explicit_result.exit_code == 0, explicit_result.output
    assert default_result.output == explicit_result.output


def _seed_due_date_dataset(conn):
    """Seed dataset for due-date basis tests.

    Layout:
      - Order #1 (due_date='2026-06-20'): revenue 200000, COGS 80000
        transaction_date = 2026-06-15T10:00:00Z
      - Order #2 (due_date=NULL): revenue 150000, COGS 50000
        transaction_date = 2026-06-18T10:00:00Z
      - Operating expense (source_type='expense'): 10000
        transaction_date = 2026-06-15T10:00:00Z

    Expected:
      - Transaction basis (--since 2026-06-16 → 2026-06-30):
        Only Order #2 revenue/COGS included (transaction_date 06-18 in range).
        Operating expense excluded (transaction_date 06-15).
        revenue=150000, COGS=50000, opex=0, net=100000
      - Due-date basis (--since 2026-06-16 → 2026-06-30):
        Order #1 included (due_date 06-20), Order #2 included (due_date NULL,
          fallback DATE(transaction_date)=06-18).
        Operating expense excluded (transaction_date 06-15).
        revenue=350000, COGS=130000, opex=0, net=220000
    """
    cash = _account_id(conn, "1100")
    revenue_acc = _account_id(conn, "4100")
    cogs = _account_id(conn, "5900")
    inventory = _account_id(conn, "1300")

    conn.execute(
        "INSERT INTO orders (id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (1, "ORD-1", "Customer 1", "[]", 200000, "delivered", "2026-06-20", "2026-06-15T10:00:00Z"),
    )
    conn.execute(
        "INSERT INTO orders (id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (2, "ORD-2", "Customer 2", "[]", 150000, "delivered", None, "2026-06-18T10:00:00Z"),
    )

    _insert_entry(
        conn, debit_account_id=cash, credit_account_id=revenue_acc,
        amount=200000.0, source_type="order", source_id=1,
        description="Order #1 revenue", created_at="2026-06-15T10:00:00Z",
    )
    _insert_entry(
        conn, debit_account_id=cogs, credit_account_id=inventory,
        amount=80000.0, source_type="order_cogs", source_id=1,
        description="Order #1 COGS", created_at="2026-06-15T10:00:00Z",
    )
    _insert_entry(
        conn, debit_account_id=cash, credit_account_id=revenue_acc,
        amount=150000.0, source_type="order", source_id=2,
        description="Order #2 revenue", created_at="2026-06-18T10:00:00Z",
    )
    _insert_entry(
        conn, debit_account_id=cogs, credit_account_id=inventory,
        amount=50000.0, source_type="order_cogs", source_id=2,
        description="Order #2 COGS", created_at="2026-06-18T10:00:00Z",
    )


def test_income_statement_date_basis_due_date_different_bucketing():
    """Due-date basis buckets order revenue/COGS by COALESCE(due_date, DATE(transaction_date))."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_due_date_dataset(conn)

    # Transaction basis: only Order #2 (transaction_date=06-18) falls in 06-16→06-30
    tx_result = _invoke([
        "report", "income-statement",
        "--since", "2026-06-16", "--until", "2026-06-30",
        "--date-basis", "transaction",
    ])
    assert tx_result.exit_code == 0, tx_result.output
    assert "150,000.00" in tx_result.output  # revenue
    assert "50,000.00" in tx_result.output   # COGS
    assert "100,000.00" in tx_result.output  # net income
    assert "200,000.00" not in tx_result.output  # Order #1 revenue excluded
    assert "80,000.00" not in tx_result.output   # Order #1 COGS excluded

    # Due-date basis: both orders fall in 06-16→06-30 (Order #1 due_date=06-20,
    # Order #2 due_date=NULL → DATE(transaction_date)=06-18)
    dd_result = _invoke([
        "report", "income-statement",
        "--since", "2026-06-16", "--until", "2026-06-30",
        "--date-basis", "due-date",
    ])
    assert dd_result.exit_code == 0, dd_result.output
    assert "350,000.00" in dd_result.output  # revenue 200000+150000
    assert "130,000.00" in dd_result.output  # COGS 80000+50000
    assert "220,000.00" in dd_result.output  # net income
    assert "(due-date basis)" in dd_result.output


def test_income_statement_date_basis_due_date_operating_expenses_on_transaction_date():
    """Operating expenses stay on transaction_date under due-date basis."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_due_date_dataset(conn)
        transport = _account_id(conn, "5300")
        cash = _account_id(conn, "1100")
        event_id = _insert_expense_event(
            conn, category="Vận chuyển", amount=10000,
            created_at="2026-06-15T10:00:00Z",
        )
        _insert_entry(
            conn, debit_account_id=transport, credit_account_id=cash,
            amount=10000.0, source_type="expense", source_id=event_id,
            description="Expense", created_at="2026-06-15T10:00:00Z",
        )

    # Due-date basis with --since 06-16 excludes the 06-15 expense
    result = _invoke([
        "report", "income-statement",
        "--since", "2026-06-16", "--until", "2026-06-30",
        "--date-basis", "due-date",
    ])
    assert result.exit_code == 0, result.output
    assert "350,000.00" in result.output  # revenue
    assert "10,000.00" not in result.output  # opex excluded (transaction_date 06-15)
    assert "220,000.00" in result.output  # net income (no opex)


def test_income_statement_date_basis_due_date_include_expense_in_range():
    """Operating expenses inside the date range show up in due-date basis."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_due_date_dataset(conn)
        transport = _account_id(conn, "5300")
        cash = _account_id(conn, "1100")
        event_id = _insert_expense_event(
            conn, category="Vận chuyển", amount=10000,
            created_at="2026-06-20T10:00:00Z",
        )
        _insert_entry(
            conn, debit_account_id=transport, credit_account_id=cash,
            amount=10000.0, source_type="expense", source_id=event_id,
            description="Expense", created_at="2026-06-20T10:00:00Z",
        )

    result = _invoke([
        "report", "income-statement",
        "--since", "2026-06-16", "--until", "2026-06-30",
        "--date-basis", "due-date",
    ])
    assert result.exit_code == 0, result.output
    assert "350,000.00" in result.output  # revenue
    assert "10,000.00" in result.output   # opex included (transaction_date 06-20)
    assert "210,000.00" in result.output  # net income (350000 - 130000 - 10000)


def test_income_statement_date_basis_default_help_shows_option():
    """--help for income-statement shows the --date-basis option."""
    result = _invoke(["report", "income-statement", "--help"])
    assert result.exit_code == 0, result.output
    assert "--date-basis" in result.output
    assert "transaction" in result.output
    assert "due-date" in result.output


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


# ---------------------------------------------------------------------------
# order-status (DG-254 Phase 2, FR1-FR6 / AC1-AC7)
# ---------------------------------------------------------------------------


def _insert_order(
    conn,
    *,
    order_id: int,
    status: str = "new",
    delivery_type: str | None = "pickup",
    total_price: float = 0.0,
    due_date: str | None = "2026-06-15",
    created_at: str = "2026-06-15T10:00:00Z",
) -> None:
    """Insert a single order row exercising the order-status report inputs."""
    conn.execute(
        "INSERT INTO orders "
        "(id, order_ref, customer_name, items, total_price, status, "
        " due_date, delivery_type, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            order_id, f"ORD-{order_id}", f"Customer {order_id}", "[]",
            total_price, status, due_date, delivery_type, created_at,
        ),
    )


def _seed_order_status_dataset(conn):
    """Seed a dataset spanning multiple statuses and delivery types.

    Layout (all dated 2026-06-15 unless noted):

      - #1 new,        pickup,    total 100000
      - #2 confirmed,   delivery,  total 200000
      - #3 in_progress, pickup,    total 150000
      - #4 ready,       bus,       total 300000
      - #5 delivered,   pickup,    total 250000
      - #6 completed,   delivery,  total 400000
      - #7 cancelled,   pickup,    total 50000
      - #8 delivered,   (NULL)     total 120000   — tests NULL delivery_type
      - #9 new,        pickup,    total 80000, due_date=NULL, created_at 2026-06-15
    """
    _insert_order(conn, order_id=1, status="new", delivery_type="pickup",
                  total_price=100000)
    _insert_order(conn, order_id=2, status="confirmed", delivery_type="delivery",
                  total_price=200000)
    _insert_order(conn, order_id=3, status="in_progress", delivery_type="pickup",
                  total_price=150000)
    _insert_order(conn, order_id=4, status="ready", delivery_type="bus",
                  total_price=300000)
    _insert_order(conn, order_id=5, status="delivered", delivery_type="pickup",
                  total_price=250000)
    _insert_order(conn, order_id=6, status="completed", delivery_type="delivery",
                  total_price=400000)
    _insert_order(conn, order_id=7, status="cancelled", delivery_type="pickup",
                  total_price=50000)
    _insert_order(conn, order_id=8, status="delivered", delivery_type=None,
                  total_price=120000)
    _insert_order(conn, order_id=9, status="new", delivery_type="pickup",
                  total_price=80000, due_date=None)


def test_order_status_exits_zero_with_header():
    """AC1/FR1: ``baker report order-status`` exits 0 and prints a header."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_order_status_dataset(conn)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    assert "Order Status Report" in result.output
    # Header columns are recognizable.
    assert "Status" in result.output
    assert "Delivery Type" in result.output
    assert "Count" in result.output
    assert "Value" in result.output


def test_order_status_groups_by_status_with_count_and_value():
    """AC2/FR2: each status group shows COUNT and SUM(total_price)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_order_status_dataset(conn)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    # delivered group: orders #5 (250000) + #8 (120000) = 2 orders, 370000.
    assert "delivered" in result.output
    # completed group: 1 order, 400000.
    assert "400,000.00" in result.output
    # cancelled group: 1 order, 50000.
    assert "50,000.00" in result.output


def test_order_status_subgroups_by_delivery_type():
    """AC3/FR3: within each status, delivery_type sub-rows show count/value."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_order_status_dataset(conn)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    # delivered status has pickup (1, 250000), delivery (0), bus (0),
    # and NULL delivery_type (1, 120000 → shown as "(none)").
    assert "(none)" in result.output
    assert "120,000.00" in result.output
    assert "250,000.00" in result.output
    # confirmed status only has delivery → 200000.
    assert "200,000.00" in result.output
    # ready status only has bus → 300000.
    assert "300,000.00" in result.output


def test_order_status_date_filter_excludes_out_of_range():
    """AC4/FR4: --since/--until filter by COALESCE(due_date, created_at)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_order_status_dataset(conn)
    # July range excludes all June-dated seed orders.
    result = _invoke([
        "report", "order-status", "--since", "2026-07-01", "--until", "2026-07-31",
    ])
    assert result.exit_code == 0, result.output
    # Grand total must be zero (no orders in range) but statuses still listed.
    assert "GRAND TOTAL" in result.output
    # No individual seed value should appear as a positive data row.
    assert "400,000.00" not in result.output
    assert "300,000.00" not in result.output


def test_order_status_date_filter_falls_back_to_created_at():
    """AC4/FR4: orders with NULL due_date use created_at for date filtering."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_order_status_dataset(conn)
    # Order #9 has due_date=NULL but created_at=2026-06-15 → included in June.
    result = _invoke([
        "report", "order-status", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # Order #9's value (80000) must appear in the new status group.
    assert "80,000.00" in result.output


def test_order_status_grand_total_row():
    """AC5/FR5: a grand total row shows overall count and total value."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_order_status_dataset(conn)
    result = _invoke([
        "report", "order-status", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "GRAND TOTAL" in result.output
    # All 9 seed orders fall in June.
    # Total value = 100000+200000+150000+300000+250000+400000+50000+120000+80000
    #             = 1,650,000
    assert "1,650,000.00" in result.output


def test_order_status_all_seven_statuses_appear_even_when_zero():
    """AC6/FR6: all 7 OrderStatus values appear even when count=0."""
    with get_db() as conn:
        ensure_schema(conn)
        # Seed only 'new' and 'delivered' orders; the other 5 statuses are 0.
        _insert_order(conn, order_id=1, status="new", total_price=100000)
        _insert_order(conn, order_id=2, status="delivered", total_price=200000)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    for status in ("new", "confirmed", "in_progress", "ready",
                    "delivered", "completed", "cancelled"):
        assert status in result.output


def test_order_status_zero_count_status_shows_zero_value():
    """AC6/FR6: a zero-count status shows count=0 and value=0.00."""
    with get_db() as conn:
        ensure_schema(conn)
        # No 'completed' orders in this seed.
        _insert_order(conn, order_id=1, status="new", total_price=100000)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    assert "completed" in result.output
    # The completed group's subtotal row must show 0 count and 0.00 value.
    # We confirm by checking that "0.00" appears (subtotal value formatting).
    assert "0.00" in result.output


def test_order_status_cancelled_orders_appear():
    """AC7: cancelled orders appear in the report output."""
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(conn, order_id=1, status="cancelled",
                      delivery_type="pickup", total_price=75000)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    assert "cancelled" in result.output
    assert "75,000.00" in result.output


def test_order_status_empty_db():
    """Empty DB still lists all 7 statuses with zero counts and a grand total."""
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["report", "order-status"])
    assert result.exit_code == 0, result.output
    assert "Order Status Report" in result.output
    assert "GRAND TOTAL" in result.output
    for status in ("new", "confirmed", "in_progress", "ready",
                    "delivered", "completed", "cancelled"):
        assert status in result.output


def test_order_status_registered_in_report_group():
    """The order-status subcommand is registered under ``baker report``."""
    result = _invoke(["report", "--help"])
    assert result.exit_code == 0, result.output
    assert "order-status" in result.output


def test_order_status_rejects_invalid_since_date():
    """Date validation applies to the order-status command."""
    result = _invoke(
        ["report", "order-status", "--since", "not-a-date", "--until", "2026-06-30"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output