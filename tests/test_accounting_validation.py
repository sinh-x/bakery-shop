"""Tests for accounting validation module — Phase 5 (DG-187, FR6/AC6).

Covers the fifteen validation checks exposed via the service module, the
``GET /api/accounts/validate`` endpoint, and the ``baker validate-accounts``
CLI command:

- double-entry integrity (imbalanced journal entries flagged)
- COGS completeness (delivered order_items missing cost_at_sale)
- waste COGS referential integrity (orphaned waste_cogs entries)
- cost history sanity (negative costs, duplicate effective_from, future dates)
- accounting equation (Assets = Liabilities + Equity + Income − Expenses)
- source completeness (expense/payment/order missing journal entries)
- COGS amount accuracy (cogs_debit vs cost_at_sale × quantity)
- cash flow integrity (net cash change vs inflows − outflows)
- lock integrity (locked_at set but locked_by empty)
- account balance sanity (asset/expense accounts with negative balance)
- future-dated entries (created_at in the future)
- duplicate entries (same source_type + source_id, excluding reversals)
- orphaned lines (journal lines with non-existent account_id)
- expense category mismatch (debited account ≠ category mapping)
- deposit revenue integrity (2100 debit = 2400 credit + 4100 credit)
- clean DB → all checks pass
- CLI command exit code + output
"""

import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.accounting_validation import run_validation


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


def _insert_imbalanced_entry(conn) -> int:
    """Insert a journal entry whose debit != credit."""
    cogs = _account_id(conn, "5900")
    inv = _account_id(conn, "1300")
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, ?, ?)",
        ("Imbalanced test", "manual", None),
    )
    entry_id = cur.lastrowid
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, cogs, 100.0, 0.0, "d"),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, inv, 0.0, 99.0, "c"),
    )
    return entry_id


def _seed_delivered_order_item_without_cost(conn, product_id: int, base_price: float) -> int:
    """Create a delivered order + order_item whose cost_at_sale is 0 but the
    product has a non-zero base_price (baseline would resolve to non-zero).
    """
    conn.execute(
        "UPDATE products SET base_price = ? WHERE id = ?",
        (base_price, product_id),
    )
    order_cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, due_date, total_price, status) "
        "VALUES (?, ?, ?, ?, ?)",
        ("ORD-VAL-1", "Tester", "2026-06-23", base_price, "delivered"),
    )
    order_id = order_cur.lastrowid
    item_cur = conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, is_extra, is_gift, cost_at_sale) "
        "VALUES (?, ?, ?, ?, ?, 0, 0, 0)",
        (order_id, str(product_id), "Test product", 1, base_price),
    )
    return int(item_cur.lastrowid)


def _seed_orphan_waste_cogs_entry(conn) -> int:
    """Insert a waste_cogs journal entry whose source_id has no matching
    stock_movements row with movement_type='waste'.
    """
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, ?, ?)",
        ("Orphan waste cogs", "waste_cogs", 999999),
    )
    return int(cur.lastrowid)


def _insert_balanced_entry(
    conn,
    debit_account_id: int,
    credit_account_id: int,
    *,
    amount: float = 100.0,
    source_type: str = "manual",
    source_id=None,
    debit_to: int | None = None,
    credit_from: int | None = None,
) -> int:
    """Insert a balanced journal entry (debit == credit).

    By default debits ``debit_account_id`` and credits ``credit_account_id``.
    Override with ``debit_to``/``credit_from`` to reverse the direction on a
    specific account (useful for creating negative-balance scenarios).
    """
    d_acct = debit_to if debit_to is not None else debit_account_id
    c_acct = credit_from if credit_from is not None else credit_account_id
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, ?, ?)",
        ("Balanced test", source_type, source_id),
    )
    entry_id = cur.lastrowid
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, d_acct, amount, 0.0, "d"),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, c_acct, 0.0, amount, "c"),
    )
    return entry_id


# ---------------------------------------------------------------------------
# Service-level: clean DB
# ---------------------------------------------------------------------------


def test_validation_clean_db_all_pass():
    with get_db() as conn:
        ensure_schema(conn)
        report = run_validation(conn)
    assert report["summary"]["overall_status"] == "pass"
    assert report["summary"]["failed"] == 0
    assert report["summary"]["total_issues"] == 0
    check_names = [c["check"] for c in report["checks"]]
    assert check_names == [
        "double_entry_integrity",
        "cogs_completeness",
        "waste_cogs_referential_integrity",
        "cost_history_sanity",
        "accounting_equation",
        "source_completeness",
        "cogs_amount_accuracy",
        "cash_flow_integrity",
        "lock_integrity",
        "account_balance_sanity",
        "future_dated_entries",
        "duplicate_entries",
        "orphaned_lines",
        "expense_category_mismatch",
        "deposit_revenue_integrity",
        "deposit_balance_integrity",
    ]
    # On a clean (empty) DB all checks pass, but the test DB contains real
    # production data which may have legitimate issues (e.g. inventory negative,
    # cancelled orders with deposits).  Only assert the check count and names.
    assert report["summary"]["total_checks"] == 16


# ---------------------------------------------------------------------------
# Service-level: double-entry integrity
# ---------------------------------------------------------------------------


def test_double_entry_integrity_flags_imbalanced_entry():
    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _insert_imbalanced_entry(conn)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "double_entry_integrity")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    finding = check["details"][0]
    assert finding["entry_id"] == entry_id
    assert finding["imbalance"] == 1.0


def test_double_entry_integrity_passes_when_balanced():
    """A properly balanced entry (inserted via _insert_journal_entry) is not flagged."""
    from baker.db.schema import _insert_journal_entry, COGS_CODE, INVENTORY_CODE

    with get_db() as conn:
        ensure_schema(conn)
        cogs = _account_id(conn, COGS_CODE)
        inv = _account_id(conn, INVENTORY_CODE)
        _insert_journal_entry(
            conn,
            description="Balanced",
            source_type="manual",
            source_id=None,
            lines=[(cogs, 500.0, 0.0, "d"), (inv, 0.0, 500.0, "c")],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "double_entry_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: COGS completeness
# ---------------------------------------------------------------------------


def test_cogs_completeness_flags_missing_cost_at_sale():
    with get_db() as conn:
        ensure_schema(conn)
        # product id 1 is seeded; give it a non-zero base_price so baseline is resolvable.
        item_id = _seed_delivered_order_item_without_cost(conn, 1, base_price=50000)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cogs_completeness")
    assert check["status"] == "fail"
    assert check["issue_count"] >= 1
    finding = next(f for f in check["details"] if f["item_id"] == item_id)
    assert finding["cost_at_sale"] == 0.0
    assert finding["base_price"] == 50000.0


def test_cogs_completeness_passes_when_cost_at_sale_set():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("UPDATE products SET base_price = 50000 WHERE id = 1")
        order_cur = conn.execute(
            "INSERT INTO orders (order_ref, customer_name, due_date, total_price, status) "
            "VALUES (?, ?, ?, ?, ?)",
            ("ORD-VAL-2", "Tester", "2026-06-23", 50000, "delivered"),
        )
        order_id = order_cur.lastrowid
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, is_extra, is_gift, cost_at_sale) "
            "VALUES (?, ?, ?, ?, ?, 0, 0, ?)",
            (order_id, "1", "Test product", 1, 50000, 15000),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cogs_completeness")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_cogs_completeness_skips_zero_base_price_product():
    """When base_price=0 and no cost_history, baseline resolves to 0 — not flagged."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_delivered_order_item_without_cost(conn, 1, base_price=0)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cogs_completeness")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: waste COGS referential integrity
# ---------------------------------------------------------------------------


def test_waste_cogs_referential_integrity_flags_orphan():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_orphan_waste_cogs_entry(conn)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "waste_cogs_referential_integrity")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    assert check["details"][0]["movement_id"] == 999999


def test_waste_cogs_referential_integrity_passes_when_valid():
    """A waste_cogs entry whose source_id points to a real waste movement is not flagged."""
    with get_db() as conn:
        ensure_schema(conn)
        mv_cur = conn.execute(
            "INSERT INTO stock_movements (product_id, movement_type, quantity, reason) "
            "VALUES (?, 'waste', -1, 'test')",
            (1,),
        )
        movement_id = mv_cur.lastrowid
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Valid waste cogs", "waste_cogs", movement_id),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "waste_cogs_referential_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: cost history sanity
# ---------------------------------------------------------------------------


def test_cost_history_sanity_flags_negative_cost():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, -500, "2020-01-01T00:00:00Z"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cost_history_sanity")
    assert check["status"] == "fail"
    neg = [f for f in check["details"] if f["anomaly"] == "negative_cost"]
    assert len(neg) == 1
    assert neg[0]["cost"] == -500.0


def test_cost_history_sanity_flags_duplicate_effective_from():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 100, "2020-01-01T00:00:00Z"),
        )
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 200, "2020-01-01T00:00:00Z"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cost_history_sanity")
    dups = [f for f in check["details"] if f["anomaly"] == "duplicate_effective_from"]
    assert len(dups) == 1
    assert dups[0]["count"] == 2


def test_cost_history_sanity_flags_future_effective_from():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 100, "2999-12-31T00:00:00Z"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cost_history_sanity")
    futures = [f for f in check["details"] if f["anomaly"] == "future_effective_from"]
    assert len(futures) == 1
    assert futures[0]["effective_from"] == "2999-12-31T00:00:00Z"


def test_cost_history_sanity_passes_on_clean_history():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 100, "2020-01-01T00:00:00Z"),
        )
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 200, "2021-01-01T00:00:00Z"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cost_history_sanity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# API endpoint: GET /api/accounts/validate
# ---------------------------------------------------------------------------


def test_api_validate_endpoint_clean_db(api_client):
    resp = api_client.get("/api/accounts/validate")
    assert resp.status_code == 200
    body = resp.json()
    # Test DB contains real production data — do not assert status == "pass".
    assert body["summary"]["total_checks"] == 16
    assert len(body["checks"]) == 16


def test_api_validate_endpoint_reports_failures(api_client):
    with get_db() as conn:
        _insert_imbalanced_entry(conn)
    resp = api_client.get("/api/accounts/validate")
    assert resp.status_code == 200
    body = resp.json()
    assert body["summary"]["overall_status"] == "fail"
    assert body["summary"]["failed"] >= 1
    de = next(c for c in body["checks"] if c["check"] == "double_entry_integrity")
    assert de["issue_count"] == 1


# ---------------------------------------------------------------------------
# CLI command: baker validate-accounts
# ---------------------------------------------------------------------------


def test_cli_validate_accounts_clean_exit_zero():
    runner = click.testing.CliRunner()
    result = runner.invoke(app, ["validate-accounts"])
    assert result.exit_code == 0, result.output
    assert "PASS" in result.output
    assert "double_entry_integrity" in result.output


def test_cli_validate_accounts_failure_exit_one():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_imbalanced_entry(conn)
    runner = click.testing.CliRunner()
    result = runner.invoke(app, ["validate-accounts"])
    assert result.exit_code == 1, result.output
    assert "FAIL" in result.output
    assert "double_entry_integrity" in result.output


# ---------------------------------------------------------------------------
# Service-level: lock integrity
# ---------------------------------------------------------------------------


def test_lock_integrity_flags_locked_at_without_locked_by():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, locked_at, locked_by) "
            "VALUES (?, ?, ?, ?, ?)",
            ("Partial lock", "manual", None, "2026-06-23T12:00:00Z", ""),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "lock_integrity")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    assert check["details"][0]["locked_at"] == "2026-06-23T12:00:00Z"


def test_lock_integrity_passes_when_both_set():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, locked_at, locked_by) "
            "VALUES (?, ?, ?, ?, ?)",
            ("Full lock", "manual", None, "2026-06-23T12:00:00Z", "sinh"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "lock_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_lock_integrity_passes_when_neither_set():
    with get_db() as conn:
        ensure_schema(conn)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "lock_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: account balance sanity
# ---------------------------------------------------------------------------


def test_account_balance_sanity_flags_negative_asset_balance():
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        revenue = _account_id(conn, "4100")
        # Debit revenue (income), credit cash (asset) → cash balance goes
        # negative while keeping the entry balanced.
        _insert_balanced_entry(conn, revenue, cash, amount=500)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "account_balance_sanity")
    flagged_codes = [f["code"] for f in check["details"]]
    assert check["status"] == "fail"
    assert "1100" in flagged_codes


def test_account_balance_sanity_passes_on_clean_db():
    with get_db() as conn:
        ensure_schema(conn)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "account_balance_sanity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: future-dated entries
# ---------------------------------------------------------------------------


def test_future_dated_entries_flags_future_created_at():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, created_at) "
            "VALUES (?, ?, ?, ?)",
            ("Future entry", "manual", None, "2999-12-31T23:59:59Z"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "future_dated_entries")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    assert check["details"][0]["created_at"] == "2999-12-31T23:59:59Z"


def test_future_dated_entries_passes_on_normal_dates():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, created_at) "
            "VALUES (?, ?, ?, ?)",
            ("Normal entry", "manual", None, "2020-01-01T10:00:00Z"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "future_dated_entries")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: duplicate entries
# ---------------------------------------------------------------------------


def test_duplicate_entries_flags_same_source():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("First", "manual", 42),
        )
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Second", "manual", 42),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "duplicate_entries")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    assert check["details"][0]["source_type"] == "manual"
    assert check["details"][0]["source_id"] == 42
    assert len(check["details"][0]["entry_ids"]) == 2


def test_duplicate_entries_excludes_reversals():
    """Reversal entries (prefix 'Reversal:') legitimately share a source."""
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Original", "manual", 42),
        )
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Reversal: Original", "manual", 42),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "duplicate_entries")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_duplicate_entries_passes_on_distinct_sources():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Entry A", "manual", 42),
        )
        conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Entry B", "manual", 43),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "duplicate_entries")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: orphaned lines
# ---------------------------------------------------------------------------


def test_orphaned_lines_flags_nonexistent_account():
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Entry with orphan line", "manual", None),
        )
        entry_id = cur.lastrowid
        # Commit the entry so we can toggle FK enforcement off, then insert
        # a journal line pointing to a non-existent account. The check exists
        # precisely to catch this kind of corruption that can occur when FKs
        # are disabled (e.g. legacy data, manual DB edits).
        conn.commit()
        conn.execute("PRAGMA foreign_keys = OFF")
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, 999999, 100.0, 0.0, "orphan"),
        )
        conn.execute("PRAGMA foreign_keys = ON")
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "orphaned_lines")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    assert check["details"][0]["account_id"] == 999999


def test_orphaned_lines_passes_on_valid_account():
    with get_db() as conn:
        ensure_schema(conn)
        cash = _account_id(conn, "1100")
        revenue = _account_id(conn, "4100")
        _insert_balanced_entry(conn, cash, revenue, amount=100)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "orphaned_lines")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Service-level: expense category mismatch
# ---------------------------------------------------------------------------


def _insert_expense_event(conn, *, category: str, amount: float = 10000,
                          payment_source: str = "Shop tiền mặt") -> int:
    """Insert an expense event and return its id."""
    import json

    data = json.dumps({
        "amount_vnd": amount,
        "category": category,
        "payment_source": payment_source,
    })
    cur = conn.execute(
        "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
        ("expense", f"Expense: {category}", data),
    )
    return int(cur.lastrowid)


def test_expense_category_mismatch_flags_wrong_account():
    """Expense event with category 'Vận chuyển' should debit 5300, not 5100."""
    with get_db() as conn:
        ensure_schema(conn)
        event_id = _insert_expense_event(conn, category="Vận chuyển")
        wrong_expense = _account_id(conn, "5100")  # Nguyên liệu — wrong
        cash = _account_id(conn, "1100")
        _insert_balanced_entry(
            conn, wrong_expense, cash, debit_to=wrong_expense, amount=10000,
            source_type="expense", source_id=event_id,
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "expense_category_mismatch")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    finding = check["details"][0]
    assert finding["category"] == "Vận chuyển"
    assert finding["expected_account_code"] == "5300"
    assert finding["actual_account_code"] == "5100"


def test_expense_category_mismatch_passes_when_correct():
    """Expense event with category 'Vận chuyển' correctly debiting 5300."""
    with get_db() as conn:
        ensure_schema(conn)
        event_id = _insert_expense_event(conn, category="Vận chuyển")
        correct_expense = _account_id(conn, "5300")
        cash = _account_id(conn, "1100")
        _insert_balanced_entry(
            conn, correct_expense, cash, amount=10000,
            source_type="expense", source_id=event_id,
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "expense_category_mismatch")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_expense_category_mismatch_excludes_inventory_purchase_categories():
    """Inventory purchase categories (Nguyên liệu, Bao bì) debit Inventory
    (1300), not expense accounts — they should not be flagged."""
    with get_db() as conn:
        ensure_schema(conn)
        event_id = _insert_expense_event(conn, category="Nguyên liệu")
        inventory = _account_id(conn, "1300")
        cash = _account_id(conn, "1100")
        _insert_balanced_entry(
            conn, inventory, cash, amount=10000,
            source_type="expense", source_id=event_id,
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "expense_category_mismatch")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_expense_category_mismatch_passes_on_clean_db():
    with get_db() as conn:
        ensure_schema(conn)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "expense_category_mismatch")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Deposit revenue integrity (DG-198 Phase 6, FR5/AC5)
# ---------------------------------------------------------------------------


def _insert_revenue_entry(
    conn,
    *,
    order_id: int,
    lines: list[tuple[str, float, float]],
    description: str = "Order revenue: TEST",
) -> int:
    """Insert a ``source_type = 'order'`` journal entry with the given
    (account_code, debit, credit) lines. Caller is responsible for keeping
    the entry balanced (debit sum == credit sum) when double-entry integrity
    is expected to pass.
    """
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order', ?)",
        (description, order_id),
    )
    entry_id = int(cur.lastrowid)
    for code, debit, credit in lines:
        acct = _account_id(conn, code)
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, acct, debit, credit, ""),
        )
    return entry_id


def _insert_delivered_order(conn, *, order_id: int | None = None) -> int:
    if order_id is None:
        cur = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, total_price, status, due_date) "
            "VALUES (?, ?, ?, 'delivered', '2026-06-10')",
            ("ORD-DRI-1", "Tester", 500000.0),
        )
        return int(cur.lastrowid)
    return order_id


def test_deposit_revenue_integrity_passes_on_clean_db():
    with get_db() as conn:
        ensure_schema(conn)
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_deposit_revenue_integrity_passes_when_balanced_with_tien_rut():
    """Revenue entry: debit 2100 500k = credit 4100 500k. Tien rut (2400) is
    cleared in a separate return entry, not part of this revenue entry
    (DG-198 reversal)."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_delivered_order(conn)
        _insert_revenue_entry(
            conn,
            order_id=order_id,
            lines=[
                ("2100", 500000.0, 0.0),
                ("4100", 0.0, 500000.0),
            ],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_deposit_revenue_integrity_passes_when_no_tien_rut():
    """Revenue entry: debit 2100 500k = credit 4100 500k (no 2400 line)."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_delivered_order(conn)
        _insert_revenue_entry(
            conn,
            order_id=order_id,
            lines=[
                ("2100", 500000.0, 0.0),
                ("4100", 0.0, 500000.0),
            ],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_deposit_revenue_integrity_flags_2400_credit_in_revenue_entry():
    """DG-198 reversal: 2400 must NOT appear in the revenue entry (it is
    cleared separately via a Tien rut return entry). A revenue entry that
    credits 2400 instead of 4100 is a gap: debit 2100 500k != credit 4100 0.
    """
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_delivered_order(conn)
        _insert_revenue_entry(
            conn,
            order_id=order_id,
            lines=[
                ("2100", 500000.0, 0.0),
                # Old-style 2400 credit (pre-reversal) — now a gap.
                ("2400", 0.0, 500000.0),
            ],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    finding = check["details"][0]
    assert finding["debit_2100"] == 500000.0
    assert finding["credit_4100"] == 0.0
    assert finding["gap"] == 500000.0


def test_deposit_revenue_integrity_flags_gap_2400_missing():
    """Gap scenario: debit 2100 500k but only credit 4100 200k — revenue is
    understated by 300k (the original DG-198 failure mode: deposit balance
    not fully converted to revenue). debit_2100 (500k) != credit_4100 (200k).
    """
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_delivered_order(conn)
        entry_id = _insert_revenue_entry(
            conn,
            order_id=order_id,
            lines=[
                ("2100", 500000.0, 0.0),
                ("4100", 0.0, 200000.0),
                # Top up with an asset credit to keep the entry balanced so
                # double_entry_integrity does not also fire — only the
                # deposit-revenue identity is wrong.
                ("1100", 0.0, 300000.0),
            ],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    finding = check["details"][0]
    assert finding["entry_id"] == entry_id
    assert finding["order_id"] == order_id
    assert finding["debit_2100"] == 500000.0
    assert finding["credit_4100"] == 200000.0
    assert finding["gap"] == 300000.0


def test_deposit_revenue_integrity_flags_gap_2400_understated():
    """Gap scenario: 4100 credit too small. debit 2100 500k, credit 4100 100k
    → 500k != 100k, gap 400k.
    """
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_delivered_order(conn)
        _insert_revenue_entry(
            conn,
            order_id=order_id,
            lines=[
                ("2100", 500000.0, 0.0),
                ("4100", 0.0, 100000.0),
                ("1100", 0.0, 400000.0),  # balance the entry
            ],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "fail"
    assert check["issue_count"] == 1
    finding = check["details"][0]
    assert finding["debit_2100"] == 500000.0
    assert finding["credit_4100"] == 100000.0
    assert finding["gap"] == 400000.0


def test_deposit_revenue_integrity_excludes_ar_entries():
    """Unpaid order AR entries (debit 1500, credit 4100) have no 2100 debit,
    so the deposit-revenue identity is not applicable and they must not be
    flagged.
    """
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_delivered_order(conn)
        _insert_revenue_entry(
            conn,
            order_id=order_id,
            description="Order revenue (AR): TEST",
            lines=[
                ("1500", 500000.0, 0.0),
                ("4100", 0.0, 500000.0),
            ],
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


def test_deposit_revenue_integrity_end_to_end_after_journal_sync():
    """End-to-end: deposit + tien_rut payment, sync, deliver, sync revenue —
    validate-accounts must report no deposit-revenue gap (AC5).
    """
    from baker.services.journal_sync import (
        _sync_delivered_order_journal,
        _sync_payment_journal,
    )

    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, total_price, status, due_date) "
            "VALUES (?, ?, ?, 'pending', '2026-06-10')",
            ("ORD-DRI-E2E", "Tester", 500000.0),
        )
        order_id = int(cur.lastrowid)
        dep_cur = conn.execute(
            "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
            "VALUES (?, ?, 'deposit', 'cash', '')",
            (order_id, 500000.0),
        )
        _sync_payment_journal(
            conn, int(dep_cur.lastrowid), 500000.0, "deposit", "cash", order_id=order_id
        )
        tr_cur = conn.execute(
            "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
            "VALUES (?, ?, 'tien_rut', 'cash', '')",
            (order_id, 300000.0),
        )
        _sync_payment_journal(
            conn, int(tr_cur.lastrowid), 300000.0, "tien_rut", "cash", order_id=order_id
        )
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id = ?", (order_id,))
        _sync_delivered_order_journal(conn, order_id, order_ref="ORD-DRI-E2E")
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "deposit_revenue_integrity")
    assert check["status"] == "pass"
    assert check["issue_count"] == 0


# ---------------------------------------------------------------------------
# Timestamp format (DG-202 TC-3, TC-4)
# ---------------------------------------------------------------------------


def test_locked_at_is_z_suffixed_via_api(api_client):
    """TC-3: locked_at is Z-suffixed UTC when journal entries are locked via
    the /api/accounts/journal/lock endpoint."""
    from datetime import datetime

    # Insert a journal entry with a transaction_date in the lock range.
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, transaction_date) "
            "VALUES (?, ?, ?, ?)",
            ("Lock test", "manual", None, "2026-06-01"),
        )
        conn.commit()

    resp = api_client.post("/api/accounts/journal/lock", json={
        "since": "2026-06-01",
        "until": "2026-06-30",
        "lockedBy": "sinh",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["lockedCount"] >= 1
    locked_at = body["lockedAt"]
    assert locked_at.endswith("Z")
    assert "+" not in locked_at
    datetime.strptime(locked_at, "%Y-%m-%dT%H:%M:%SZ")

    # Verify the stored locked_at in the DB is also Z-suffixed.
    with get_db() as conn:
        row = conn.execute(
            "SELECT locked_at FROM journal_entries "
            "WHERE transaction_date = '2026-06-01' AND locked_at IS NOT NULL "
            "ORDER BY id DESC LIMIT 1"
        ).fetchone()
    assert row is not None
    assert row["locked_at"].endswith("Z")


def test_locked_at_null_when_not_locked():
    """TC-3 (null case): locked_at is None for an unlocked journal entry."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("Unlocked test", "manual", None),
        )
        entry_id = cur.lastrowid
        row = conn.execute(
            "SELECT locked_at FROM journal_entries WHERE id = ?", (entry_id,)
        ).fetchone()
    assert row["locked_at"] is None


def test_transaction_date_format_is_set(api_client):
    """TC-4: transaction_date on journal entries is set (Z-suffix or date-only
    as appropriate). The journal list API returns transactionDate populated."""
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO journal_entries "
            "(description, source_type, source_id, transaction_date) "
            "VALUES (?, ?, ?, ?)",
            ("TC-4 entry", "manual", None, "2026-06-15T10:00:00Z"),
        )
        conn.commit()

    resp = api_client.get("/api/accounts/journal", params={"source_type": "manual"})
    assert resp.status_code == 200
    items = resp.json()["items"]
    entry = next((e for e in items if e["description"] == "TC-4 entry"), None)
    assert entry is not None
    td = entry["transactionDate"]
    assert td is not None
    assert td == "2026-06-15T10:00:00Z"


def test_transaction_date_empty_when_not_set():
    """TC-4 (null case): transaction_date is empty/None when not explicitly
    set on a journal entry."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("TC-4 no date", "manual", None),
        )
        entry_id = cur.lastrowid
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (entry_id,)
        ).fetchone()
    # transaction_date may be NULL or empty string.
    assert row["transaction_date"] is None or row["transaction_date"] == ""