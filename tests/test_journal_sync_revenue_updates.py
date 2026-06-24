"""Tests for DG-190 Phase 4.3 — update detection + refund handling in revenue
recognition.

Covers:

- ``PaymentTransaction.total_paid_net`` (deposits − tien_rut refunds)
- ``_sync_delivered_order_journal`` updates a stale revenue entry when the
  2100 debit no longer matches net deposits (payment correction scenario)
- Refund handling: a ``tien_rut`` on a delivered order reduces the 2100 debit
  to net deposits on re-sync
- Net deposits <= 0 (refunds >= deposits) → no revenue entry is created
- Idempotent: re-syncing an already-correct entry is a no-op
- ``_backfill_delivered_order_journal_entries`` reconciles stale entries against
  current net deposits
- Locked entries are reversed (not deleted) on update
"""

from baker.db.connection import get_db
from baker.db.schema import (
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    _backfill_delivered_order_journal_entries,
    ensure_schema,
)
from baker.models.payment_transaction import PaymentTransaction
from baker.services.journal_sync import (
    _delete_journal_entry_cascade,
    _sync_delivered_order_journal,
)


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
) -> int:
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, ?, ?, ?, '2026-06-10')",
        (order_ref, customer_name, total_price, status),
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
        "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
        "VALUES (?, ?, ?, ?, '')",
        (order_id, amount, ptype, method),
    )
    return int(cur.lastrowid)


def _insert_revenue_entry(
    conn,
    *,
    order_id: int,
    amount: float,
) -> int:
    """Insert a stale paid-order revenue entry debiting 2100 for `amount`."""
    deposits_acc = _account_id(conn, CUSTOMER_DEPOSITS_CODE)
    revenue_acc = _account_id(conn, ORDER_REVENUE_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order', ?)",
        (f"Order revenue: {order_id}", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Chuyển cọc sang doanh thu')",
        (entry_id, deposits_acc, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Doanh thu bán hàng')",
        (entry_id, revenue_acc, amount),
    )
    return entry_id


def _revenue_2100_debit(conn, order_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) AS debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = ?
        """,
        (order_id, CUSTOMER_DEPOSITS_CODE),
    ).fetchone()
    return float(row["debit"])


def _revenue_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type = 'order' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


# ---------------------------------------------------------------------------
# total_paid_net
# ---------------------------------------------------------------------------


def test_total_paid_net_deposits_minus_tien_rut():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-NET-100")
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_payment(conn, order_id=oid, amount=200000, ptype="tien_rut")
        assert PaymentTransaction.total_paid_excl_tien_rut(conn, oid) == 500000.0
        assert PaymentTransaction.total_tien_rut(conn, oid) == 200000.0
        assert PaymentTransaction.total_paid_net(conn, oid) == 300000.0


def test_total_paid_net_zero_when_no_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-NET-101")
        assert PaymentTransaction.total_paid_net(conn, oid) == 0.0


def test_total_paid_net_negative_when_refunds_exceed_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-NET-102")
        _insert_payment(conn, order_id=oid, amount=200000, ptype="deposit")
        _insert_payment(conn, order_id=oid, amount=500000, ptype="tien_rut")
        assert PaymentTransaction.total_paid_net(conn, oid) == -300000.0


# ---------------------------------------------------------------------------
# _sync_delivered_order_journal — update detection
# ---------------------------------------------------------------------------


def test_sync_updates_stale_revenue_entry_on_payment_correction():
    """Payment corrected: 700k deposit → 500k deposit; re-sync updates 2100 debit."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-UPD-200", total_price=700000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=700000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-UPD-200")
        assert _revenue_2100_debit(conn, oid) == 700000.0

        # Correct the payment: delete the 700k deposit, add a 500k deposit.
        conn.execute("DELETE FROM payment_transactions WHERE order_id = ?", (oid,))
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        # Re-sync should detect the stale 700k debit and update to 500k net.
        _sync_delivered_order_journal(conn, oid, "ORD-UPD-200")
        assert _revenue_2100_debit(conn, oid) == 500000.0
        assert _revenue_entry_count(conn, oid) == 1
        conn.commit()


def test_sync_idempotent_when_entry_matches_net_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-UPD-201", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-UPD-201")
        first_entry = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]

        # Re-sync should be a no-op — same entry id retained.
        _sync_delivered_order_journal(conn, oid, "ORD-UPD-201")
        second_entry = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        assert int(first_entry) == int(second_entry)
        assert _revenue_2100_debit(conn, oid) == 500000.0


def test_sync_recreates_after_external_stale_insert():
    """A stale entry inserted out-of-band is replaced on sync."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-UPD-202", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        # Insert a stale entry debiting 2100 for 900k.
        stale_id = _insert_revenue_entry(conn, order_id=oid, amount=900000)
        assert _revenue_2100_debit(conn, oid) == 900000.0

        _sync_delivered_order_journal(conn, oid, "ORD-UPD-202")
        assert _revenue_2100_debit(conn, oid) == 500000.0
        # Stale entry deleted; exactly one entry remains.
        remaining = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchall()
        assert len(remaining) == 1
        assert int(remaining[0][0]) != stale_id


# ---------------------------------------------------------------------------
# Refund (tien_rut) handling
# ---------------------------------------------------------------------------


def test_sync_refund_reduces_revenue_to_net_deposits():
    """500k deposit + 200k tien_rut → 2100 debit = 300k net."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-REF-300", total_price=700000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-REF-300")
        assert _revenue_2100_debit(conn, oid) == 500000.0

        # Issue a refund after delivery.
        _insert_payment(conn, order_id=oid, amount=200000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-REF-300")
        assert _revenue_2100_debit(conn, oid) == 300000.0


def test_sync_skips_revenue_when_net_deposits_zero_or_negative():
    """Refunds >= deposits → no revenue entry created."""
    with get_db() as conn:
        ensure_schema(conn)
        # Net exactly zero: 500k deposit + 500k tien_rut.
        oid_zero = _insert_order(
            conn, order_ref="ORD-REF-310", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid_zero, amount=500000, ptype="deposit")
        _insert_payment(conn, order_id=oid_zero, amount=500000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid_zero, "ORD-REF-310")
        assert _revenue_entry_count(conn, oid_zero) == 0

        # Net negative: 200k deposit + 500k tien_rut.
        oid_neg = _insert_order(
            conn, order_ref="ORD-REF-311", total_price=200000, status="delivered"
        )
        _insert_payment(conn, order_id=oid_neg, amount=200000, ptype="deposit")
        _insert_payment(conn, order_id=oid_neg, amount=500000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid_neg, "ORD-REF-311")
        assert _revenue_entry_count(conn, oid_neg) == 0


def test_sync_removes_revenue_entry_when_refund_drains_deposits():
    """Entry existed, then a refund brings net to 0 → entry is removed."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-REF-320", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-REF-320")
        assert _revenue_entry_count(conn, oid) == 1

        # Drain deposits with a full refund.
        _insert_payment(conn, order_id=oid, amount=500000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-REF-320")
        assert _revenue_entry_count(conn, oid) == 0


# ---------------------------------------------------------------------------
# Locked entry handling
# ---------------------------------------------------------------------------


def test_sync_reverses_locked_stale_entry():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-LCK-400", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-LCK-400")
        entry_id = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (entry_id,),
        )

        # Correct the payment; sync must reverse (not delete) the locked entry.
        conn.execute("DELETE FROM payment_transactions WHERE order_id = ?", (oid,))
        _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-LCK-400")

        # The locked original still exists; a reversal entry offsets it and a
        # new corrected entry was created (3 entries total). The net 2100
        # balance (debit − credit across all order entries) reflects 300k.
        entries = conn.execute(
            "SELECT id, locked_at FROM journal_entries "
            "WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchall()
        assert len(entries) == 3
        net2100 = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS net
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = ?
            """,
            (oid, CUSTOMER_DEPOSITS_CODE),
        ).fetchone()["net"]
        assert float(net2100) == 300000.0


# ---------------------------------------------------------------------------
# Backfill reconciliation
# ---------------------------------------------------------------------------


def test_backfill_reconciles_stale_revenue_to_net_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BF-500", total_price=700000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_payment(conn, order_id=oid, amount=200000, ptype="tien_rut")
        # Stale entry debiting 700k (the old gross, ignoring the refund).
        _insert_revenue_entry(conn, order_id=oid, amount=700000)
        assert _revenue_2100_debit(conn, oid) == 700000.0

        _backfill_delivered_order_journal_entries(conn)
        # Net = 500k − 200k = 300k.
        assert _revenue_2100_debit(conn, oid) == 300000.0
        assert _revenue_entry_count(conn, oid) == 1
        conn.commit()


def test_backfill_skips_already_correct_entries():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BF-501", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-BF-501")
        entry_id_before = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]

        _backfill_delivered_order_journal_entries(conn)
        entry_id_after = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        assert int(entry_id_before) == int(entry_id_after)