"""Tests for ``baker repair-deposit-balance`` — DG-233 Phase 6.

Covers FR6/AC6/AC7/AC9:

- ``--order-id`` repairs a single cancelled order with orphaned deposits
- ``--order-id`` repairs a delivered order with negative 2100 balance
- ``--all`` repairs all affected orders
- ``--dry-run`` shows planned actions without mutating
- Idempotency (AC7): second run reports no orders to repair
- Already-correct order is not flagged
- Locked entries are reversed rather than deleted
- VN labels (AC9)
- Command registration / --help
"""

import click.testing

from baker.cli import app
from baker.commands.repair import _process_deposit_balance_order
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0]
    )


def _insert_order(
    conn,
    *,
    order_ref: str,
    customer_name: str = "Khách thử",
    total_price: float = 500000.0,
    status: str = "delivered",
    due_date: str | None = "2026-06-10",
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
) -> int:
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date,"
        " delivery_type, shipping_fee) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date, delivery_type, shipping_fee),
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


def _deposit_2100_balance(conn, order_id: int) -> dict:
    """Return per-order 2100 net balance (mirrors validation check)."""
    deposits_code = "2100"
    row = conn.execute(
        """
        SELECT o.id,
               COALESCE((
                   SELECT SUM(jl.credit - jl.debit)
                   FROM payment_transactions pt
                   JOIN journal_entries je ON je.source_type = 'payment_transaction'
                     AND je.source_id = pt.id
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE pt.order_id = o.id
                     AND (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
               ), 0) AS pt_net,
               COALESCE((
                   SELECT SUM(jl.debit)
                   FROM journal_entries je
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE je.source_type = 'order' AND je.source_id = o.id
                     AND je.description NOT LIKE 'Reversal:%'
               ), 0) AS rev_debit,
               COALESCE((
                   SELECT SUM(jl.debit)
                   FROM journal_entries je
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE je.source_type = 'order_shipping_hold'
                     AND je.source_id = o.id
               ), 0) AS ship_debit
        FROM orders o
        WHERE o.id = ?
        """,
        (deposits_code, deposits_code, deposits_code, order_id),
    ).fetchone()
    if row is None:
        return {"pt_net": 0.0, "rev_debit": 0.0, "ship_debit": 0.0, "net": 0.0}
    pt_net = float(row["pt_net"])
    rev_debit = float(row["rev_debit"])
    ship_debit = float(row["ship_debit"])
    return {
        "pt_net": pt_net,
        "rev_debit": rev_debit,
        "ship_debit": ship_debit,
        "net": pt_net - rev_debit - ship_debit,
    }


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_deposit_balance_command_registered():
    result = _invoke(["repair-deposit-balance", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_deposit_balance_requires_one_mode():
    result = _invoke(["repair-deposit-balance"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_deposit_balance_rejects_both_modes():
    result = _invoke(["repair-deposit-balance", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# Cancelled order with orphaned deposits
# ---------------------------------------------------------------------------


def test_repair_cancelled_order_with_orphaned_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-001", customer_name="Anh H",
            total_price=500000, status="cancelled",
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, txn_id, 500000, "deposit", "cash", order_id=oid)

        bal = _deposit_2100_balance(conn, oid)
        assert bal["pt_net"] == 500000.0
        assert bal["net"] == 500000.0

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "ORD-260707-001" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert bal["pt_net"] == 0.0
        assert bal["net"] == 0.0


def test_repair_cancelled_order_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-002", customer_name="Anh D",
            total_price=300000, status="cancelled",
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, txn_id, 300000, "deposit", "cash", order_id=oid)

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "ORD-260707-002" in result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert bal["pt_net"] == 300000.0
        assert bal["net"] == 300000.0


def test_repair_deposit_balance_cancelled_order_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-003", customer_name="Anh I",
            total_price=200000, status="cancelled",
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=200000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, txn_id, 200000, "deposit", "cash", order_id=oid)

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào" in result.output


# ---------------------------------------------------------------------------
# Delivered order with negative 2100 balance (stale revenue entry)
# ---------------------------------------------------------------------------


def test_repair_delivered_order_negative_balance():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260710-010", customer_name="Anh N",
            total_price=300000, status="delivered",
        )
        # Only 100k deposit, but revenue entry recorded 300k debit on 2100
        _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        # Need to sync the payment journal entry first for deposit to show up
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 100000, "deposit", "cash", order_id=oid)

        # Insert a stale revenue entry with 300k debit (only 100k deposited)
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=300000,
        )

        bal = _deposit_2100_balance(conn, oid)
        assert bal["pt_net"] == 100000.0
        assert bal["rev_debit"] == 300000.0
        assert bal["net"] == -200000.0  # negative balance

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "ORD-260710-010" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert bal["pt_net"] == 100000.0
        # After reconcile, rev_debit should match pt_net within tolerance
        assert abs(bal["rev_debit"] - 100000.0) <= 0.01
        assert abs(bal["net"]) <= 0.01


def test_repair_delivered_negative_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260710-011", customer_name="Anh D",
            total_price=400000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=200000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 200000, "deposit", "cash", order_id=oid)
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=400000,
        )

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "ORD-260710-011" in result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert bal["rev_debit"] == 400000.0


def test_repair_delivered_negative_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260710-012", customer_name="Anh I",
            total_price=250000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=150000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 150000, "deposit", "cash", order_id=oid)
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=250000,
        )

    # First run
    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    # Second run
    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào" in result.output


# ---------------------------------------------------------------------------
# --all mode
# ---------------------------------------------------------------------------


def test_repair_deposit_balance_all_repairs_multiple():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")

        # Order 1: cancelled with orphaned deposits
        oid1 = _insert_order(
            conn, order_ref="ORD-260707-A01", customer_name="Khách 1",
            total_price=300000, status="cancelled",
        )
        _insert_payment(conn, order_id=oid1, amount=300000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 300000, "deposit", "cash", order_id=oid1)

        # Order 2: delivered with negative balance
        oid2 = _insert_order(
            conn, order_ref="ORD-260710-A02", customer_name="Khách 2",
            total_price=500000, status="delivered",
        )
        _insert_payment(conn, order_id=oid2, amount=200000, ptype="deposit")
        _sync_payment_journal(conn, 2, 200000, "deposit", "cash", order_id=oid2)
        _insert_revenue_entry(
            conn, order_id=oid2, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )

    result = _invoke(["repair-deposit-balance", "--all"])
    assert result.exit_code == 0, result.output
    assert "ORD-260707-A01" in result.output
    assert "ORD-260710-A02" in result.output
    assert "đã sửa: 2" in result.output

    # Verify both orders now have clean balances
    with get_db() as conn:
        ensure_schema(conn)
        b1 = _deposit_2100_balance(conn, oid1)
        assert abs(b1["net"]) <= 0.01
        b2 = _deposit_2100_balance(conn, oid2)
        assert abs(b2["net"]) <= 0.01


def test_repair_deposit_balance_all_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")

        oid1 = _insert_order(
            conn, order_ref="ORD-260707-A03", customer_name="Khách 3",
            total_price=400000, status="cancelled",
        )
        _insert_payment(conn, order_id=oid1, amount=400000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 400000, "deposit", "cash", order_id=oid1)

        oid2 = _insert_order(
            conn, order_ref="ORD-260710-A04", customer_name="Khách 4",
            total_price=350000, status="delivered",
        )
        _insert_payment(conn, order_id=oid2, amount=100000, ptype="deposit")
        _sync_payment_journal(conn, 2, 100000, "deposit", "cash", order_id=oid2)
        _insert_revenue_entry(
            conn, order_id=oid2, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=350000,
        )

    # First run fixes both
    result = _invoke(["repair-deposit-balance", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa: 2" in result.output

    # Second run finds nothing
    result = _invoke(["repair-deposit-balance", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào" in result.output


def test_repair_deposit_balance_all_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(
            conn, order_ref="ORD-260707-A05", customer_name="Khách 5",
            total_price=500000, status="cancelled",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 500000, "deposit", "cash", order_id=oid1)

    result = _invoke(["repair-deposit-balance", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "ORD-260707-A05" in result.output
    assert "sẽ sửa: 1" in result.output

    # Dry-run should not mutate
    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid1)
        assert bal["pt_net"] == 500000.0


# ---------------------------------------------------------------------------
# Already-correct order is not flagged
# ---------------------------------------------------------------------------


def test_deposit_balance_correct_order_not_flagged():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260710-020", customer_name="Anh C",
            total_price=200000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=200000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 200000, "deposit", "cash", order_id=oid)
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=200000,
        )

    result = _invoke(["repair-deposit-balance", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào" in result.output


# ---------------------------------------------------------------------------
# VN labels
# ---------------------------------------------------------------------------


def test_deposit_balance_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        asset_acc = _account_id(conn, "1100")
        oid = _insert_order(
            conn, order_ref="ORD-260707-VN1", customer_name="Anh V",
            total_price=400000, status="cancelled",
        )
        _insert_payment(conn, order_id=oid, amount=400000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 400000, "deposit", "cash", order_id=oid)

    result = _invoke(["repair-deposit-balance", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "Sửa số dư cọc khách hàng (2100)" in result.output
    assert "Mã đơn" in result.output
    assert "Trạng thái" in result.output
    assert "Cọc vào" in result.output
    assert "Đã ghi nhận" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


def test_deposit_balance_vn_labels_empty():
    result = _invoke(["repair-deposit-balance", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào cần sửa số dư cọc" in result.output


# ---------------------------------------------------------------------------
# Service-level function tests
# ---------------------------------------------------------------------------


def test_process_deposit_balance_cancelled_order():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-S01", customer_name="SV Test",
            total_price=300000, status="cancelled",
        )
        _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 300000, "deposit", "cash", order_id=oid)

        result = _process_deposit_balance_order(conn, oid, dry_run=False)
        assert result["action"] == "repaired"
        assert result["deposits_in"] == 300000.0
        assert result["status"] == "cancelled"

        conn.commit()

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert abs(bal["net"]) <= 0.01


def test_process_deposit_balance_delivered_order():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        oid = _insert_order(
            conn, order_ref="ORD-260710-S02", customer_name="SV Test",
            total_price=400000, status="delivered",
        )
        _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 100000, "deposit", "cash", order_id=oid)
        _insert_revenue_entry(
            conn, order_id=oid, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=400000,
        )

        result = _process_deposit_balance_order(conn, oid, dry_run=False)
        assert result["action"] == "repaired"
        assert result["status"] == "delivered"

        conn.commit()

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert abs(bal["net"]) <= 0.01
        assert abs(bal["rev_debit"] - 100000.0) <= 0.01


def test_process_deposit_balance_dry_run():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-S03", customer_name="SV Test",
            total_price=500000, status="cancelled",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal
        _sync_payment_journal(conn, 1, 500000, "deposit", "cash", order_id=oid)

        result = _process_deposit_balance_order(conn, oid, dry_run=True)
        assert result["action"] == "will-repair"
        assert result["deposits_in"] == 500000.0


def test_process_deposit_balance_not_applicable():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-S04", customer_name="SV Test",
            total_price=200000, status="cancelled",
        )

        result = _process_deposit_balance_order(conn, oid, dry_run=False)
        assert result["action"] == "not-applicable"
        assert result["deposits_in"] == 0.0


def test_process_deposit_balance_nonexistent_order():
    with get_db() as conn:
        ensure_schema(conn)

        result = _process_deposit_balance_order(conn, 99999, dry_run=False)
        assert result["action"] == "not-applicable"


def test_process_deposit_balance_locked_payment():
    from baker.services.journal_sync import _sync_payment_journal

    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260707-L01", customer_name="Khách L",
            total_price=500000, status="cancelled",
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_payment_journal(conn, txn_id, 500000, "deposit", "cash", order_id=oid)

        # Lock the journal entry
        conn.execute(
            "UPDATE journal_entries SET locked_at = datetime('now') "
            "WHERE source_type = 'payment_transaction' AND source_id = ?",
            (txn_id,),
        )

        bal = _deposit_2100_balance(conn, oid)
        assert bal["pt_net"] == 500000.0

        result = _process_deposit_balance_order(conn, oid, dry_run=False)
        assert result["action"] == "repaired"

        conn.commit()

    with get_db() as conn:
        ensure_schema(conn)
        bal = _deposit_2100_balance(conn, oid)
        assert abs(bal["net"]) <= 0.01
