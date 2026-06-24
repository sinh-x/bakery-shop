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
    BUS_SHIPPING_HELD_CODE,
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
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
) -> int:
    cur = conn.execute(
        "INSERT INTO orders "
        "(order_ref, customer_name, total_price, status, due_date, "
        " delivery_type, shipping_fee) "
        "VALUES (?, ?, ?, ?, '2026-06-10', ?, ?)",
        (order_ref, customer_name, total_price, status, delivery_type, shipping_fee),
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
        assert PaymentTransaction.total_paid_excl_outflows(conn, oid) == 500000.0
        assert PaymentTransaction.total_outflows(conn, oid) == 200000.0
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


# ---------------------------------------------------------------------------
# DG-191 Phase 3 — Bus shipping revenue exclusion + shipping release (FR3/FR4)
# ---------------------------------------------------------------------------


def _revenue_4100_credit(conn, order_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.credit), 0) AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = ?
        """,
        (order_id, ORDER_REVENUE_CODE),
    ).fetchone()
    return float(row["credit"])


def _release_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'order_shipping_release' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


def _release_line_amounts(conn, order_id: int) -> dict[str, dict[str, float]]:
    """Return per-account debit/credit for the order's shipping release entry."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_shipping_release' AND je.source_id = ?
        ORDER BY je.id DESC
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _pay_and_sync(
    conn,
    *,
    order_id: int,
    amount: float,
) -> int:
    """Insert a deposit payment and run the payment journal sync (bus split)."""
    from baker.services.journal_sync import _sync_payment_journal

    txn_id = _insert_payment(conn, order_id=order_id, amount=amount, ptype="deposit")
    _sync_payment_journal(conn, txn_id, amount, "deposit", "cash", order_id=order_id)
    return txn_id


def test_bus_order_revenue_excludes_shipping_fee_ac3():
    """AC3: net=100000, shipping_fee=25000 → revenue entry 2100/4100 = 75000."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-AC3",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-AC3")
        assert _revenue_2100_debit(conn, oid) == 75000.0
        assert _revenue_4100_credit(conn, oid) == 75000.0
        assert _revenue_entry_count(conn, oid) == 1


def test_bus_order_shipping_release_entry_created_ac4():
    """AC4: shipping_fee=25000 held in 2200 → release entry debit 2200/credit 1100."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-AC4",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-AC4")
        assert _release_entry_count(conn, oid) == 1
        lines = _release_line_amounts(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        assert lines["1100"]["credit"] == 25000.0


def test_bus_order_shipping_fee_zero_unchanged():
    """Bus order with shipping_fee=0: no exclusion, no release entry."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-FEE0",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=0,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-FEE0")
        assert _revenue_2100_debit(conn, oid) == 100000.0
        assert _revenue_4100_credit(conn, oid) == 100000.0
        assert _release_entry_count(conn, oid) == 0


def test_pickup_order_revenue_unchanged():
    """Pickup order: no exclusion, no release entry."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-PICKUP-RV",
            total_price=100000,
            status="delivered",
            delivery_type="pickup",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)

        _sync_delivered_order_journal(conn, oid, "ORD-PICKUP-RV")
        assert _revenue_2100_debit(conn, oid) == 100000.0
        assert _release_entry_count(conn, oid) == 0


def test_door_order_revenue_unchanged():
    """Door order: no exclusion, no release entry."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DOOR-RV",
            total_price=100000,
            status="delivered",
            delivery_type="door",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)

        _sync_delivered_order_journal(conn, oid, "ORD-DOOR-RV")
        assert _revenue_2100_debit(conn, oid) == 100000.0
        assert _release_entry_count(conn, oid) == 0


def test_bus_order_net_equals_shipping_no_revenue_entry():
    """net=25000, shipping_fee=25000 → revenue=0, no revenue entry created."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-EQ",
            total_price=25000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=25000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-EQ")
        assert _revenue_entry_count(conn, oid) == 0
        # Release still happens: held 25000 released to 1100.
        assert _release_entry_count(conn, oid) == 1
        lines = _release_line_amounts(conn, oid)
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0


def test_bus_order_revenue_partial_after_shipping_excluded():
    """net=30000, shipping_fee=25000 → revenue=5000."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-PART",
            total_price=30000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=30000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-PART")
        assert _revenue_2100_debit(conn, oid) == 5000.0
        assert _revenue_4100_credit(conn, oid) == 5000.0


def test_bus_order_release_idempotent_when_matches():
    """Re-syncing a matching release entry is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-IDEM",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-IDEM")
        first_count = _release_entry_count(conn, oid)
        first_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchone()[0]

        # Re-sync should be a no-op.
        _sync_delivered_order_journal(conn, oid, "ORD-BUS-IDEM")
        assert _release_entry_count(conn, oid) == first_count
        second_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        assert int(first_id) == int(second_id)


def test_bus_order_release_reverses_locked_stale_entry():
    """Locked stale release entry is reversed; a new corrected entry is created."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-LOCK",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)
        _sync_delivered_order_journal(conn, oid, "ORD-BUS-LOCK")
        release_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (release_id,),
        )

        # Increase the held shipping by adding another deposit so the release
        # amount changes — but here we instead change shipping_fee upward to
        # force a mismatch. Re-pay is not needed; instead edit shipping_fee.
        conn.execute(
            "UPDATE orders SET shipping_fee = 30000 WHERE id = ?", (oid,)
        )
        # Add an extra deposit to cover the additional shipping in 2200.
        _pay_and_sync(conn, order_id=oid, amount=30000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-LOCK")
        # The locked original still exists; a reversal offsets it and a new
        # corrected entry was created (3 entries total).
        entries = conn.execute(
            "SELECT id, locked_at FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchall()
        assert len(entries) == 3


def test_bus_order_release_deletes_stale_unlocked_entry():
    """Stale unlocked release entry is deleted; a new one is created."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BUS-STALE",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        _pay_and_sync(conn, order_id=oid, amount=100000)
        _sync_delivered_order_journal(conn, oid, "ORD-BUS-STALE")
        stale_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchone()[0]

        # Change shipping_fee and re-pay so release amount differs.
        conn.execute(
            "UPDATE orders SET shipping_fee = 30000 WHERE id = ?", (oid,)
        )
        _pay_and_sync(conn, order_id=oid, amount=30000)

        _sync_delivered_order_journal(conn, oid, "ORD-BUS-STALE")
        remaining = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (oid,),
        ).fetchall()
        assert len(remaining) == 1
        assert int(remaining[0][0]) != stale_id


# ---------------------------------------------------------------------------
# DG-191 Phase 5 — Bus shipping backfill migration (FR5, NFR2)
# ---------------------------------------------------------------------------


def _hold_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'order_shipping_hold' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


def _hold_line_amounts(conn, order_id: int) -> dict[str, dict[str, float]]:
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_shipping_hold' AND je.source_id = ?
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _seed_stale_bus_order(
    conn,
    *,
    order_ref: str,
    shipping_fee: float,
    deposit: float,
    total_price: float = 100000.0,
    delivery_type: str = "bus",
) -> int:
    """Seed a delivered bus order with a stale revenue entry (pre-Phase-3 style).

    The revenue entry debits 2100 / credits 4100 for the full deposit, i.e. it
    *includes* the shipping fee — exactly the state the v49 backfill must fix.
    No payment-time 2100/2200 split and no hold/release entries exist.
    """
    oid = _insert_order(
        conn,
        order_ref=order_ref,
        total_price=total_price,
        status="delivered",
        delivery_type=delivery_type,
        shipping_fee=shipping_fee,
    )
    _insert_payment(conn, order_id=oid, amount=deposit, ptype="deposit")
    _insert_revenue_entry(conn, order_id=oid, amount=deposit)
    return oid


def _assert_double_entry_integrity_v49(conn) -> None:
    rows = conn.execute(
        """
        SELECT je.id, SUM(jl.debit) AS total_debit, SUM(jl.credit) AS total_credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        GROUP BY je.id
        """
    ).fetchall()
    assert len(rows) > 0, "No journal entries to verify"
    for row in rows:
        delta = abs(float(row["total_debit"]) - float(row["total_credit"]))
        assert delta < 0.005, (
            f"Entry {row['id']}: debit {row['total_debit']} != credit {row['total_credit']}"
        )


def test_v49_backfill_corrects_revenue_creates_hold_and_release():
    """AC5: stale revenue (100000→4100) → corrected to 75000, hold+release created."""
    from baker.db.schema import _migrate_v49_bus_shipping_backfill

    with get_db() as conn:
        ensure_schema(conn)
        oid = _seed_stale_bus_order(
            conn,
            order_ref="ORD-BF-V49-1",
            shipping_fee=25000,
            deposit=100000,
        )
        # Pre-conditions: stale state.
        assert _revenue_2100_debit(conn, oid) == 100000.0
        assert _hold_entry_count(conn, oid) == 0
        assert _release_entry_count(conn, oid) == 0

        _migrate_v49_bus_shipping_backfill(conn)

        # Revenue corrected to net − shipping = 100000 − 25000 = 75000.
        assert _revenue_2100_debit(conn, oid) == 75000.0
        assert _revenue_4100_credit(conn, oid) == 75000.0
        assert _revenue_entry_count(conn, oid) == 1

        # Hold entry: debit 2100 25000, credit 2200 25000.
        assert _hold_entry_count(conn, oid) == 1
        hold = _hold_line_amounts(conn, oid)
        assert hold[CUSTOMER_DEPOSITS_CODE]["debit"] == 25000.0
        assert hold[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0

        # Release entry: debit 2200 25000, credit 1100 25000.
        assert _release_entry_count(conn, oid) == 1
        release = _release_line_amounts(conn, oid)
        assert release[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        assert release["1100"]["credit"] == 25000.0

        _assert_double_entry_integrity_v49(conn)
        conn.commit()


def test_v49_backfill_is_idempotent():
    """NFR2: running the backfill twice produces no duplicate entries."""
    from baker.db.schema import _migrate_v49_bus_shipping_backfill

    with get_db() as conn:
        ensure_schema(conn)
        oid = _seed_stale_bus_order(
            conn,
            order_ref="ORD-BF-V49-2",
            shipping_fee=25000,
            deposit=100000,
        )
        _migrate_v49_bus_shipping_backfill(conn)
        rev_after_1 = _revenue_entry_count(conn, oid)
        hold_after_1 = _hold_entry_count(conn, oid)
        rel_after_1 = _release_entry_count(conn, oid)

        _migrate_v49_bus_shipping_backfill(conn)
        assert _revenue_entry_count(conn, oid) == rev_after_1
        assert _hold_entry_count(conn, oid) == hold_after_1
        assert _release_entry_count(conn, oid) == rel_after_1
        assert _revenue_2100_debit(conn, oid) == 75000.0
        _assert_double_entry_integrity_v49(conn)
        conn.commit()


def test_v49_backfill_skips_non_bus_orders():
    """FR7: a delivered door/pickup order is untouched by the bus backfill."""
    from baker.db.schema import _migrate_v49_bus_shipping_backfill

    with get_db() as conn:
        ensure_schema(conn)
        oid = _seed_stale_bus_order(
            conn,
            order_ref="ORD-BF-V49-3",
            shipping_fee=20000,
            deposit=100000,
            delivery_type="door",
        )
        assert _revenue_2100_debit(conn, oid) == 100000.0

        _migrate_v49_bus_shipping_backfill(conn)

        assert _revenue_2100_debit(conn, oid) == 100000.0
        assert _hold_entry_count(conn, oid) == 0
        assert _release_entry_count(conn, oid) == 0
        conn.commit()


def test_v49_backfill_skips_bus_order_with_zero_shipping_fee():
    """Bus order with shipping_fee=0 is skipped (nothing to hold/release)."""
    from baker.db.schema import _migrate_v49_bus_shipping_backfill

    with get_db() as conn:
        ensure_schema(conn)
        oid = _seed_stale_bus_order(
            conn,
            order_ref="ORD-BF-V49-4",
            shipping_fee=0,
            deposit=100000,
        )
        _migrate_v49_bus_shipping_backfill(conn)
        assert _revenue_2100_debit(conn, oid) == 100000.0
        assert _hold_entry_count(conn, oid) == 0
        assert _release_entry_count(conn, oid) == 0
        conn.commit()


def test_v49_backfill_skips_order_already_has_hold_and_release():
    """Idempotent when hold+release entries already exist (post-Phase-3 order)."""
    from baker.db.schema import _migrate_v49_bus_shipping_backfill

    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-BF-V49-5",
            total_price=100000,
            status="delivered",
            delivery_type="bus",
            shipping_fee=25000,
        )
        # Payment-time split + live delivery sync (the Phase 2/3 path).
        _pay_and_sync(conn, order_id=oid, amount=100000)
        _sync_delivered_order_journal(conn, oid, "ORD-BF-V49-5")
        assert _release_entry_count(conn, oid) == 1
        rev_before = _revenue_entry_count(conn, oid)
        rel_before = _release_entry_count(conn, oid)

        _migrate_v49_bus_shipping_backfill(conn)

        # Revenue already excludes shipping — no duplicate revenue entry.
        assert _revenue_entry_count(conn, oid) == rev_before
        assert _release_entry_count(conn, oid) == rel_before
        assert _revenue_2100_debit(conn, oid) == 75000.0
        # The live path already holds shipping in 2200 via the payment-time
        # split (payment_transaction entries). The backfill must NOT create a
        # redundant order_shipping_hold entry — that would double-hold the
        # shipping. No order_shipping_hold entry is expected here.
        assert _hold_entry_count(conn, oid) == 0
        # A second run remains a no-op (idempotent).
        _migrate_v49_bus_shipping_backfill(conn)
        assert _hold_entry_count(conn, oid) == 0
        assert _release_entry_count(conn, oid) == rel_before
        _assert_double_entry_integrity_v49(conn)
        conn.commit()