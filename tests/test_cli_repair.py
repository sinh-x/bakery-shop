"""Tests for ``baker repair-order-revenue`` CLI command — DG-190 Phase 4.2.

Covers:

- ``--order-id`` single-order repair (stale entry → repaired)
- ``--all`` batch repair of stale entries
- ``--dry-run`` shows what would change without mutating
- Idempotent no-op on an already-correct order
- Non-delivered order reports "không áp dụng"
- Command registration / ``--help``
- Service-level helper coverage (``_process_order`` actions)

Each test seeds a small known dataset and asserts the expected values appear
in the CLI output.
"""

import click
import click.testing

from baker.cli import app
from baker.commands.repair import _process_order
from baker.commands.repair.order_revenue import _process_shipping_release_order
from baker.commands.repair import _vn_amount
from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.journal_sync import _replace_order_entry


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0])


def _insert_order(
    conn,
    *,
    order_ref: str,
    customer_name: str = "Khách thử",
    total_price: float = 500000.0,
    status: str = "delivered",
    due_date: str | None = "2026-06-10",
) -> int:
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date),
    )
    return int(cur.lastrowid)


def _insert_payment(
    conn,
    *,
    order_id: int,
    amount: float,
    ptype: str = "deposit",
    method: str = "cash",
) -> int:
    cur = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method) "
        "VALUES (?, ?, ?, ?)",
        (order_id, amount, ptype, method),
    )
    return int(cur.lastrowid)


def _insert_revenue_entry(
    conn,
    *,
    order_id: int,
    deposits_account_id: int,
    revenue_account_id: int,
    amount: float,
) -> int:
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order', ?)",
        (f"Order revenue: {order_id}", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Chuyển cọc sang doanh thu')",
        (entry_id, deposits_account_id, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Doanh thu bán hàng')",
        (entry_id, revenue_account_id, amount),
    )
    return entry_id


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _revenue_2100_debit(conn, order_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) AS debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = '2100'
        """,
        (order_id,),
    ).fetchone()
    return float(row["debit"])


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_repair_command_registered():
    result = _invoke(["repair-order-revenue", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_repair_requires_one_mode():
    result = _invoke(["repair-order-revenue"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_repair_rejects_both_modes():
    result = _invoke(["repair-order-revenue", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# Single order repair
# ---------------------------------------------------------------------------


def test_repair_single_order_fixes_stale_entry():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-100", customer_name="Anh K",
            total_price=700000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        assert _revenue_2100_debit(conn, oid) == 700000.0

    result = _invoke(["repair-order-revenue", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-100" in result.output
    assert "700.000" in result.output  # old debit
    assert "500.000" in result.output  # net deposits
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid) == 500000.0


# ---------------------------------------------------------------------------
# Idempotent: already-correct order is a no-op
# ---------------------------------------------------------------------------


def test_repair_already_correct_order_is_noop():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-110", customer_name="Anh C",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )
        assert _revenue_2100_debit(conn, oid) == 500000.0

    result = _invoke(["repair-order-revenue", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "bỏ qua" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid) == 500000.0


# ---------------------------------------------------------------------------
# Non-delivered order reports not applicable
# ---------------------------------------------------------------------------


def test_repair_non_delivered_order_reports_not_applicable():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-120", customer_name="Anh N",
            total_price=500000, status="new",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )

    result = _invoke(["repair-order-revenue", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-120" in result.output
    assert "không áp dụng" in result.output


# ---------------------------------------------------------------------------
# Batch --all
# ---------------------------------------------------------------------------


def test_repair_all_repairs_only_stale_entries():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        # Order 1: stale (700k debit vs 500k net) → repaired.
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-200", customer_name="Khách 1",
            total_price=700000, status="delivered",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid1, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        # Order 2: already correct (500k = 500k) → skipped.
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-201", customer_name="Khách 2",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid2, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid2, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )
        # Order 3: delivered but no revenue entry → included, revenue entry created.
        oid3 = _insert_order(
            conn, order_ref="ORD-260624-202", customer_name="Khách 3",
            total_price=300000, status="delivered",
        )
        _insert_payment(conn, order_id=oid3, amount=300000, ptype="deposit")

    result = _invoke(["repair-order-revenue", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-200" in result.output
    assert "ORD-260624-201" in result.output
    assert "ORD-260624-202" in result.output
    assert "đã sửa: 2" in result.output
    assert "bỏ qua: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid1) == 500000.0


# ---------------------------------------------------------------------------
# Batch --all idempotency: second run is all "bỏ qua" (NF2, AC2)
# ---------------------------------------------------------------------------


def test_repair_all_idempotent_second_run_all_skipped():
    """After --all creates missing entries, a second --all run reports all orders as 'bỏ qua'."""
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-250", customer_name="Khách I1",
            total_price=400000, status="delivered", due_date="2026-07-01",
        )
        _insert_payment(conn, order_id=oid1, amount=400000, ptype="deposit")
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-251", customer_name="Khách I2",
            total_price=600000, status="completed", due_date="2026-07-02",
        )
        _insert_payment(conn, order_id=oid2, amount=600000, ptype="deposit")

    # First run: creates entries for both orders.
    result1 = _invoke(["repair-order-revenue", "--all"])
    assert result1.exit_code == 0, result1.output
    assert "ORD-260624-250" in result1.output
    assert "ORD-260624-251" in result1.output
    assert "đã sửa: 2" in result1.output

    # Verify entries were created.
    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid1) == 400000.0
        assert _revenue_2100_debit(conn, oid2) == 600000.0

    # Second run: all orders already correct → skipped.
    result2 = _invoke(["repair-order-revenue", "--all"])
    assert result2.exit_code == 0, result2.output
    assert "ORD-260624-250" in result2.output
    assert "ORD-260624-251" in result2.output
    assert "bỏ qua: 2" in result2.output
    assert "đã sửa: 0" in result2.output


# ---------------------------------------------------------------------------
# Dry-run
# ---------------------------------------------------------------------------


def test_repair_all_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-300", customer_name="Khách D",
            total_price=700000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        assert _revenue_2100_debit(conn, oid) == 700000.0

    result = _invoke(["repair-order-revenue", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-300" in result.output
    assert "sẽ sửa" in result.output
    assert "đã sửa" not in result.output

    # Database unchanged.
    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid) == 700000.0


def test_repair_single_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-310", customer_name="Khách S",
            total_price=700000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        assert _revenue_2100_debit(conn, oid) == 700000.0

    result = _invoke(["repair-order-revenue", "--order-id", str(oid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid) == 700000.0


# ---------------------------------------------------------------------------
# Dry-run on already-correct order is a no-op (skipped)
# ---------------------------------------------------------------------------


def test_repair_dry_run_skips_already_correct():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-320", customer_name="Khách OK",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )

    result = _invoke(["repair-order-revenue", "--order-id", str(oid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "bỏ qua: 1" in result.output
    assert "sẽ sửa: 0" in result.output


# ---------------------------------------------------------------------------
# Refund (tien_rut) double-debit repair
# ---------------------------------------------------------------------------


def test_repair_fixes_refund_double_debit():
    """500k deposit + 200k refund; stale revenue debits 700k → repaired to 300k net.

    Refund is a true outflow (DR 2100 at payment time), so the deposit balance
    converted to revenue is 500k − 200k = 300k. (``tien_rut`` is no longer an
    outflow per the DG-198 reversal — it is a deposit inflow journaled to 2400
    and returned separately — so a tien_rut would NOT reduce the 2100 debit.)
    """
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-400", customer_name="Anh R",
            total_price=700000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_payment(conn, order_id=oid, amount=200000, ptype="refund")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        assert _revenue_2100_debit(conn, oid) == 700000.0

    result = _invoke(["repair-order-revenue", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "300.000" in result.output  # net deposits (500k − 200k refund)

    with get_db() as conn:
        ensure_schema(conn)
        assert _revenue_2100_debit(conn, oid) == 300000.0


# ---------------------------------------------------------------------------
# Service-level: _process_order action labels
# ---------------------------------------------------------------------------


def test_process_order_creates_when_no_revenue_entry():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260624-500", customer_name="Anh NA",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        result = _process_order(conn, oid, dry_run=False)
    assert result["action"] == "created"


def test_process_order_skipped_when_within_tolerance():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-510", customer_name="Anh SK",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000.002,
        )
        result = _process_order(conn, oid, dry_run=False)
    assert result["action"] == "skipped"


def test_process_order_will_repair_in_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260624-520", customer_name="Anh WR",
            total_price=700000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        result = _process_order(conn, oid, dry_run=True)
    assert result["action"] == "will-repair"


# ---------------------------------------------------------------------------
# --since date filtering (Phase 4.2)
# ---------------------------------------------------------------------------


def test_repair_all_with_since_filters_by_due_date():
    """--since DATE limits scan to orders with due_date >= DATE."""
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-600", customer_name="Khách Sau",
            total_price=700000, status="delivered", due_date="2026-06-01",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid1, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-601", customer_name="Khách Trước",
            total_price=700000, status="delivered", due_date="2026-05-01",
        )
        _insert_payment(conn, order_id=oid2, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid2, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )

    result = _invoke(["repair-order-revenue", "--all", "--since", "2026-06-01"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-600" in result.output
    assert "ORD-260624-601" not in result.output
    assert "đã sửa: 1" in result.output
    assert "bỏ qua: 0" in result.output


def test_repair_all_with_since_includes_orders_without_revenue_entry():
    """--since scan includes orders with no revenue entry (created action)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-610", customer_name="Khách Mới",
            total_price=300000, status="delivered", due_date="2026-07-01",
        )
        _insert_payment(conn, order_id=oid1, amount=300000, ptype="deposit")
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-611", customer_name="Khách Cũ",
            total_price=300000, status="delivered", due_date="2026-05-01",
        )
        _insert_payment(conn, order_id=oid2, amount=300000, ptype="deposit")

    result = _invoke(["repair-order-revenue", "--all", "--since", "2026-06-01"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-610" in result.output
    assert "ORD-260624-611" not in result.output
    assert "đã tạo" in result.output
    assert "đã sửa: 1" in result.output


def test_since_rejected_without_all():
    """--since without --all is an error."""
    result = _invoke(["repair-order-revenue", "--order-id", "1", "--since", "2026-06-01"])
    assert result.exit_code != 0
    assert "chỉ dùng với --all" in result.output


# ---------------------------------------------------------------------------
# VN amount formatting
# ---------------------------------------------------------------------------


def test_vn_amount_formatting():
    from baker.commands.repair import _vn_amount

    assert _vn_amount(0) == "0"
    assert _vn_amount(500000) == "500.000"
    assert _vn_amount(1500000) == "1.500.000"
    assert _vn_amount(-200000) == "-200.000"


# ---------------------------------------------------------------------------
# check-revenue-gaps (Phase 4.3)
# ---------------------------------------------------------------------------


def test_check_revenue_gaps_command_registered():
    result = _invoke(["check-revenue-gaps", "--help"])
    assert result.exit_code == 0, result.output
    assert "chỉ đọc" in result.output.lower()


def test_check_revenue_gaps_finds_missing_entries():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-700", customer_name="Khách G1",
            total_price=500000, status="delivered", due_date="2026-07-01",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-701", customer_name="Khách G2",
            total_price=300000, status="completed", due_date="2026-07-02",
        )
        _insert_payment(conn, order_id=oid2, amount=300000, ptype="deposit")
        oid3 = _insert_order(
            conn, order_ref="ORD-260624-702", customer_name="Khách OK",
            total_price=400000, status="delivered", due_date="2026-07-03",
        )
        _insert_payment(conn, order_id=oid3, amount=400000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid3, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=400000,
        )

    result = _invoke(["check-revenue-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-700" in result.output
    assert "ORD-260624-701" in result.output
    assert "ORD-260624-702" not in result.output
    assert "Tổng: 2" in result.output


def test_check_revenue_gaps_read_only_no_mutation():
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-710", customer_name="Khách RO",
            total_price=500000, status="delivered", due_date="2026-07-10",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")

    # Count rows before
    with get_db() as conn:
        ensure_schema(conn)
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_before = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        pt_before = conn.execute("SELECT COUNT(*) AS c FROM payment_transactions").fetchone()["c"]
        o_before = conn.execute("SELECT COUNT(*) AS c FROM orders").fetchone()["c"]

    result = _invoke(["check-revenue-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-710" in result.output
    assert "thiếu bút toán doanh thu" in result.output

    # Count rows after — must be identical
    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_after = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        pt_after = conn.execute("SELECT COUNT(*) AS c FROM payment_transactions").fetchone()["c"]
        o_after = conn.execute("SELECT COUNT(*) AS c FROM orders").fetchone()["c"]

    assert je_before == je_after
    assert jl_before == jl_after
    assert pt_before == pt_after
    assert o_before == o_after


def test_check_revenue_gaps_empty_when_all_have_entries():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-720", customer_name="Khách All",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid1, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )

    result = _invoke(["check-revenue-gaps"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào" in result.output


def test_check_revenue_gaps_ignores_non_delivered_orders():
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-730", customer_name="Khách New",
            total_price=500000, status="new",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")

    result = _invoke(["check-revenue-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-730" not in result.output
    assert "không có đơn hàng nào" in result.output


# ---------------------------------------------------------------------------
# ``baker repair-payment-journal`` CLI tests — DG-233 Phase 1
# ---------------------------------------------------------------------------


def _payment_journal_entry(conn, txn_id: int):
    """Return the journal entry id for a payment transaction, or None."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'payment_transaction' AND source_id = ?",
        (txn_id,),
    ).fetchone()
    return int(row["id"]) if row else None


def _payment_journal_lines(conn, txn_id: int):
    """Return count of journal lines for a payment transaction's journal entry."""
    row = conn.execute(
        "SELECT COUNT(*) AS c FROM journal_lines jl "
        "JOIN journal_entries je ON je.id = jl.journal_entry_id "
        "WHERE je.source_type = 'payment_transaction' AND je.source_id = ?",
        (txn_id,),
    ).fetchone()
    return int(row["c"]) if row else 0


# Registration & help


def test_payment_journal_command_registered():
    result = _invoke(["repair-payment-journal", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_payment_journal_requires_one_mode():
    result = _invoke(["repair-payment-journal"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_payment_journal_rejects_both_modes():
    result = _invoke(["repair-payment-journal", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# --all backfill


def test_payment_journal_all_backfills_missing():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260707-052", customer_name="Khách Backfill",
            total_price=500000, status="delivered",
        )
        txn1 = _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        txn2 = _insert_payment(conn, order_id=oid, amount=50000, ptype="refund")
        # No journal entries created — simulating missing backfill state

    result = _invoke(["repair-payment-journal", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "#" + str(txn1) in result.output
    assert "#" + str(txn2) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _payment_journal_entry(conn, txn1) is not None
        assert _payment_journal_entry(conn, txn2) is not None
        assert _payment_journal_lines(conn, txn1) > 0
        assert _payment_journal_lines(conn, txn2) > 0


def test_payment_journal_all_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-053", customer_name="Khách Idem",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")

    # First run — backfills
    result1 = _invoke(["repair-payment-journal", "--all"])
    assert result1.exit_code == 0, result1.output
    assert "đã sửa" in result1.output

    # Second run — idempotent, no transactions need backfill
    result2 = _invoke(["repair-payment-journal", "--all"])
    assert result2.exit_code == 0, result2.output
    assert "không có giao dịch thanh toán nào cần bổ sung" in result2.output


# --order-id backfill


def test_payment_journal_order_id_backfills():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-054", customer_name="Khách Single",
            total_price=500000, status="delivered",
        )
        txn1 = _insert_payment(conn, order_id=oid, amount=200000, ptype="deposit")
        _insert_payment(conn, order_id=oid, amount=100000, ptype="refund")

    result = _invoke(["repair-payment-journal", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    # Both payment transactions for this order should be backfilled
    assert "#" + str(txn1) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # Check all transactions for that order got journal entries
        txns = conn.execute(
            "SELECT id FROM payment_transactions WHERE order_id = ?", (oid,)
        ).fetchall()
        for t in txns:
            assert _payment_journal_entry(conn, int(t["id"])) is not None


# --dry-run


def test_payment_journal_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-055", customer_name="Khách Dry",
            total_price=500000, status="delivered",
        )
        txn1 = _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_before = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]

    result = _invoke(["repair-payment-journal", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output
    assert "#" + str(txn1) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_after = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        entry_id = _payment_journal_entry(conn, txn1)

    assert je_before == je_after
    assert jl_before == jl_after
    assert entry_id is None


def test_payment_journal_dry_run_order_id():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-056", customer_name="Khách Dry2",
            total_price=500000, status="delivered",
        )
        txn1 = _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")

    result = _invoke(["repair-payment-journal", "--order-id", str(oid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _payment_journal_entry(conn, txn1) is None


# Invalidated transactions are skipped


def test_payment_journal_skips_invalidated():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-057", customer_name="Khách Inv",
            total_price=500000, status="delivered",
        )
        # Create a payment transaction then invalidate it
        txn1 = _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        conn.execute(
            "UPDATE payment_transactions SET invalidated_at = datetime('now') WHERE id = ?",
            (txn1,),
        )

    result = _invoke(["repair-payment-journal", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có giao dịch thanh toán nào cần bổ sung" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _payment_journal_entry(conn, txn1) is None


# Vietnamese labels


def test_payment_journal_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-058", customer_name="Khách VN",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")

    result = _invoke(["repair-payment-journal", "--all"])
    assert result.exit_code == 0, result.output
    assert "Bổ sung bút toán nhật ký thanh toán" in result.output
    assert "Mã GD" in result.output
    assert "Số tiền" in result.output
    assert "Loại" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


# ---------------------------------------------------------------------------
# ``baker repair-ar-entries`` — DG-233 Phase 2 tests
# (FR2, AC8, AC7, AC9)
# ---------------------------------------------------------------------------


def _ar_entry_exists(conn, order_id: int):
    """Return True if the order has a source_type='order' journal entry."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return row is not None


def _ar_entry_has_ar_desc(conn, order_id: int):
    """Return True if the order has an AR-prefix journal entry."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order' AND source_id = ? AND description LIKE ?",
        (order_id, "Order revenue (AR):%"),
    ).fetchone()
    return row is not None


# Registration & help


def test_ar_entries_command_registered():
    result = _invoke(["repair-ar-entries", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_ar_entries_requires_one_mode():
    result = _invoke(["repair-ar-entries"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_ar_entries_rejects_both_modes():
    result = _invoke(["repair-ar-entries", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# --all backfill


def test_ar_entries_all_backfills_missing():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-009", customer_name="Khách AR",
            total_price=500000, status="delivered",
        )
        # No payment_transactions — zero deposit order

    result = _invoke(["repair-ar-entries", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "ORD-260707-009" in result.output
    assert "500.000" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _ar_entry_exists(conn, oid)
        assert _ar_entry_has_ar_desc(conn, oid)


def test_ar_entries_all_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-010", customer_name="Khách Idem",
            total_price=500000, status="delivered",
        )

    # First run — creates AR entry
    result1 = _invoke(["repair-ar-entries", "--all"])
    assert result1.exit_code == 0, result1.output
    assert "đã sửa" in result1.output

    # Second run — idempotent, no orders need backfill
    result2 = _invoke(["repair-ar-entries", "--all"])
    assert result2.exit_code == 0, result2.output
    assert "không có đơn hàng nào cần bổ sung bút toán công nợ" in result2.output


# --order-id backfill


def test_ar_entries_order_id_backfills():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-011", customer_name="Khách Single",
            total_price=200000, status="delivered",
        )

    result = _invoke(["repair-ar-entries", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "ORD-260707-011" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _ar_entry_exists(conn, oid)
        assert _ar_entry_has_ar_desc(conn, oid)


def test_ar_entries_order_id_not_applicable_when_not_zero_deposit():
    """Order with deposits should not be picked up (handled by repair-order-revenue)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-012", customer_name="Khách Skip",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")

    result = _invoke(["repair-ar-entries", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào cần bổ sung bút toán công nợ" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert not _ar_entry_exists(conn, oid)


# --dry-run


def test_ar_entries_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-013", customer_name="Khách Dry",
            total_price=300000, status="delivered",
        )
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]

    result = _invoke(["repair-ar-entries", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output
    assert "ORD-260707-013" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        assert not _ar_entry_exists(conn, oid)

    assert je_before == je_after


def test_ar_entries_dry_run_order_id():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-014", customer_name="Khách Dry2",
            total_price=300000, status="delivered",
        )

    result = _invoke(["repair-ar-entries", "--order-id", str(oid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert not _ar_entry_exists(conn, oid)


# Non-delivered orders are skipped


def test_ar_entries_skips_non_delivered():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn, order_ref="ORD-260707-015", customer_name="Khách Draft",
            total_price=500000, status="draft",
        )

    result = _invoke(["repair-ar-entries", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào cần bổ sung bút toán công nợ" in result.output


def test_ar_entries_skips_deposit_orders():
    """Orders with deposits but no revenue entry should not be picked up."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-016", customer_name="Khách Dep",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=400000, ptype="deposit")

    result = _invoke(["repair-ar-entries", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào cần bổ sung bút toán công nợ" in result.output


# Vietnamese labels


def test_ar_entries_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn, order_ref="ORD-260707-017", customer_name="Khách VN",
            total_price=500000, status="delivered",
        )

    result = _invoke(["repair-ar-entries", "--all"])
    assert result.exit_code == 0, result.output
    assert "Bổ sung bút toán công nợ phải thu (AR)" in result.output
    assert "Mã đơn" in result.output
    assert "Tổng tiền" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


# ---------------------------------------------------------------------------
# Cross-guard: deposit-style revenue JE prevents AR entry (DG-249 Phase 1, AC1)
# ---------------------------------------------------------------------------


def test_ar_entries_skips_order_with_deposit_style_revenue_je():
    """AC1: an order with a deposit-style revenue JE (source_type='order',
    debit on 2100) must be skipped by ``repair-ar-entries --all`` so no
    duplicate AR entry is created.
    """
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260716-AC1", customer_name="Khách Cọc",
            total_price=500000, status="delivered",
        )
        # Insert a deposit-style revenue JE (DR 2100 / CR 4100) directly so
        # the order already has a source_type='order' entry with a 2100 debit.
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )
        assert _revenue_2100_debit(conn, oid) == 500000.0
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]

    result = _invoke(["repair-ar-entries", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào cần bổ sung bút toán công nợ" in result.output
    assert "ORD-260716-AC1" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # No new AR entry created — JE count unchanged.
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        assert je_before == je_after
        # The deposit-style entry is still the only order entry; no AR entry.
        assert not _ar_entry_has_ar_desc(conn, oid)
        assert _revenue_2100_debit(conn, oid) == 500000.0


def test_ar_entries_skips_order_with_deposit_style_revenue_je_order_id():
    """AC1 (single-order path): ``--order-id`` on an order with a deposit-style
    revenue JE is also skipped — no duplicate AR entry created.
    """
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260716-AC1b", customer_name="Khách Cọc2",
            total_price=300000, status="delivered",
        )
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=300000,
        )
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]

    result = _invoke(["repair-ar-entries", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào cần bổ sung bút toán công nợ" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        assert je_before == je_after
        assert not _ar_entry_has_ar_desc(conn, oid)


# ---------------------------------------------------------------------------
# ``baker repair-inventory`` CLI tests — DG-233 Phase 4
# (FR4, AC4, AC7, AC9)
# ---------------------------------------------------------------------------


def _insert_expense_event(conn, *, category: str, amount: float = 10000,
                          payment_source: str = "Tiền mặt tại quầy") -> int:
    """Insert an expense event and return its id."""
    import json

    data = json.dumps({
        "amount_vnd": amount,
        "category": category,
        "payment_source": payment_source,
    })
    cur = conn.execute(
        "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
        ("expense", f"Chi phí: {category}", data),
    )
    return int(cur.lastrowid)


def _expense_journal_entry(conn, event_id: int):
    """Return the journal entry id for an expense event, or None."""
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'expense' AND source_id = ?",
        (event_id,),
    ).fetchone()
    return int(row["id"]) if row else None


# Registration & help


def test_inventory_command_registered():
    result = _invoke(["repair-inventory", "--help"])
    assert result.exit_code == 0, result.output
    assert "--event-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_inventory_requires_one_mode():
    result = _invoke(["repair-inventory"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_inventory_rejects_both_modes():
    result = _invoke(["repair-inventory", "--event-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# --all backfill


def test_inventory_all_backfills_missing():
    with get_db() as conn:
        ensure_schema(conn)
        eid1 = _insert_expense_event(
            conn, category="Nguyên liệu", amount=500000,
            payment_source="Tiền mặt tại quầy",
        )
        eid2 = _insert_expense_event(
            conn, category="Bao bì", amount=200000,
            payment_source="Tiền mặt tại quầy",
        )
        assert eid1 > 0
        assert eid2 > 0

    result = _invoke(["repair-inventory", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "#" + str(eid1) in result.output
    assert "#" + str(eid2) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_journal_entry(conn, eid1) is not None
        assert _expense_journal_entry(conn, eid2) is not None


def test_inventory_all_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_expense_event(
            conn, category="Nguyên liệu", amount=300000,
            payment_source="Tiền mặt tại quầy",
        )

    result1 = _invoke(["repair-inventory", "--all"])
    assert result1.exit_code == 0, result1.output
    assert "đã sửa" in result1.output

    result2 = _invoke(["repair-inventory", "--all"])
    assert result2.exit_code == 0, result2.output
    assert "không có sự kiện nhập kho nào cần bổ sung" in result2.output


# --event-id backfill


def test_inventory_event_id_backfills():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Nguyên liệu", amount=150000,
            payment_source="Tiền mặt tại quầy",
        )

    result = _invoke(["repair-inventory", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "#" + str(eid) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_journal_entry(conn, eid) is not None


def test_inventory_event_id_not_found_is_noop():
    result = _invoke(["repair-inventory", "--event-id", "99999"])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện nhập kho nào cần bổ sung" in result.output


# --dry-run


def test_inventory_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Bao bì", amount=250000,
            payment_source="Tiền mặt tại quầy",
        )
        je_before = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries"
        ).fetchone()["c"]

    result = _invoke(["repair-inventory", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output
    assert "#" + str(eid) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries"
        ).fetchone()["c"]
        assert _expense_journal_entry(conn, eid) is None

    assert je_before == je_after


def test_inventory_dry_run_event_id():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Nguyên liệu", amount=100000,
            payment_source="Tiền mặt tại quầy",
        )

    result = _invoke(
        ["repair-inventory", "--event-id", str(eid), "--dry-run"]
    )
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_journal_entry(conn, eid) is None


# Non-inventory categories are excluded


def test_inventory_excludes_non_inventory_categories():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Vận chuyển", amount=100000,
            payment_source="Tiền mặt tại quầy",
        )

    result = _invoke(["repair-inventory", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện nhập kho nào cần bổ sung" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_journal_entry(conn, eid) is None


def test_inventory_mixed_categories_only_backfills_inventory():
    with get_db() as conn:
        ensure_schema(conn)
        eid1 = _insert_expense_event(
            conn, category="Nguyên liệu", amount=300000,
            payment_source="Tiền mặt tại quầy",
        )
        eid2 = _insert_expense_event(
            conn, category="Vận chuyển", amount=50000,
            payment_source="Tiền mặt tại quầy",
        )

    result = _invoke(["repair-inventory", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "#" + str(eid1) in result.output
    assert "#" + str(eid2) not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_journal_entry(conn, eid1) is not None
        assert _expense_journal_entry(conn, eid2) is None


# Deleted events are skipped


def test_inventory_skips_deleted_events():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Nguyên liệu", amount=400000,
            payment_source="Tiền mặt tại quầy",
        )
        conn.execute(
            "UPDATE events SET deleted_at = datetime('now') WHERE id = ?",
            (eid,),
        )

    result = _invoke(["repair-inventory", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện nhập kho nào cần bổ sung" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_journal_entry(conn, eid) is None


# Vietnamese labels


def test_inventory_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_expense_event(
            conn, category="Bao bì", amount=350000,
            payment_source="Tiền mặt tại quầy",
        )

    result = _invoke(["repair-inventory", "--all"])
    assert result.exit_code == 0, result.output
    assert "Sửa bút toán nhập kho (Hàng tồn kho 1300)" in result.output
    assert "Mã SK" in result.output
    assert "Danh mục" in result.output
    assert "Số tiền" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


# Service-level function tests


def test_process_inventory_backfill_service_level():
    from baker.commands.repair import (
        _expense_events_needing_inventory_backfill,
        _process_inventory_backfill,
    )
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Nguyên liệu", amount=150000,
            payment_source="Tiền mặt tại quầy",
        )
        events = _expense_events_needing_inventory_backfill(conn, event_id=eid)
        assert len(events) == 1
        assert events[0]["id"] == eid

        result = _process_inventory_backfill(conn, events[0], dry_run=False)
        assert result["action"] == "backfilled"
        assert _expense_journal_entry(conn, eid) is not None

        events_after = _expense_events_needing_inventory_backfill(
            conn, event_id=eid
        )
        assert len(events_after) == 0


def test_process_inventory_backfill_dry_run():
    from baker.commands.repair import (
        _expense_events_needing_inventory_backfill,
        _process_inventory_backfill,
    )
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Bao bì", amount=200000,
            payment_source="Tiền mặt tại quầy",
        )
        events = _expense_events_needing_inventory_backfill(conn, event_id=eid)
        assert len(events) == 1

        result = _process_inventory_backfill(conn, events[0], dry_run=True)
        assert result["action"] == "will-backfill"
        assert _expense_journal_entry(conn, eid) is None


# Verify backfill creates correct DR 1300 / CR payment account


def test_inventory_backfill_creates_1300_debit():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, category="Nguyên liệu", amount=500000,
            payment_source="Tiền mặt tại quầy",
        )

    _invoke(["repair-inventory", "--all"])

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_journal_entry(conn, eid)
        assert entry_id is not None

        inv_row = conn.execute(
            """
            SELECT jl.debit, jl.credit
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = '1300'
            """,
            (entry_id,),
        ).fetchone()
        assert inv_row is not None
        assert float(inv_row["debit"]) == 500000.0
        assert float(inv_row["credit"]) == 0.0

        cr_row = conn.execute(
            """
            SELECT jl.debit, jl.credit, a.code
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND jl.credit > 0
            """,
            (entry_id,),
        ).fetchone()
        assert cr_row is not None
        assert float(cr_row["credit"]) == 500000.0


# ---------------------------------------------------------------------------
# DG-301 Phase 3 — repair commands backfill past reconciliation sale orders
# (AC6: repair-order-revenue --all, repair-order-revenue --cogs --all,
#  repair-payment-journal --all backfill reconciliation orders that were
#  created before the journal sync fix and therefore have no journal entries)
# ---------------------------------------------------------------------------


def _submit_reconciliation_with_sale(api_client):
    """Submit a reconciliation with one sale row and return (order_id, txn_id).

    Uses the FastAPI test client so the full reconciliation flow (order,
    payment, stock decrement, journal sync) runs end-to-end. The journal
    entries created by Phase 1 are intentionally deleted by the caller to
    simulate a past reconciliation order created before the fix.
    """
    from baker.db.connection import get_db
    from baker.services.inventory_fifo import create_lot_with_items

    with get_db() as conn:
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', ?)
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (1, "true"),
        )
        # Reset and seed stock for product 1.
        conn.execute(
            "DELETE FROM inventory_items WHERE lot_id IN (SELECT id FROM stock_lots WHERE product_id = ?)",
            (1,),
        )
        conn.execute("DELETE FROM stock_lots WHERE product_id = ?", (1,))
        create_lot_with_items(conn, 1, None, 6)

    payload = {
        "staff_name": "An",
        "payment_method": "cash",
        "lines": [
            {
                "product_id": 1,
                "expected_qty": 6,
                "counted_qty": 4,
                "sale_qty": 2,
                "waste_qty": 0,
                "manual_unit_price": 12000,
            }
        ],
    }
    resp = api_client.post("/api/reconciliations/submit", json=payload)
    assert resp.status_code == 201, resp.text

    with get_db() as conn:
        order = conn.execute(
            "SELECT id, order_ref FROM orders ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert order is not None
        payment = conn.execute(
            "SELECT id FROM payment_transactions ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert payment is not None

    return int(order["id"]), str(order["order_ref"]), int(payment["id"])


def _delete_all_order_journal_entries(conn, order_id: int) -> None:
    """Delete every journal entry owned by an order (revenue + COGS) and the
    payment transaction's entry, simulating a pre-fix reconciliation order.

    Uses the cascade delete helper so reversal links and lines are cleaned up
    consistently, mirroring what a pre-fix DB would look like (no entries at
    all).
    """
    from baker.services.journal_sync import _delete_journal_entry_cascade

    rows = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE (source_type = 'order' AND source_id = ?) "
        "   OR (source_type = 'order_cogs' AND source_id = ?) "
        "   OR (source_type = 'payment_transaction' AND source_id IN "
        "       (SELECT id FROM payment_transactions WHERE order_id = ?))",
        (order_id, order_id, order_id),
    ).fetchall()
    for r in rows:
        _delete_journal_entry_cascade(conn, int(r["id"]))


def _journal_entry_ids(conn, order_id: int, txn_id: int) -> dict:
    """Return a map of source_type -> list of journal_entry ids for the order
    and its payment transaction. Used to assert before/after state."""
    result = {"order": [], "order_cogs": [], "payment_transaction": []}
    for source_type, source_id in (
        ("order", order_id),
        ("order_cogs", order_id),
        ("payment_transaction", txn_id),
    ):
        rows = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type = ? AND source_id = ? "
            "AND description NOT LIKE 'Reversal:%' ORDER BY id",
            (source_type, source_id),
        ).fetchall()
        result[source_type] = [int(r["id"]) for r in rows]
    return result


def _journal_line_codes(conn, entry_id: int) -> list[tuple[str, float, float]]:
    """Return [(account_code, debit, credit)] for a journal entry."""
    rows = conn.execute(
        "SELECT a.code, jl.debit, jl.credit "
        "FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id "
        "WHERE jl.journal_entry_id = ? ORDER BY a.code",
        (entry_id,),
    ).fetchall()
    return [(r["code"], float(r["debit"]), float(r["credit"])) for r in rows]


def test_repair_backfills_reconciliation_revenue_journal_entry(api_client):
    """AC6 (part 1): ``repair-order-revenue --all`` backfills the missing
    revenue journal entry (DR 2100 / CR 4100, source_type='order') for a
    past reconciliation sale order created before the journal sync fix."""
    order_id, order_ref, txn_id = _submit_reconciliation_with_sale(api_client)

    # Simulate a pre-fix reconciliation order: delete all journal entries
    # owned by the order (revenue + COGS) and its payment transaction.
    with get_db() as conn:
        ensure_schema(conn)
        _delete_all_order_journal_entries(conn, order_id)
        before = _journal_entry_ids(conn, order_id, txn_id)
        assert before["order"] == [], "precondition: revenue entry deleted"
        assert before["order_cogs"] == [], "precondition: COGS entry deleted"
        assert before["payment_transaction"] == [], "precondition: payment entry deleted"

    result = _invoke(["repair-order-revenue", "--all"])
    assert result.exit_code == 0, result.output
    # The revenue repair reports "đã sửa" (repaired + created counts).
    assert "đã sửa" in result.output
    assert order_ref in result.output

    with get_db() as conn:
        ensure_schema(conn)
        after = _journal_entry_ids(conn, order_id, txn_id)
        # Revenue entry was backfilled.
        assert len(after["order"]) == 1, f"revenue entry backfilled: {after['order']}"
        lines = _journal_line_codes(conn, after["order"][0])
        deposits_line = next(l for l in lines if l[0] == "2100")
        revenue_line = next(l for l in lines if l[0] == "4100")
        # DG-368: sale_qty=2 splits into 2 Orders (each qty=1). The helper
        # returns the last Order, whose revenue entry is 1 unit × 12000 = 12000
        # (the other Order keeps its own 12000 entry, untouched here).
        assert deposits_line[1] == 12000.0, deposits_line
        assert revenue_line[2] == 12000.0, revenue_line


def test_repair_backfills_reconciliation_cogs_journal_entry(api_client):
    """AC6 (part 2): ``repair-order-revenue --cogs --all`` backfills the
    missing COGS journal entry (DR 5900 / CR 1300, source_type='order_cogs')
    for a past reconciliation sale order created before the journal sync
    fix."""
    order_id, order_ref, txn_id = _submit_reconciliation_with_sale(api_client)

    with get_db() as conn:
        ensure_schema(conn)
        _delete_all_order_journal_entries(conn, order_id)
        before = _journal_entry_ids(conn, order_id, txn_id)
        assert before["order_cogs"] == [], "precondition: COGS entry deleted"

    result = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        after = _journal_entry_ids(conn, order_id, txn_id)
        assert len(after["order_cogs"]) == 1, f"COGS entry backfilled: {after['order_cogs']}"
        lines = _journal_line_codes(conn, after["order_cogs"][0])
        cogs_line = next(l for l in lines if l[0] == "5900")
        inv_line = next(l for l in lines if l[0] == "1300")
        assert cogs_line[1] > 0, cogs_line
        assert inv_line[2] == cogs_line[1], inv_line


def test_repair_backfills_reconciliation_payment_journal_entry(api_client):
    """AC6 (part 3): ``repair-payment-journal --all`` backfills the missing
    payment journal entry (DR Asset / CR 2100, source_type='payment_transaction')
    for a past reconciliation sale order created before the journal sync
    fix."""
    order_id, order_ref, txn_id = _submit_reconciliation_with_sale(api_client)

    with get_db() as conn:
        ensure_schema(conn)
        _delete_all_order_journal_entries(conn, order_id)
        before = _journal_entry_ids(conn, order_id, txn_id)
        assert before["payment_transaction"] == [], "precondition: payment entry deleted"

    result = _invoke(["repair-payment-journal", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "#" + str(txn_id) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        after = _journal_entry_ids(conn, order_id, txn_id)
        assert len(after["payment_transaction"]) == 1, (
            f"payment entry backfilled: {after['payment_transaction']}"
        )
        lines = _journal_line_codes(conn, after["payment_transaction"][0])
        # Cash method → asset account 1101 (Tiền mặt tại quầy, DG-330).
        asset_line = next(l for l in lines if l[0] == "1101")
        deposits_line = next(l for l in lines if l[0] == "2100")
        # DG-368: sale_qty=2 splits into 2 Orders (each qty=1). The helper
        # returns the last Order's payment, whose entry is 1 unit × 12000 = 12000
        # (the other Order keeps its own 12000 entry, untouched here).
        assert asset_line[1] == 12000.0, asset_line
        assert deposits_line[2] == 12000.0, deposits_line


def test_repair_backfills_all_reconciliation_journal_entries_idempotent(api_client):
    """AC6 (idempotency): running all three repair commands a second time is
    a no-op — the backfilled entries are detected as correct and skipped
    (revenue) or no transactions are found needing backfill (payment)."""
    order_id, order_ref, txn_id = _submit_reconciliation_with_sale(api_client)

    with get_db() as conn:
        ensure_schema(conn)
        _delete_all_order_journal_entries(conn, order_id)
        before = _journal_entry_ids(conn, order_id, txn_id)
        assert before["order"] == []
        assert before["order_cogs"] == []
        assert before["payment_transaction"] == []

    # First run — backfills all three entry types.
    r1 = _invoke(["repair-order-revenue", "--all"])
    assert r1.exit_code == 0, r1.output
    r2 = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert r2.exit_code == 0, r2.output
    r3 = _invoke(["repair-payment-journal", "--all"])
    assert r3.exit_code == 0, r3.output

    with get_db() as conn:
        ensure_schema(conn)
        after_first = _journal_entry_ids(conn, order_id, txn_id)
        assert len(after_first["order"]) == 1
        assert len(after_first["order_cogs"]) == 1
        assert len(after_first["payment_transaction"]) == 1

    # Second run — idempotent: revenue/COGS report "bỏ qua" (skipped) and
    # payment reports no transactions needing backfill.
    r1b = _invoke(["repair-order-revenue", "--all"])
    assert r1b.exit_code == 0, r1b.output
    r2b = _invoke(["repair-order-revenue", "--cogs", "--all"])
    assert r2b.exit_code == 0, r2b.output
    r3b = _invoke(["repair-payment-journal", "--all"])
    assert r3b.exit_code == 0, r3b.output

    with get_db() as conn:
        ensure_schema(conn)
        after_second = _journal_entry_ids(conn, order_id, txn_id)
        # No new entries created on the second run.
        assert after_second["order"] == after_first["order"]
        assert after_second["order_cogs"] == after_first["order_cogs"]
        assert after_second["payment_transaction"] == after_first["payment_transaction"]


# ---------------------------------------------------------------------------
# DG-356 Phase 2 — repair-order-revenue --shipping-release
# ---------------------------------------------------------------------------


def _insert_bus_order(
    conn,
    *,
    order_ref: str,
    customer_name: str = "Khách bus",
    total_price: float = 100000.0,
    status: str = "delivered",
    shipping_fee: float = 25000.0,
    delivery_type: str = "bus",
    due_date: str = "2026-07-15",
) -> int:
    """Insert a bus order with a shipping fee (helper for shipping-release tests)."""
    cur = conn.execute(
        "INSERT INTO orders "
        "(order_ref, customer_name, total_price, status, due_date, "
        " delivery_type, shipping_fee) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date, delivery_type, shipping_fee),
    )
    return int(cur.lastrowid)


def _pay_and_sync_bus(conn, *, order_id: int, amount: float) -> int:
    """Insert a cash deposit payment and run the payment journal sync.

    This credits 2200 with the shipping portion so ``_held_shipping_for_order``
    sees it as held, mirroring the real payment-time bus split.
    """
    from baker.services.journal_sync import _sync_payment_journal

    cur = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
        "VALUES (?, ?, 'deposit', 'cash', '')",
        (order_id, amount),
    )
    txn_id = int(cur.lastrowid)
    _sync_payment_journal(conn, txn_id, amount, "deposit", "cash", order_id=order_id)
    return txn_id


def _insert_cash_drawer(
    conn,
    *,
    opened_at: str,
    opening_balance: int = 0,
    status: str = "open",
) -> int:
    cur = conn.execute(
        "INSERT INTO cash_drawer "
        "(opened_at, opening_balance, status) "
        "VALUES (?, ?, ?)",
        (opened_at, int(opening_balance), status),
    )
    return int(cur.lastrowid)


def _shipping_release_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


def _delete_shipping_release_entry(conn, order_id: int) -> None:
    """Delete the order_shipping_release journal entry (and its lines) for setup.

    DG-366 Phase 3 made ``_sync_payment_journal`` re-trigger the shipping
    release for delivered/completed bus orders, so ``_pay_and_sync_bus`` now
    creates the release entry as a side effect. Tests that exercise the
    repair "backfill missing entry" path call this helper after setup to
    restore the pre-Phase-3 "missing release" state.
    """
    conn.execute(
        "DELETE FROM journal_lines WHERE journal_entry_id IN ("
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ?"
        ")",
        (order_id,),
    )
    conn.execute(
        "DELETE FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ?",
        (order_id,),
    )


def _shipping_release_lines(conn, order_id: int) -> dict[str, dict[str, float]]:
    """Return per-account debit/credit for the order's latest shipping release entry."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_shipping_release' AND je.source_id = ?
        ORDER BY je.id DESC, jl.id ASC
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def test_shipping_release_command_registered():
    """--shipping-release flag is registered and documented in --help."""
    result = _invoke(["repair-order-revenue", "--help"])
    assert result.exit_code == 0, result.output
    assert "--shipping-release" in result.output


def test_shipping_release_rejects_cogs_combo():
    """--shipping-release and --cogs are mutually exclusive."""
    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--cogs", "--all"]
    )
    assert result.exit_code != 0
    assert "không thể dùng" in result.output.lower() or "không" in result.output.lower()


def test_shipping_release_backfills_missing_entry_credit_1101_within_drawer():
    """AC4: bus order missing order_shipping_release, delivery within open drawer
    → entry created with CR 1101 (Cash in Drawer)."""
    with get_db() as conn:
        ensure_schema(conn)
        # Open drawer opened before the delivery event.
        _insert_cash_drawer(conn, opened_at="2026-07-14T00:00:00Z", opening_balance=0)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-1101", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # Seed a delivered event so _resolve_delivered_timestamp returns a
        # timestamp at/after the drawer's opened_at.
        conn.execute(
            "INSERT INTO events (type, order_id, timestamp, data, summary, staff_name) "
            "VALUES ('order', ?, '2026-07-15T08:00:00Z', ?, 'Giao đơn', 'Thử nghiệm')",
            (oid, f'{{"order_ref": "ORD-BUS-REL-1101", "to_status": "delivered"}}'),
        )
        # DG-366 Phase 3: _sync_payment_journal now creates the release entry
        # for delivered bus orders. Delete it to restore the "missing entry"
        # state the repair command must backfill.
        _delete_shipping_release_entry(conn, oid)
        assert _shipping_release_entry_count(conn, oid) == 0

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-REL-1101" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1
        lines = _shipping_release_lines(conn, oid)
        assert lines["2200"]["debit"] == 25000.0
        assert lines["1101"]["credit"] == 25000.0


def test_shipping_release_backfills_missing_entry_credit_1102_no_drawer():
    """AC5: bus order missing order_shipping_release, no open drawer
    → entry created with CR 1102 (Owner's Cash)."""
    with get_db() as conn:
        ensure_schema(conn)
        # No open drawer.
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-1102", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        conn.execute(
            "INSERT INTO events (type, order_id, timestamp, data, summary, staff_name) "
            "VALUES ('order', ?, '2026-07-15T08:00:00Z', ?, 'Giao đơn', 'Thử nghiệm')",
            (oid, f'{{"order_ref": "ORD-BUS-REL-1102", "to_status": "delivered"}}'),
        )
        # DG-366 Phase 3: _sync_payment_journal now creates the release entry.
        _delete_shipping_release_entry(conn, oid)
        assert _shipping_release_entry_count(conn, oid) == 0

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-REL-1102" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1
        lines = _shipping_release_lines(conn, oid)
        assert lines["2200"]["debit"] == 25000.0
        assert lines["1102"]["credit"] == 25000.0


def test_shipping_release_credit_1102_when_delivery_predates_drawer():
    """AC5 boundary: an open drawer exists but the order's delivery timestamp
    predates ``drawer.opened_at`` → credit 1102 (Owner's Cash), not 1101.

    Covers the second branch of ``_resolve_shipping_release_asset_account``
    (FR4): ``delivery_ts is not None and delivery_ts >= drawer.opened_at``
    is False because ``delivery_ts < drawer.opened_at``, so the release is
    routed to 1102 with no drawer link. Mirrors the AC5 no-drawer case but
    exercises the explicit predate comparison.
    """
    with get_db() as conn:
        ensure_schema(conn)
        # Open drawer opened AFTER the delivery event.
        _insert_cash_drawer(conn, opened_at="2026-07-16T00:00:00Z", opening_balance=0)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-PREDATE", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # Seed a delivered event BEFORE the drawer opened_at.
        conn.execute(
            "INSERT INTO events (type, order_id, timestamp, data, summary, staff_name) "
            "VALUES ('order', ?, '2026-07-15T08:00:00Z', ?, 'Giao đơn', 'Thử nghiệm')",
            (oid, f'{{"order_ref": "ORD-BUS-REL-PREDATE", "to_status": "delivered"}}'),
        )
        # DG-366 Phase 3: _sync_payment_journal now creates the release entry.
        _delete_shipping_release_entry(conn, oid)
        assert _shipping_release_entry_count(conn, oid) == 0

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-REL-PREDATE" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1
        lines = _shipping_release_lines(conn, oid)
        assert lines["2200"]["debit"] == 25000.0
        # FR4: delivery predates drawer → credit 1102 (Owner's Cash), not 1101.
        assert lines["1102"]["credit"] == 25000.0
        assert "1101" not in lines


def test_shipping_release_skips_existing_matching_entry_idempotent():
    """AC6: bus order already has a matching order_shipping_release → skipped."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-IDEM", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)

    # First repair creates the entry.
    r1 = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert r1.exit_code == 0, r1.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1
        first_entry_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchone()[0]

    # Second run — idempotent: skipped, no new entry.
    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "bỏ qua: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1
        second_entry_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        assert int(first_entry_id) == int(second_entry_id)


def test_shipping_release_reports_locked_and_does_not_modify():
    """AC7: bus order with a locked stale order_shipping_release entry →
    reported as locked, not modified."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-LOCK", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # DG-366 Phase 3: _sync_payment_journal now creates a correct release
        # entry. Remove it so only the manually-inserted stale locked entry
        # exists — the scenario this test exercises.
        _delete_shipping_release_entry(conn, oid)
        # Create a stale release entry (wrong amount) then lock it.
        held_acct = _account_id(conn, "2200")
        asset_acct = _account_id(conn, "1101")
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, 'order_shipping_release', ?)",
            (f"Shipping release: ORD-BUS-REL-LOCK", oid),
        )
        stale_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 10000.0, 0.0, 'Thanh toán ship bus')",
            (stale_id, held_acct),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, 10000.0, 'Tiền ship bus đã trả')",
            (stale_id, asset_acct),
        )
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (stale_id,),
        )

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "khoá: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # The locked entry is untouched (still 10000, not 25000).
        assert _shipping_release_entry_count(conn, oid) == 1
        lines = _shipping_release_lines(conn, oid)
        assert lines["2200"]["debit"] == 10000.0


def test_shipping_release_dry_run_does_not_mutate():
    """AC8: --dry-run previews the missing entry without writing."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-DRY", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # DG-366 Phase 3: _sync_payment_journal now creates the release entry.
        _delete_shipping_release_entry(conn, oid)
        assert _shipping_release_entry_count(conn, oid) == 0

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid), "--dry-run"]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-REL-DRY" in result.output
    assert "sẽ sửa" in result.output
    assert "đã sửa" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 0


def test_shipping_release_all_scans_bus_orders_only():
    """FR2/FR8: --all scans only bus orders with shipping_fee > 0; pickup/door
    orders are excluded and reported as not-applicable (not present)."""
    with get_db() as conn:
        ensure_schema(conn)
        bus_oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-ALL", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=bus_oid, amount=100000)
        # DG-366 Phase 3: _sync_payment_journal now creates the release entry
        # for the bus order. Remove it so the --all repair has a missing
        # entry to backfill (otherwise the bus order would be reported as
        # skipped and the test would no longer exercise the backfill path).
        _delete_shipping_release_entry(conn, bus_oid)
        # Pickup order with shipping_fee — must NOT be scanned.
        pickup_oid = _insert_bus_order(
            conn, order_ref="ORD-PICK-REL-ALL", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="pickup",
        )
        _pay_and_sync_bus(conn, order_id=pickup_oid, amount=100000)
        # Bus order with shipping_fee=0 — must NOT be scanned.
        zero_oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-ZERO", total_price=100000, shipping_fee=0,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=zero_oid, amount=100000)

    result = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-REL-ALL" in result.output
    # Pickup and zero-fee orders are excluded from the scan entirely.
    assert "ORD-PICK-REL-ALL" not in result.output
    assert "ORD-BUS-REL-ZERO" not in result.output
    assert "đã sửa: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, bus_oid) == 1
        assert _shipping_release_entry_count(conn, pickup_oid) == 0
        assert _shipping_release_entry_count(conn, zero_oid) == 0


def test_shipping_release_all_idempotent_second_run_all_skipped():
    """FR5/AC6: second --all run reports every scanned bus order as skipped."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-ALL2", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # DG-366 Phase 3: _sync_payment_journal now creates the release entry.
        # Remove it so the first --all run has a missing entry to backfill.
        _delete_shipping_release_entry(conn, oid)

    r1 = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert r1.exit_code == 0, r1.output
    assert "đã sửa: 1" in r1.output

    r2 = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "bỏ qua: 1" in r2.output
    assert "đã sửa: 0" in r2.output


def test_shipping_release_not_applicable_for_non_bus_order_id():
    """--order-id on a non-bus order reports not-applicable."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-DOOR-REL-NA", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "không áp dụng: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 0


def test_shipping_release_repair_stale_unlocked_entry():
    """A stale unlocked release entry is deleted and recreated with the
    correct amount (mirrors the sync code's unlocked-stale path)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-REL-STALE", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # DG-366 Phase 3: _sync_payment_journal now creates a correct release
        # entry. Remove it so only the manually-inserted stale unlocked
        # entry exists — the scenario this test exercises.
        _delete_shipping_release_entry(conn, oid)
        # Insert a stale (wrong-amount) unlocked release entry.
        held_acct = _account_id(conn, "2200")
        asset_acct = _account_id(conn, "1101")
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, 'order_shipping_release', ?)",
            (f"Shipping release: ORD-BUS-REL-STALE", oid),
        )
        stale_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 10000.0, 0.0, 'Thanh toán ship bus')",
            (stale_id, held_acct),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, 10000.0, 'Tiền ship bus đã trả')",
            (stale_id, asset_acct),
        )

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--order-id", str(oid)]
    )
    assert result.exit_code == 0, result.output
    assert "đã sửa: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1
        lines = _shipping_release_lines(conn, oid)
        assert lines["2200"]["debit"] == 25000.0


def test_shipping_release_repair_preserves_balanced_locked_reversal_chain():
    """A locked release plus its reversal is already balanced and is skipped."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-REL-CHAIN", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        held_acct = _account_id(conn, "2200")
        asset_acct = _account_id(conn, "1101")
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id, locked_at) "
            "VALUES (?, 'order_shipping_release', ?, CURRENT_TIMESTAMP)",
            ("Shipping release: ORD-REL-CHAIN", oid),
        )
        original_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 25000, 0, 'ship')", (original_id, held_acct)
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0, 25000, 'ship')", (original_id, asset_acct)
        )
        _replace_order_entry(conn, original_id, respect_locks=True)
        before = _shipping_release_entry_count(conn, oid)
        preview = _process_shipping_release_order(conn, oid, dry_run=True)
        assert preview["action"] == "skipped"
        result = _process_shipping_release_order(conn, oid, dry_run=False)
        assert result["action"] == "skipped"
        assert _shipping_release_entry_count(conn, oid) == before == 2


def test_shipping_release_repair_reverses_stale_locked_original():
    """A stale locked non-bus release is reversed, not left as locked/stale."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-REL-LOCKED-STALE", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        held_acct = _account_id(conn, "2200")
        asset_acct = _account_id(conn, "1101")
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id, locked_at) "
            "VALUES (?, 'order_shipping_release', ?, CURRENT_TIMESTAMP)",
            ("Shipping release: ORD-REL-LOCKED-STALE", oid),
        )
        entry_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) VALUES (?, ?, 10000, 0, 'ship')",
            (entry_id, held_acct),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) VALUES (?, ?, 0, 10000, 'ship')",
            (entry_id, asset_acct),
        )
        preview = _process_shipping_release_order(conn, oid, dry_run=True)
        assert preview["action"] == "will-repair"
        result = _process_shipping_release_order(conn, oid, dry_run=False)
        assert result["action"] == "repaired"
        assert _shipping_release_entry_count(conn, oid) == 2
        net = conn.execute(
            "SELECT COALESCE(SUM(jl.debit - jl.credit), 0) FROM journal_lines jl "
            "JOIN journal_entries je ON je.id = jl.journal_entry_id "
            "WHERE je.source_type = 'order_shipping_release' AND je.source_id = ? "
            "AND jl.account_id = ?",
            (oid, held_acct),
        ).fetchone()[0]
        assert float(net) == 0.0

# ---------------------------------------------------------------------------
# DG-366 Phase 5 — check-shipping-release-gaps (read-only detection, FR5/AC6)
# ---------------------------------------------------------------------------


def test_check_shipping_release_gaps_command_registered():
    """--help lists the command and documents it as read-only."""
    result = _invoke(["check-shipping-release-gaps", "--help"])
    assert result.exit_code == 0, result.output
    assert "chỉ đọc" in result.output.lower()


def test_check_shipping_release_gaps_finds_missing_release():
    """AC6: bus order with held 2200 but no order_shipping_release is reported."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-GAP-DET", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # Phase 3 auto-creates the release; delete it to restore the gap.
        _delete_shipping_release_entry(conn, oid)
        assert _shipping_release_entry_count(conn, oid) == 0
        # Sanity: held_in_2200 should be 25000 after the payment.
        from baker.services.journal_sync import _held_shipping_for_order
        assert _held_shipping_for_order(conn, oid) == 25000.0

    result = _invoke(["check-shipping-release-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-GAP-DET" in result.output
    assert "25.000" in result.output
    assert "Tổng: 1" in result.output


def test_check_shipping_release_gaps_read_only_no_mutation():
    """The detection query never mutates the database."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-GAP-RO", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        _delete_shipping_release_entry(conn, oid)

    with get_db() as conn:
        ensure_schema(conn)
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_before = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        o_before = conn.execute("SELECT COUNT(*) AS c FROM orders").fetchone()["c"]

    result = _invoke(["check-shipping-release-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-GAP-RO" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_after = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        o_after = conn.execute("SELECT COUNT(*) AS c FROM orders").fetchone()["c"]

    assert je_before == je_after
    assert jl_before == jl_after
    assert o_before == o_after


def test_check_shipping_release_gaps_empty_when_release_exists():
    """Bus order with held 2200 AND a matching release entry → not reported."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-GAP-OK", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        # Phase 3 creates the release — leave it in place (no gap).
        assert _shipping_release_entry_count(conn, oid) == 1

    result = _invoke(["check-shipping-release-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-GAP-OK" not in result.output
    assert "không có đơn ship bus nào" in result.output


def test_check_shipping_release_gaps_ignores_non_bus_orders():
    """Pickup/door orders are never reported (no shipping held in 2200)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-PICKUP-GAP", customer_name="Khách pickup",
            total_price=100000, status="delivered", due_date="2026-07-15",
        )
        _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")

    result = _invoke(["check-shipping-release-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-PICKUP-GAP" not in result.output
    assert "không có đơn ship bus nào" in result.output


def test_check_shipping_release_gaps_ignores_non_delivered_bus_orders():
    """Bus orders not yet delivered/completed are not reported."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-GAP-NEW", total_price=100000, shipping_fee=25000,
            status="new", due_date="2026-07-15",
        )
        _pay_and_sync_bus(conn, order_id=oid, amount=100000)
        _delete_shipping_release_entry(conn, oid)

    result = _invoke(["check-shipping-release-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-GAP-NEW" not in result.output
    assert "không có đơn ship bus nào" in result.output


def test_check_shipping_release_gaps_ignores_bus_order_with_no_held_shipping():
    """Bus order with no held 2200 (no payment) and no release → not reported
    (the AC6 gap requires held shipping in 2200)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-BUS-GAP-UNPAID", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15",
        )
        # No payment → no held shipping in 2200.
        assert _shipping_release_entry_count(conn, oid) == 0

    result = _invoke(["check-shipping-release-gaps"])
    assert result.exit_code == 0, result.output
    assert "ORD-BUS-GAP-UNPAID" not in result.output
    assert "không có đơn ship bus nào" in result.output


# ---------------------------------------------------------------------------
# DG-422 Phase 2 — scan-all stale bus-shipping accounting repair
# (FR5, NFR2, AC5)
# ---------------------------------------------------------------------------


def _insert_stale_shipping_release_entry(
    conn, *, order_id: int, amount: float = 25000.0
) -> int:
    """Insert a stale ``order_shipping_release`` entry for an order.

    Used to simulate the pre-Phase-1 state where a bus→non-bus delivery-type
    edit left a stale release entry behind (the scan-all repair target).
    """
    held_acct = _account_id(conn, "2200")
    asset_acct = _account_id(conn, "1101")
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order_shipping_release', ?)",
        (f"Shipping release: stale #{order_id}", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Thanh toán ship bus')",
        (entry_id, held_acct, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Tiền ship bus đã trả')",
        (entry_id, asset_acct, amount),
    )
    return entry_id


def test_scan_all_removes_stale_release_on_non_bus_order():
    """FR5/AC5: ``--all`` scans non-bus orders with a stale release entry and
    removes it (the bus→non-bus stale case from pre-Phase-1 delivery-type edits)."""
    with get_db() as conn:
        ensure_schema(conn)
        # A door order (formerly bus) that still carries a stale release entry.
        oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-REMOVED", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        _insert_stale_shipping_release_entry(conn, order_id=oid, amount=25000)
        assert _shipping_release_entry_count(conn, oid) == 1

    result = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-DG422-REMOVED" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 0


def test_scan_all_non_bus_stale_release_idempotent_second_run():
    """NFR2/AC5: after removing the stale release entry, a second ``--all``
    run does not rescan the non-bus order (no release entry → not in scan
    set → not reported at all)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-IDEM", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        _insert_stale_shipping_release_entry(conn, order_id=oid, amount=25000)

    # First run removes the stale entry.
    r1 = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert r1.exit_code == 0, r1.output
    assert "đã sửa" in r1.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 0

    # Second run: the non-bus order is no longer in the scan set (no release
    # entry → excluded by the scan query), so it is not reported at all.
    r2 = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "ORD-DG422-IDEM" not in r2.output


def test_scan_all_dry_run_does_not_remove_stale_release():
    """AC5: ``--all --dry-run`` previews the removal without writing."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-DRY", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        _insert_stale_shipping_release_entry(conn, order_id=oid, amount=25000)
        assert _shipping_release_entry_count(conn, oid) == 1

    result = _invoke(
        ["repair-order-revenue", "--shipping-release", "--all", "--dry-run"]
    )
    assert result.exit_code == 0, result.output
    assert "ORD-DG422-DRY" in result.output
    assert "sẽ sửa" in result.output
    assert "đã sửa" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 1


def test_scan_all_non_bus_stale_locked_release_is_reversed():
    """A stale locked non-bus release is reversed to restore a balanced chain."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-LOCK", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        entry_id = _insert_stale_shipping_release_entry(conn, order_id=oid, amount=25000)
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (entry_id,),
        )

    result = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, oid) == 2


def test_scan_all_bus_backfill_and_non_bus_removal_together():
    """FR5: ``--all`` handles both cases in one sweep — a bus order missing
    its release entry (backfill) and a non-bus order with a stale release
    entry (removal)."""
    with get_db() as conn:
        ensure_schema(conn)
        # Bus order missing release → backfill.
        bus_oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-BUS", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="bus",
        )
        _pay_and_sync_bus(conn, order_id=bus_oid, amount=100000)
        _delete_shipping_release_entry(conn, bus_oid)
        assert _shipping_release_entry_count(conn, bus_oid) == 0
        # Non-bus order with stale release → removal.
        door_oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-DOOR", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        _insert_stale_shipping_release_entry(conn, order_id=door_oid, amount=25000)
        assert _shipping_release_entry_count(conn, door_oid) == 1

    result = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-DG422-BUS" in result.output
    assert "ORD-DG422-DOOR" in result.output
    assert "đã sửa: 2" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _shipping_release_entry_count(conn, bus_oid) == 1
        assert _shipping_release_entry_count(conn, door_oid) == 0

    # Second run: both orders are now correct → bus order skipped, door order
    # excluded from scan. Only the bus order appears as "bỏ qua".
    r2 = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "ORD-DG422-BUS" in r2.output
    assert "bỏ qua: 1" in r2.output
    assert "đã sửa: 0" in r2.output


def test_scan_all_non_bus_order_without_release_not_scanned():
    """FR5: a non-bus order with no release entry is excluded from the scan
    (not reported as not-applicable — it is simply not in the scan set)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_bus_order(
            conn, order_ref="ORD-DG422-CLEAN", total_price=100000, shipping_fee=25000,
            status="delivered", due_date="2026-07-15", delivery_type="door",
        )
        # No payment, no release entry — clean door order.
        assert _shipping_release_entry_count(conn, oid) == 0

    result = _invoke(["repair-order-revenue", "--shipping-release", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-DG422-CLEAN" not in result.output
