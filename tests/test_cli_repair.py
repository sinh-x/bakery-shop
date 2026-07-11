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
from baker.commands.repair import _vn_amount
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


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