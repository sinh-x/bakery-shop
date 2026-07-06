"""Tests for ``baker repair-order-revenue --cogs`` — DG-208 Phase 5.

Covers FR8/FR9/NFR1/NFR5/AC6:

- ``--cogs --order-id`` repairs a stale COGS entry (delete-and-recreate)
- ``--cogs --order-id`` backfills a missing COGS entry
- ``--cogs --all`` repairs/backfills every stale/missing order
- ``--cogs --dry-run`` shows planned actions without mutating
- Idempotency (AC6): running ``--cogs --all`` twice → second run all "skipped"
- Non-delivered orders are excluded from ``--all``
- Already-correct entry within tolerance is skipped
- Locked entry is reported as "khoá" and not mutated
- Order with zero expected COGS reports "không áp dụng"
- Service-level ``_process_cogs_order`` action labels
"""

import click.testing

from baker.cli import app
from baker.commands.repair import _process_cogs_order
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_PRODUCT_SEQ = {"n": 0}


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0]
    )


def _insert_product(conn, *, name=None, category="banh_mi", base_price=100000):
    if name is None:
        _PRODUCT_SEQ["n"] += 1
        name = f"SP-{_PRODUCT_SEQ['n']}"
    cur = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (name, category, base_price, base_price),
    )
    return int(cur.lastrowid)


def _insert_order(
    conn,
    *,
    order_ref,
    customer_name="Khách thử",
    total_price=0,
    status="delivered",
    due_date="2026-06-10",
):
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date),
    )
    return int(cur.lastrowid)


def _add_order_item(
    conn,
    *,
    order_id,
    product_id,
    product_name="Bánh mì",
    qty=1,
    unit_price=100000,
    cost_at_sale=0,
    is_extra=0,
    is_gift=0,
):
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift) "
        "VALUES (?, ?, ?, ?, ?, 0, 'delivered', ?, ?, ?)",
        (order_id, product_id, product_name, qty, unit_price,
         cost_at_sale, is_extra, is_gift),
    )


def _insert_cogs_entry(
    conn,
    *,
    order_id,
    cogs_account_id,
    inventory_account_id,
    amount,
    order_ref="ORD",
    locked=False,
):
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order_cogs', ?)",
        (f"Order COGS: {order_ref}", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Giá vốn hàng bán')",
        (entry_id, cogs_account_id, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Xuất kho')",
        (entry_id, inventory_account_id, amount),
    )
    if locked:
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (entry_id,),
        )
    return entry_id


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _cogs_5900_debit(conn, order_id) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) AS debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_cogs' AND je.source_id = ? AND a.code = '5900'
        """,
        (order_id,),
    ).fetchone()
    return float(row["debit"])


def _seed_delivered_order_with_product(
    conn, *, order_ref, unit_price=100000, base_price=100000, cost_at_sale=0
):
    """Seed a delivered order with one non-extra/non-gift item.

    Returns (order_id, product_id). With base_price=100000 and no cost_history,
    the expected COGS for a qty=1 item is unit_price * 0.30.
    """
    pid = _insert_product(conn, base_price=base_price)
    oid = _insert_order(conn, order_ref=order_ref, total_price=unit_price)
    _add_order_item(
        conn,
        order_id=oid,
        product_id=pid,
        qty=1,
        unit_price=unit_price,
        cost_at_sale=cost_at_sale,
    )
    return oid, pid


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_cogs_flag_registered_in_help():
    result = _invoke(["repair-order-revenue", "--help"])
    assert result.exit_code == 0, result.output
    assert "--cogs" in result.output


# ---------------------------------------------------------------------------
# Single order: missing COGS → backfilled
# ---------------------------------------------------------------------------


def test_cogs_single_order_backfills_missing_entry():
    with get_db() as conn:
        ensure_schema(conn)
        oid, _pid = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-100", unit_price=200000, base_price=100000,
        )
        # No order_cogs entry exists → expected 200000 * 0.30 = 60000.
        assert _cogs_5900_debit(conn, oid) == 0.0

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-COGS-100" in result.output
    assert "đã sửa" in result.output
    # "bỏ qua: 0" and a "đã sửa: 1" count
    assert "đã sửa: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _cogs_5900_debit(conn, oid) == 60000.0
        # cost_at_sale was populated during backfill.
        row = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE order_id = ?", (oid,)
        ).fetchone()
        assert float(row["cost_at_sale"]) == 60000.0


# ---------------------------------------------------------------------------
# Single order: stale COGS → repaired (delete-and-recreate)
# ---------------------------------------------------------------------------


def test_cogs_single_order_repairs_stale_entry():
    """Stale = order_cogs entry exists but a zero-cost item hasn't been resolved.

    Item: unit_price=300000, base_price=100000, cost_at_sale=0 (not yet
    resolved). Existing order_cogs entry debits 10000 (stale/wrong, e.g. from
    a pre-fix run). Expected after resolution = 300000 * 0.30 = 90000, so the
    entry is stale → delete-and-recreate.
    """
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        oid, _pid = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-110", unit_price=300000, base_price=100000,
            cost_at_sale=0,
        )
        # Stale COGS entry: 10000 (does not match expected 300000 * 0.30 = 90000
        # once the zero-cost item is resolved).
        _insert_cogs_entry(
            conn, order_id=oid, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=10000, order_ref="ORD-COGS-110",
        )
        assert _cogs_5900_debit(conn, oid) == 10000.0

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-COGS-110" in result.output
    assert "đã sửa" in result.output
    assert "90.000" in result.output  # expected COGS

    with get_db() as conn:
        ensure_schema(conn)
        # Exactly one order_cogs entry now, debiting 90000.
        assert _cogs_5900_debit(conn, oid) == 90000.0
        count = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries "
            "WHERE source_type = 'order_cogs' AND source_id = ?",
            (oid,),
        ).fetchone()["c"]
        assert count == 1
        # cost_at_sale was populated during the repair.
        row = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE order_id = ?", (oid,)
        ).fetchone()
        assert float(row["cost_at_sale"]) == 90000.0


# ---------------------------------------------------------------------------
# Single order: already correct → skipped (idempotent)
# ---------------------------------------------------------------------------


def test_cogs_single_order_skips_already_correct():
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        oid, _pid = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-120", unit_price=100000, base_price=100000,
            cost_at_sale=30000,
        )
        # Expected = 100000 * 0.30 = 30000; entry already debits 30000.
        _insert_cogs_entry(
            conn, order_id=oid, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=30000, order_ref="ORD-COGS-120",
        )
        assert _cogs_5900_debit(conn, oid) == 30000.0

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "bỏ qua" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # Unchanged.
        assert _cogs_5900_debit(conn, oid) == 30000.0
        count = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries "
            "WHERE source_type = 'order_cogs' AND source_id = ?",
            (oid,),
        ).fetchone()["c"]
        assert count == 1


# ---------------------------------------------------------------------------
# Idempotency AC6: --cogs --all twice → second run all "skipped"
# ---------------------------------------------------------------------------


def test_cogs_all_idempotent_second_run_all_skipped():
    with get_db() as conn:
        ensure_schema(conn)
        # Two delivered orders, both missing COGS initially.
        _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-200", unit_price=200000, base_price=100000,
        )
        _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-201", unit_price=500000, base_price=100000,
        )

    # First run: both should be backfilled (đã sửa: 2, bỏ qua: 0).
    r1 = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert r1.exit_code == 0, r1.output
    assert "ORD-COGS-200" in r1.output
    assert "ORD-COGS-201" in r1.output
    assert "đã sửa: 2" in r1.output
    assert "bỏ qua: 0" in r1.output

    # Second run: idempotent → all skipped (AC6).
    r2 = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "ORD-COGS-200" in r2.output
    assert "ORD-COGS-201" in r2.output
    assert "đã sửa: 0" in r2.output
    assert "bỏ qua: 2" in r2.output


# ---------------------------------------------------------------------------
# --all scopes to delivered/completed orders
# ---------------------------------------------------------------------------


def test_cogs_all_excludes_non_delivered_orders():
    with get_db() as conn:
        ensure_schema(conn)
        # Delivered order needing backfill.
        oid1, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-300", unit_price=100000, base_price=100000,
        )
        # Non-delivered (new) order missing COGS — should be excluded.
        pid = _insert_product(conn, base_price=100000)
        oid2 = _insert_order(
            conn, order_ref="ORD-COGS-301", total_price=100000, status="new",
        )
        _add_order_item(
            conn, order_id=oid2, product_id=pid, qty=1,
            unit_price=100000, cost_at_sale=0,
        )

    result = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-COGS-300" in result.output
    assert "ORD-COGS-301" not in result.output


# ---------------------------------------------------------------------------
# Dry-run does not mutate
# ---------------------------------------------------------------------------


def test_cogs_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-400", unit_price=200000, base_price=100000,
        )
        assert _cogs_5900_debit(conn, oid) == 0.0

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid), "--dry-run"]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-COGS-400" in result.output
    assert "sẽ sửa" in result.output
    assert "đã sửa" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # No entry created.
        assert _cogs_5900_debit(conn, oid) == 0.0
        # cost_at_sale not populated (dry run must not write back).
        row = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE order_id = ?", (oid,)
        ).fetchone()
        assert float(row["cost_at_sale"]) == 0.0


# ---------------------------------------------------------------------------
# Locked entry → "khoá", not mutated
# ---------------------------------------------------------------------------


def test_cogs_locked_entry_not_mutated():
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-500", unit_price=300000, base_price=100000,
            cost_at_sale=0,
        )
        # Stale AND locked entry (cost_at_sale=0 → expected 90000, entry=10000).
        _insert_cogs_entry(
            conn, order_id=oid, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=10000, order_ref="ORD-COGS-500",
            locked=True,
        )
        assert _cogs_5900_debit(conn, oid) == 10000.0

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "khoá" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # Unchanged.
        assert _cogs_5900_debit(conn, oid) == 10000.0


# ---------------------------------------------------------------------------
# Zero expected COGS → "không áp dụng"
# ---------------------------------------------------------------------------


def test_cogs_zero_expected_reports_not_applicable():
    with get_db() as conn:
        ensure_schema(conn)
        # Product with base_price = 0 → baseline resolves to 0.
        pid = _insert_product(conn, base_price=0)
        oid = _insert_order(
            conn, order_ref="ORD-COGS-600", total_price=0, status="delivered",
        )
        _add_order_item(
            conn, order_id=oid, product_id=pid, qty=1,
            unit_price=0, cost_at_sale=0,
        )

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "không áp dụng" in result.output


# ---------------------------------------------------------------------------
# Tolerance: entry within 0.005 VND → skipped
# ---------------------------------------------------------------------------


def test_cogs_within_tolerance_skipped():
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        # Expected = 30000.002 (100000.001 * 0.30 rounded to 2dp = 30000.00).
        # Use unit_price so expected is exactly 30000.00; entry debits 30000.002
        # → within MISMATCH_TOLERANCE (0.005) → skipped.
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-700", unit_price=100000, base_price=100000,
            cost_at_sale=30000,
        )
        _insert_cogs_entry(
            conn, order_id=oid, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=30000.002,
            order_ref="ORD-COGS-700",
        )

    result = _invoke(
        ["repair-order-revenue", "--cogs", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "bỏ qua" in result.output


# ---------------------------------------------------------------------------
# Service-level: _process_cogs_order action labels
# ---------------------------------------------------------------------------


def test_process_cogs_order_backfills_missing():
    with get_db() as conn:
        ensure_schema(conn)
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-800", unit_price=200000, base_price=100000,
        )
        result = _process_cogs_order(conn, oid, dry_run=False)
    assert result["action"] == "backfilled"
    assert result["expected_cogs"] == 60000.0


def test_process_cogs_order_skipped_when_correct():
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-810", unit_price=100000, base_price=100000,
            cost_at_sale=30000,
        )
        _insert_cogs_entry(
            conn, order_id=oid, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=30000, order_ref="ORD-COGS-810",
        )
        result = _process_cogs_order(conn, oid, dry_run=False)
    assert result["action"] == "skipped"


def test_process_cogs_order_will_backfill_in_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-820", unit_price=200000, base_price=100000,
        )
        result = _process_cogs_order(conn, oid, dry_run=True)
    assert result["action"] == "will-backfill"


def test_process_cogs_order_will_repair_stale_in_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        oid, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-830", unit_price=300000, base_price=100000,
            cost_at_sale=0,
        )
        # Stale: entry=10000 vs expected 90000 once resolved.
        _insert_cogs_entry(
            conn, order_id=oid, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=10000, order_ref="ORD-COGS-830",
        )
        result = _process_cogs_order(conn, oid, dry_run=True)
    assert result["action"] == "will-repair"


def test_process_cogs_order_not_applicable_when_zero_expected():
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, base_price=0)
        oid = _insert_order(
            conn, order_ref="ORD-COGS-840", total_price=0, status="delivered",
        )
        _add_order_item(
            conn, order_id=oid, product_id=pid, qty=1,
            unit_price=0, cost_at_sale=0,
        )
        result = _process_cogs_order(conn, oid, dry_run=False)
    assert result["action"] == "not-applicable"


# ---------------------------------------------------------------------------
# --cogs --all repairs a mix: stale + missing + correct
# ---------------------------------------------------------------------------


def test_cogs_all_repairs_mix_of_stale_missing_correct():
    with get_db() as conn:
        ensure_schema(conn)
        cogs_acc = _account_id(conn, "5900")
        inv_acc = _account_id(conn, "1300")
        # Order 1: missing COGS → backfilled.
        _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-900", unit_price=200000, base_price=100000,
        )
        # Order 2: stale COGS (zero-cost item + wrong existing entry) → repaired.
        oid2, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-901", unit_price=300000, base_price=100000,
            cost_at_sale=0,
        )
        _insert_cogs_entry(
            conn, order_id=oid2, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=10000, order_ref="ORD-COGS-901",
        )
        # Order 3: already correct (cost_at_sale set, entry matches) → skipped.
        oid3, _ = _seed_delivered_order_with_product(
            conn, order_ref="ORD-COGS-902", unit_price=100000, base_price=100000,
            cost_at_sale=30000,
        )
        _insert_cogs_entry(
            conn, order_id=oid3, cogs_account_id=cogs_acc,
            inventory_account_id=inv_acc, amount=30000, order_ref="ORD-COGS-902",
        )

    result = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-COGS-900" in result.output
    assert "ORD-COGS-901" in result.output
    assert "ORD-COGS-902" in result.output
    # 2 repaired/backfilled (missing + stale), 1 skipped.
    assert "đã sửa: 2" in result.output
    assert "bỏ qua: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        oid_a = _order_id_by_ref(conn, "ORD-COGS-900")
        oid_b = _order_id_by_ref(conn, "ORD-COGS-901")
        oid_c = _order_id_by_ref(conn, "ORD-COGS-902")
        # Missing → backfilled to 200000 * 0.30 = 60000.
        assert _cogs_5900_debit(conn, oid_a) == 60000.0
        # Stale → repaired to 300000 * 0.30 = 90000.
        assert _cogs_5900_debit(conn, oid_b) == 90000.0
        # Already correct → unchanged at 30000.
        assert _cogs_5900_debit(conn, oid_c) == 30000.0
        # Exactly one order_cogs entry per order.
        for oid in (oid_a, oid_b, oid_c):
            count = conn.execute(
                "SELECT COUNT(*) AS c FROM journal_entries "
                "WHERE source_type = 'order_cogs' AND source_id = ?",
                (oid,),
            ).fetchone()["c"]
            assert count == 1


def _order_id_by_ref(conn, order_ref):
    row = conn.execute(
        "SELECT id FROM orders WHERE order_ref = ?", (order_ref,)
    ).fetchone()
    return int(row["id"])