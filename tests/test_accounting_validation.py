"""Tests for accounting validation module — Phase 5 (DG-187, FR6/AC6).

Covers the four validation checks exposed via the service module, the
``GET /api/accounts/validate`` endpoint, and the ``baker validate-accounts``
CLI command:

- double-entry integrity (imbalanced journal entries flagged)
- COGS completeness (delivered order_items missing cost_at_sale)
- waste COGS referential integrity (orphaned waste_cogs entries)
- cost history sanity (negative costs, duplicate effective_from, future dates)
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
    ]


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
            (1, -500, "2020-01-01T00:00:00"),
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
            (1, 100, "2020-01-01T00:00:00"),
        )
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 200, "2020-01-01T00:00:00"),
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
            (1, 100, "2999-12-31T00:00:00"),
        )
        report = run_validation(conn)
    check = next(c for c in report["checks"] if c["check"] == "cost_history_sanity")
    futures = [f for f in check["details"] if f["anomaly"] == "future_effective_from"]
    assert len(futures) == 1
    assert futures[0]["effective_from"] == "2999-12-31T00:00:00"


def test_cost_history_sanity_passes_on_clean_history():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 100, "2020-01-01T00:00:00"),
        )
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 200, "2021-01-01T00:00:00"),
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
    assert body["summary"]["overall_status"] == "pass"
    assert len(body["checks"]) == 4
    assert body["summary"]["total_checks"] == 4


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