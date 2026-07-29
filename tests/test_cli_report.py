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
                           created_at: str | None = None,
                           subcategory: str | None = None) -> int:
    """Insert an expense event with a category and return its id."""
    payload = {
        "amount_vnd": amount,
        "category": category,
        "payment_source": "Shop tiền mặt",
    }
    if subcategory is not None:
        payload["subcategory"] = subcategory
    data = json.dumps(payload)
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


def _seed_markup_dataset(conn):
    """Seed one delivered order with a trưng bày markup item.

    Order #1 (delivered, 2026-06-15):
      - item: unit_price=250000, assigned_price=200000 → markup 50000
      - item: unit_price=100000, assigned_price=NULL     → no markup (historical)
      - item: unit_price=200000, assigned_price=200000   → no markup (equal)
    """
    cash = _account_id(conn, "1100")
    revenue = _account_id(conn, "4100")
    ts = "2026-06-15T10:00:00Z"
    conn.execute(
        "INSERT INTO orders "
        "(id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (1, "ORD-1", "Khach A", "[]", 550000, "delivered", "2026-06-15", ts),
    )
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift, assigned_price) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (1, "", "Banh trung bay", 1, 250000, 0, "delivered", 60000, 0, 0, 200000),
    )
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift, assigned_price) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (1, "", "Banh lich su", 1, 100000, 1, "delivered", 30000, 0, 0, None),
    )
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift, assigned_price) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (1, "", "Banh khong markup", 1, 200000, 2, "delivered", 60000, 0, 0, 200000),
    )
    _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                  amount=550000.0, source_type="order", source_id=1,
                  description="Order revenue: ORD-1", created_at=ts)


def test_income_statement_shows_markup_line_when_markup_present():
    """DG-296 Phase 5 FR7: income statement shows a Markup line for trưng bày."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_markup_dataset(conn)
    result = _invoke(["report", "income-statement",
                      "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Markup (trung bay)" in result.output
    # Only the 250000/200000 item contributes → 50000
    assert "50,000.00" in result.output


def test_income_statement_omits_markup_line_when_no_markup():
    """No markup items → the Markup line must not appear (clean output)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_known_dataset(conn)  # no order_items with assigned_price markup
    result = _invoke(["report", "income-statement",
                      "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Markup (trung bay)" not in result.output


def test_income_statement_markup_respects_date_filter():
    """Markup outside the date window is excluded."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_markup_dataset(conn)
    # Window in July — the 2026-06-15 order is out of range.
    result = _invoke(["report", "income-statement",
                      "--since", "2026-07-01", "--until", "2026-07-31"])
    assert result.exit_code == 0, result.output
    assert "Markup (trung bay)" not in result.output


def test_income_statement_markup_due_date_basis():
    """DG-296 Phase 5: due-date basis also surfaces the markup line."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_markup_dataset(conn)
    result = _invoke(["report", "income-statement",
                      "--date-basis", "due-date",
                      "--since", "2026-06-01", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Markup (trung bay)" in result.output
    assert "50,000.00" in result.output


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


def test_expense_by_category_subcategory_breakdown():
    """FR3 / AC3: parent categories with subcategories show a breakdown.

    Seeds expenses under Nguyên liệu (Trứng, Kem, Bột, Phụ gia khác) plus a
    legacy Nguyên liệu expense with no subcategory, and a Vận chuyển expense
    (no children). The report must print the Nguyên liệu parent total and a
    sub-breakdown: Trứng, Kem, Bột, Phụ gia khác, and the no-subcategory
    remainder. Vận chuyển has no children → no breakdown block.
    """
    with get_db() as conn:
        ensure_schema(conn)
        ts = "2026-06-15T10:00:00Z"
        cash = _account_id(conn, "1100")

        def _exp(category, subcategory, account_code, amount):
            eid = _insert_expense_event(
                conn, category=category, amount=amount,
                created_at=ts, subcategory=subcategory,
            )
            acc = _account_id(conn, account_code)
            _insert_entry(
                conn, debit_account_id=acc, credit_account_id=cash,
                amount=float(amount), source_type="expense", source_id=eid,
                description=f"Expense: {category}/{subcategory}", created_at=ts,
            )

        # Nguyên liệu subcategories (FR4 account codes)
        _exp("Nguyên liệu", "Trứng", "5110", 50000)
        _exp("Nguyên liệu", "Kem", "5120", 30000)
        _exp("Nguyên liệu", "Bột", "5130", 20000)
        _exp("Nguyên liệu", "Phụ gia khác", "5140", 10000)
        # Legacy Nguyên liệu expense with no subcategory (FR6)
        eid_legacy = _insert_expense_event(
            conn, category="Nguyên liệu", amount=15000, created_at=ts,
        )
        nl = _account_id(conn, "5100")
        _insert_entry(
            conn, debit_account_id=nl, credit_account_id=cash,
            amount=15000.0, source_type="expense", source_id=eid_legacy,
            description="Expense: Nguyên liệu (legacy)", created_at=ts,
        )
        # Vận chuyển — no subcategory breakdown
        transport = _account_id(conn, "5300")
        eid_trans = _insert_expense_event(
            conn, category="Vận chuyển", amount=10000, created_at=ts,
        )
        _insert_entry(
            conn, debit_account_id=transport, credit_account_id=cash,
            amount=10000.0, source_type="expense", source_id=eid_trans,
            description="Expense: Vận chuyển", created_at=ts,
        )

    result = _invoke([
        "report", "expense-by-category", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Expense by Category" in result.output
    # Parent totals
    assert "Nguyên liệu" in result.output
    assert "Vận chuyển" in result.output
    # Subcategory breakdown lines (AC3)
    assert "Trứng" in result.output
    assert "Kem" in result.output
    assert "Bột" in result.output
    assert "Phụ gia khác" in result.output
    # Subcategory amounts
    assert "50,000.00" in result.output
    assert "30,000.00" in result.output
    assert "20,000.00" in result.output
    assert "10,000.00" in result.output
    # Grand total = 50+30+20+10+15+10 = 135000
    assert "135,000.00" in result.output


def test_expense_by_category_subcategory_only_legacy_category_string():
    """FR6: a legacy expense whose category is itself a subcategory name
    (subcategory stored in events.data.category with no subcategory field)
    is normalized back to its parent for the breakdown.
    """
    with get_db() as conn:
        ensure_schema(conn)
        ts = "2026-06-15T10:00:00Z"
        cash = _account_id(conn, "1100")
        eggs = _account_id(conn, "5110")
        eid = _insert_expense_event(
            conn, category="Trứng", amount=40000, created_at=ts,
        )
        _insert_entry(
            conn, debit_account_id=eggs, credit_account_id=cash,
            amount=40000.0, source_type="expense", source_id=eid,
            description="Expense: Trứng (legacy category)", created_at=ts,
        )
    result = _invoke([
        "report", "expense-by-category", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # The parent "Nguyên liệu" row should include the 40000, and the
    # subcategory breakdown should attribute it to Trứng.
    assert "Nguyên liệu" in result.output
    assert "Trứng" in result.output
    assert "40,000.00" in result.output


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


def test_cogs_audit_flags_sold_extra_with_zero_cost_at_sale():
    """FR10: a sold extra (is_extra=1, is_gift=0) with cost_at_sale=0 is
    flagged as zero-cost. Pre-Phase-5 the is_extra=0 filter hid it."""
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        revenue = _account_id(conn, "4100")
        cogs = _account_id(conn, "5900")
        inventory = _account_id(conn, "1300")
        ts = "2026-06-15T10:00:00Z"
        conn.execute(
            "INSERT INTO orders "
            "(id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (10, "ORD-10", "Extras customer", "[]", 100000, "delivered",
             "2026-06-15", ts),
        )
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, "
            " position, status, cost_at_sale, is_extra, is_gift) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (10, "", "Banh mi", 1, 100000, 0, "delivered", 30000, 0, 0),
        )
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, "
            " position, status, cost_at_sale, is_extra, is_gift) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (10, "", "Nen phu kien", 1, 5000, 1, "delivered", 0, 1, 0),
        )
        _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                      amount=100000.0, source_type="order", source_id=10,
                      description="Order revenue: ORD-10", created_at=ts)
        _insert_entry(conn, debit_account_id=cogs, credit_account_id=inventory,
                      amount=30000.0, source_type="order_cogs", source_id=10,
                      description="Order COGS: ORD-10", created_at=ts)
    result = _invoke([
        "report", "cogs-audit", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # ORD-10 should be flagged zero-cost because the sold extra has cost_at_sale=0
    assert "ORD-10" in result.output
    assert "zero-cost" in result.output
    assert "ok=0, missing=0, zero-cost=1, low=0" in result.output


def test_cogs_audit_excludes_gift_items_from_zero_cost_detection():
    """FR10: gift items (is_gift=1) remain excluded from zero-cost detection
    since their cost is recorded by the separate order_gift_cogs entry."""
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        revenue = _account_id(conn, "4100")
        cogs = _account_id(conn, "5900")
        inventory = _account_id(conn, "1300")
        ts = "2026-06-15T10:00:00Z"
        conn.execute(
            "INSERT INTO orders "
            "(id, order_ref, customer_name, items, total_price, status, due_date, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (11, "ORD-11", "Gift customer", "[]", 100000, "delivered",
             "2026-06-15", ts),
        )
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, "
            " position, status, cost_at_sale, is_extra, is_gift) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (11, "", "Banh mi", 1, 100000, 0, "delivered", 30000, 0, 0),
        )
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, "
            " position, status, cost_at_sale, is_extra, is_gift) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (11, "", "Nen qua tang", 1, 5000, 1, "delivered", 0, 0, 1),
        )
        _insert_entry(conn, debit_account_id=cash, credit_account_id=revenue,
                      amount=100000.0, source_type="order", source_id=11,
                      description="Order revenue: ORD-11", created_at=ts)
        _insert_entry(conn, debit_account_id=cogs, credit_account_id=inventory,
                      amount=30000.0, source_type="order_cogs", source_id=11,
                      description="Order COGS: ORD-11", created_at=ts)
    result = _invoke([
        "report", "cogs-audit", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "ORD-11" in result.output
    # Gift item with cost_at_sale=0 must NOT trigger zero-cost (excluded by is_gift=0)
    assert "ok=1, missing=0, zero-cost=0, low=0" in result.output


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


# ---------------------------------------------------------------------------
# cashflow (DG-300 Phase 1)
# ---------------------------------------------------------------------------


def _seed_cashflow_dataset(conn):
    """Seed a known dataset exercising operating, investing, and financing.

    All entries dated 2026-06-15 unless noted. Amounts chosen so each section
    has a distinct, easily-asserted total.

    Layout:
      - Customer payment (operating inflow):
          DR 1100 (Cash) 200000 / CR 2100 (Customer Deposits) 200000
          source_type='payment_transaction'
      - Customer refund (operating outflow):
          DR 2100 50000 / CR 1210 (Phượng VCB) 50000
          source_type='payment_transaction'
      - Expense paid in cash (operating outflow):
          DR 5300 (Vận chuyển) 10000 / CR 1100 10000
          source_type='expense'
      - Owner capital contribution (financing inflow):
          DR 1220 (Ân VCB) 500000 / CR 3100 (Owner's Equity) 500000
          source_type='owner_capital'
      - Owner draw (financing outflow):
          DR 3100 100000 / CR 1100 100000
          source_type='owner_draw'
      - Fixed-asset purchase (investing outflow):
          DR 1600 (Fixed Assets) 300000 / CR 1290 (Un-allocated Bank) 300000
          source_type='manual'
      - Pre-period entry (opens the opening balance):
          DR 1100 100000 / CR 4100 (Order Revenue) 100000
          source_type='order', dated 2026-05-10

    Expected period (June 2026) totals:
      - Operating inflow (customers):   200000 (1100) + 0 (1210) = 200000
      - Operating outflow (customers):   50000 (1210 refund)
      - Operating outflow (suppliers):   10000 (1100 expense)
      - Investing outflow:               300000 (1290)
      - Financing inflow:                500000 (1220)
      - Financing outflow:               100000 (1100)
      - Net cash flow = (200000 + 500000) - (50000 + 10000 + 300000 + 100000)
                      = 700000 - 460000 = 240000
      - Opening cash (before 2026-06-01): 100000 (1100)
      - Closing cash (≤ 2026-06-30):
          1100: 100000 + 200000 - 10000 - 100000 = 190000
          1210: -50000
          1220: 500000
          1290: -300000
          total = 190000 - 50000 + 500000 - 300000 = 340000
      - closing - opening = 340000 - 100000 = 240000  ✓ reconciles
    """
    cash = _account_id(conn, "1100")
    phuong = _account_id(conn, "1210")
    an = _account_id(conn, "1220")
    unalloc = _account_id(conn, "1290")
    deposits = _account_id(conn, "2100")
    transport = _account_id(conn, "5300")
    equity = _account_id(conn, "3100")
    revenue = _account_id(conn, "4100")
    fixed_assets = _account_id(conn, "1600")
    ts = "2026-06-15T10:00:00Z"
    pre_ts = "2026-05-10T10:00:00Z"

    # Pre-period entry establishing the opening balance.
    _insert_entry(
        conn, debit_account_id=cash, credit_account_id=revenue,
        amount=100000.0, source_type="order", source_id=99,
        description="Pre-period sale", created_at=pre_ts, transaction_date=pre_ts,
    )

    # Operating: customer payment (inflow) and refund (outflow).
    _insert_entry(
        conn, debit_account_id=cash, credit_account_id=deposits,
        amount=200000.0, source_type="payment_transaction", source_id=1,
        description="Customer deposit", created_at=ts, transaction_date=ts,
    )
    _insert_entry(
        conn, debit_account_id=deposits, credit_account_id=phuong,
        amount=50000.0, source_type="payment_transaction", source_id=2,
        description="Customer refund", created_at=ts, transaction_date=ts,
    )

    # Operating: expense paid in cash (outflow).
    event_id = _insert_expense_event(
        conn, category="Vận chuyển", amount=10000, created_at=ts,
    )
    _insert_entry(
        conn, debit_account_id=transport, credit_account_id=cash,
        amount=10000.0, source_type="expense", source_id=event_id,
        description="Expense: Vận chuyển", created_at=ts, transaction_date=ts,
    )

    # Financing: owner capital contribution (inflow) and draw (outflow).
    _insert_entry(
        conn, debit_account_id=an, credit_account_id=equity,
        amount=500000.0, source_type="owner_capital", source_id=None,
        description="Owner capital contribution", created_at=ts, transaction_date=ts,
    )
    _insert_entry(
        conn, debit_account_id=equity, credit_account_id=cash,
        amount=100000.0, source_type="owner_draw", source_id=None,
        description="Owner draw", created_at=ts, transaction_date=ts,
    )

    # Investing: fixed-asset purchase (outflow on cash side).
    _insert_entry(
        conn, debit_account_id=fixed_assets, credit_account_id=unalloc,
        amount=300000.0, source_type="manual", source_id=None,
        description="Fixed-asset purchase", created_at=ts, transaction_date=ts,
    )


def test_cashflow_exits_zero_and_prints_header():
    """AC1: command exits 0 and prints a structured cashflow report."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Cashflow Statement (Direct Method)" in result.output
    assert "Period: 2026-06-01 → 2026-06-30" in result.output


def test_cashflow_operating_subsections_present():
    """AC2: operating section shows customers and suppliers/employees sub-sections."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Operating Activities" in result.output
    assert "Cash from customers" in result.output
    assert "Cash paid to suppliers/employees" in result.output
    assert "Net operating cashflow" in result.output
    # Customer inflow 200000 on 1100; refund outflow 50000 on 1210.
    assert "200,000.00" in result.output
    assert "50,000.00" in result.output
    # Supplier/employee outflow 10000 on 1100.
    assert "10,000.00" in result.output


def test_cashflow_financing_section_shows_capital_and_draw():
    """AC3: financing section shows owner_capital inflow and owner_draw outflow."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Financing Activities" in result.output
    assert "Net financing cashflow" in result.output
    # Owner capital contribution 500000 on 1220.
    assert "500,000.00" in result.output
    # Owner draw 100000 on 1100 (already asserted elsewhere, but ensure present).
    assert "100,000.00" in result.output


def test_cashflow_investing_section_shows_fixed_asset_flow():
    """AC4: investing section shows cash flow on account 1600."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Investing Activities" in result.output
    assert "Net investing cashflow" in result.output
    # Fixed-asset purchase: 300000 outflow on 1290.
    assert "300,000.00" in result.output


def test_cashflow_date_filter_excludes_out_of_range():
    """AC7: --since/--until restricts period activity to entries within the period."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    # July range excludes all June-dated seed entries from period activity.
    result = _invoke([
        "report", "cashflow", "--since", "2026-07-01", "--until", "2026-07-31",
    ])
    assert result.exit_code == 0, result.output
    # No activity in any section.
    assert result.output.count("(no activity)") >= 3
    # Reconciliation should still be OK (0 net cash flow = 0 change).
    assert "[OK]" in result.output
    # Period activity totals are zero.
    assert "Net cash flow                                           0.00" in result.output
    # Opening and closing balances are equal (no period movement) — both
    # include all pre-July entries (the May sale + all June activity).
    assert "Opening cash balance                              340,000.00" in result.output
    assert "Closing cash balance                              340,000.00" in result.output


def test_cashflow_reconciliation_ok():
    """AC8/FR7: net cash flow reconciles with closing - opening within tolerance."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Reconciliation (closing - opening)" in result.output
    assert "[OK]" in result.output
    # Net cash flow = 240000 (see _seed_cashflow_dataset docstring).
    assert "240,000.00" in result.output


def test_cashflow_empty_db():
    """Empty DB still prints a complete report with zero totals and OK reconciliation."""
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Cashflow Statement (Direct Method)" in result.output
    assert result.output.count("(no activity)") >= 3
    assert "[OK]" in result.output


def test_cashflow_account_1600_seeded():
    """The v85 migration seeds account 1600 in the chart of accounts."""
    with get_db() as conn:
        ensure_schema(conn)
        row = conn.execute(
            "SELECT code, name, type FROM accounts WHERE code = '1600'"
        ).fetchone()
    assert row is not None
    assert row["code"] == "1600"
    assert row["type"] == "asset"
    assert "Tài sản cố định" in row["name"]


def test_cashflow_registered_in_report_group():
    """The cashflow subcommand is registered under ``baker report``."""
    result = _invoke(["report", "--help"])
    assert result.exit_code == 0, result.output
    assert "cashflow" in result.output


def test_cashflow_rejects_invalid_since_date():
    """Date validation applies to the cashflow command."""
    result = _invoke(
        ["report", "cashflow", "--since", "not-a-date", "--until", "2026-06-30"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output


# ---------------------------------------------------------------------------
# cashflow Phase 2 — per-account breakdown and balance reconciliation (DG-300)
# ---------------------------------------------------------------------------


def test_cashflow_per_account_breakdown_section_present():
    """AC6/FR6: a standalone per-account breakdown table is printed."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Per-Account Breakdown" in result.output
    # Every cash account code appears in the breakdown.
    for code in ("1100", "1200", "1210", "1220", "1290"):
        assert code in result.output


def test_cashflow_per_account_breakdown_values():
    """AC6/FR6: per-account inflows, outflows, and net change are correct."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    output = result.output
    # From _seed_cashflow_dataset, expected per-account period activity:
    #   1100: inflow 200000 (customer) - outflow 10000 (expense) + 100000 (owner_draw)
    #         => inflows 200000, outflows 110000, net 90000
    #   1210: outflow 50000 (refund) => inflows 0, outflows 50000, net -50000
    #   1220: inflow 500000 (owner_capital) => inflows 500000, outflows 0, net 500000
    #   1290: outflow 300000 (investing) => inflows 0, outflows 300000, net -300000
    #   1200: no activity
    # Locate the Per-Account Breakdown block and verify the per-account rows.
    breakdown_idx = output.index("Per-Account Breakdown")
    breakdown = output[breakdown_idx:]
    # 1100 row: inflows 200000, outflows 110000, net 90000.
    assert "1100" in breakdown
    assert "200,000.00" in breakdown
    assert "110,000.00" in breakdown
    assert "90,000.00" in breakdown
    # 1210 row: outflows 50000, net -50000.
    assert "50,000.00" in breakdown
    # 1220 row: inflows 500000.
    assert "500,000.00" in breakdown
    # 1290 row: outflows 300000, net -300000.
    assert "300,000.00" in breakdown


def test_cashflow_per_account_breakdown_totals_row():
    """AC6/AC8: the breakdown TOTAL row matches the reconciliation totals."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # The TOTAL row net change (700000 - 460000 = 240000) equals the net cash
    # flow asserted by test_cashflow_reconciliation_ok.
    assert "TOTAL" in result.output
    # Net change 240000 appears in the breakdown totals.
    assert "240,000.00" in result.output
    # Opening total 100000 and closing total 340000.
    assert "100,000.00" in result.output
    assert "340,000.00" in result.output


def test_cashflow_opening_closing_balance_correct():
    """AC5/FR5: opening and closing balances are computed correctly.

    From _seed_cashflow_dataset:
      - Opening (before 2026-06-01): 100000 on 1100 (pre-period sale).
      - Closing (≤ 2026-06-30):
          1100: 100000 + 200000 - 10000 - 100000 = 190000
          1210: -50000
          1220: 500000
          1290: -300000
          total = 340000
    closing - opening = 240000, which equals net cash flow.
    """
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Opening cash balance" in result.output
    assert "Closing cash balance" in result.output
    # Opening 100000 (pre-period sale on 1100); closing 340000.
    assert "100,000.00" in result.output
    assert "340,000.00" in result.output


def test_cashflow_reconciliation_closing_equals_opening_plus_net():
    """AC5: closing = opening + net cash flow (within tolerance)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # closing - opening = 240000 = net cash flow → reconciliation OK.
    assert "Reconciliation (closing - opening)" in result.output
    assert "[OK]" in result.output
    assert "240,000.00" in result.output


def test_cashflow_per_account_breakdown_empty_db():
    """AC6: the per-account breakdown table renders on an empty DB with zeros."""
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    assert "Per-Account Breakdown" in result.output
    # All five cash account codes appear even with no activity.
    for code in ("1100", "1200", "1210", "1220", "1290"):
        assert code in result.output
    # TOTAL row is present.
    assert "TOTAL" in result.output


# ---------------------------------------------------------------------------
# cashflow Phase 3 — edge cases and polish (DG-300)
# ---------------------------------------------------------------------------


def test_cashflow_missing_since_and_until_all_time():
    """Edge case #2: no --since/--until computes the all-time range.

    With no date filters, the report should still exit 0, show the
    'All time' period label, and print a complete report. The
    reconciliation may report [MISMATCH] when unclassified cash-affecting
    entries (e.g. ``source_type='order'`` direct cash sales, which FR2
    excludes to avoid double-counting with ``payment_transaction``) fall
    inside the all-time period — that is accurate reporting, not a crash.
    """
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke(["report", "cashflow"])
    assert result.exit_code == 0, result.output
    assert "Period: All time" in result.output
    assert "Opening cash balance" in result.output
    assert "Closing cash balance" in result.output
    # Opening is 0 (all-time starts at the beginning); closing reflects
    # every cash entry ever recorded.
    assert "Reconciliation (closing - opening)" in result.output


def test_cashflow_missing_until_only():
    """Edge case #2b: only --since given → 'since <date>' period label."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke(["report", "cashflow", "--since", "2026-06-01"])
    assert result.exit_code == 0, result.output
    assert "Period: since 2026-06-01" in result.output
    assert "[OK]" in result.output


def test_cashflow_missing_since_only():
    """Edge case #2c: only --until given → 'until <date>' period label.

    Like the all-time case, omitting --since means the period starts at
    the beginning of time, so unclassified cash-affecting entries (the
    pre-period ``order`` sale) fall inside the period and the
    reconciliation may report [MISMATCH] — that is accurate, not a crash.
    """
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke(["report", "cashflow", "--until", "2026-06-30"])
    assert result.exit_code == 0, result.output
    assert "Period: until 2026-06-30" in result.output
    assert "Reconciliation (closing - opening)" in result.output


def test_cashflow_rejects_invalid_until_date():
    """Edge case #3: invalid --until format is rejected (not a crash)."""
    result = _invoke(
        ["report", "cashflow", "--since", "2026-06-01", "--until", "31-06-2026"]
    )
    assert result.exit_code != 0, result.output
    assert "YYYY-MM-DD" in result.output


def test_cashflow_rejects_inverted_range():
    """Edge case #6: --since later than --until is rejected with a clear error."""
    result = _invoke(
        ["report", "cashflow", "--since", "2026-06-30", "--until", "2026-06-01"]
    )
    assert result.exit_code != 0, result.output
    assert "must not be later than" in result.output


def test_cashflow_same_day_range_allowed():
    """Edge case #6b: same-day --since/--until is valid (not inverted)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-15", "--until", "2026-06-15",
    ])
    assert result.exit_code == 0, result.output
    assert "[OK]" in result.output


def test_cashflow_no_cash_activity_but_other_entries_exist():
    """Edge case #4: non-cash journal entries present → report shows zero cashflow.

    Seed a journal entry that touches only non-cash accounts (2100 customer
    deposits ↔ 2500 accounts payable). The cashflow report should show
    '(no activity)' in every section, zero net cash flow, and [OK]
    reconciliation with opening == closing.
    """
    with get_db() as conn:
        ensure_schema(conn)
        deposits = _account_id(conn, "2100")
        ap = _account_id(conn, "2500")
        ts = "2026-06-15T10:00:00Z"
        _insert_entry(
            conn, debit_account_id=deposits, credit_account_id=ap,
            amount=75000.0, source_type="manual", source_id=None,
            description="Non-cash accrual", created_at=ts, transaction_date=ts,
        )
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # No cash account activity in any section.
    assert result.output.count("(no activity)") >= 3
    # Net cash flow is zero (no cash movement).
    assert "Net cash flow" in result.output
    assert "0.00" in result.output
    # Opening == closing (both 0 — no cash movement ever).
    assert "Opening cash balance" in result.output
    assert "Closing cash balance" in result.output
    assert "[OK]" in result.output


def test_cashflow_empty_range_shows_zeroes_and_no_activity():
    """Edge case #1: a date range with no journal entries shows zeroes, not a crash.

    A range entirely before any seeded entry (Jan 2026) should produce a
    complete report with zero totals, '(no activity)' in every section,
    and [OK] reconciliation.
    """
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-01-01", "--until", "2026-01-31",
    ])
    assert result.exit_code == 0, result.output
    assert result.output.count("(no activity)") >= 3
    assert "Net cash flow" in result.output
    # Opening balance is 0 (no entries before 2026-01-01).
    assert "Opening cash balance" in result.output
    assert "Closing cash balance" in result.output
    assert "[OK]" in result.output


def test_cashflow_output_is_plain_text_no_ansi():
    """NFR1: report output contains no ANSI escape codes."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_cashflow_dataset(conn)
    result = _invoke([
        "report", "cashflow", "--since", "2026-06-01", "--until", "2026-06-30",
    ])
    assert result.exit_code == 0, result.output
    # Click's CliRunner strips styling by default; assert no raw escape
    # sequences leaked into the captured output.
    assert "\x1b[" not in result.output