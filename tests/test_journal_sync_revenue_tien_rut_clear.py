"""Tests for DG-198 Phase 4 — revenue entry clears 2400 (Tien Rut Held) at
delivery (FR3, AC3).

Covers:

- Order with deposits + tien_rut, delivered → revenue entry debits 2100 (full
  deposit balance), credits 2400 (tien_rut held), credits 4100 (net revenue).
- Order with deposits == tien_rut (net = 0) → revenue entry still created with
  debit 2100 == credit 2400, credit 4100 == 0 (omitted).
- Order with deposits and no tien_rut → unchanged single-line 2100/4100 entry.
- _held_tien_rut_for_order returns the net 2400 balance for the order.
- Double-entry integrity holds for every revenue entry.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    TIEN_RUT_HELD_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _held_tien_rut_for_order,
    _sync_delivered_order_journal,
    _sync_payment_journal,
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


def _pay_and_sync(
    conn,
    *,
    order_id: int,
    amount: float,
    ptype: str = "deposit",
) -> int:
    """Insert a payment and run the payment journal sync."""
    txn_id = _insert_payment(conn, order_id=order_id, amount=amount, ptype=ptype)
    _sync_payment_journal(
        conn, txn_id, amount, ptype, "cash", order_id=order_id
    )
    return txn_id


def _revenue_lines(conn, order_id: int) -> dict[str, dict[str, float]]:
    """Return per-account debit/credit for the order's revenue journal entry."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ?
        ORDER BY je.id DESC
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _revenue_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type = 'order' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


def _assert_double_entry_integrity(conn) -> None:
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


# ---------------------------------------------------------------------------
# _held_tien_rut_for_order
# ---------------------------------------------------------------------------


def test_held_tien_rut_for_order_returns_net_2400_balance():
    """500k deposit + 300k tien_rut → 2400 holds 300k; reversal reduces it."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-RUT-HELD-100", total_price=500000)
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        txn_rut = _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")
        assert _held_tien_rut_for_order(conn, oid) == 300000.0

        # Delete the tien_rut payment entry — 2400 returns to 0.
        _sync_payment_journal(
            conn, txn_rut, 300000, "tien_rut", "cash", order_id=oid, deleted=True,
        )
        assert _held_tien_rut_for_order(conn, oid) == 0.0
        conn.commit()


def test_held_tien_rut_for_order_zero_when_no_tien_rut():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-RUT-HELD-101", total_price=500000)
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        assert _held_tien_rut_for_order(conn, oid) == 0.0


# ---------------------------------------------------------------------------
# AC3 — revenue entry clears 2400 at delivery
# ---------------------------------------------------------------------------


def test_revenue_entry_clears_2400_and_recognizes_net_revenue():
    """AC3: 500k deposits + 300k tien_rut → debit 2100 500k, credit 2400 300k,
    credit 4100 200k."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-AC3", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-AC3")
        assert _revenue_entry_count(conn, oid) == 1
        lines = _revenue_lines(conn, oid)
        assert lines[CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert lines[TIEN_RUT_HELD_CODE]["credit"] == 300000.0
        assert lines[ORDER_REVENUE_CODE]["credit"] == 200000.0
        _assert_double_entry_integrity(conn)
        conn.commit()


def test_revenue_entry_created_when_net_zero():
    """Deposits == tien_rut (net = 0) → revenue entry still created.

    Debit 2100 == credit 2400; the 4100 credit is 0 (omitted). This replaces
    the previous "skip when net <= 0" behaviour (FR3).
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-NET0", total_price=500000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="tien_rut")

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-NET0")
        assert _revenue_entry_count(conn, oid) == 1
        lines = _revenue_lines(conn, oid)
        assert lines[CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert lines[TIEN_RUT_HELD_CODE]["credit"] == 500000.0
        # 4100 credit is zero and therefore omitted from the entry.
        assert ORDER_REVENUE_CODE not in lines
        _assert_double_entry_integrity(conn)
        conn.commit()


def test_revenue_entry_unchanged_when_no_tien_rut():
    """No tien_rut → single-line debit 2100 / credit 4100 (regression)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-NORUT", total_price=500000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-NORUT")
        assert _revenue_entry_count(conn, oid) == 1
        lines = _revenue_lines(conn, oid)
        assert lines[CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert lines[ORDER_REVENUE_CODE]["credit"] == 500000.0
        assert TIEN_RUT_HELD_CODE not in lines
        _assert_double_entry_integrity(conn)
        conn.commit()


# ---------------------------------------------------------------------------
# Update detection + idempotency
# ---------------------------------------------------------------------------


def test_revenue_entry_updates_when_tien_rut_added_after_delivery():
    """500k deposit delivered (entry 2100=500k), then 300k tien_rut → re-sync
    updates to 2100=500k, 2400=300k, 4100=200k."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-UPD", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-UPD")
        lines = _revenue_lines(conn, oid)
        assert lines[CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert TIEN_RUT_HELD_CODE not in lines

        # Issue a tien_rut after delivery; re-sync must update the entry.
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-UPD")
        assert _revenue_entry_count(conn, oid) == 1
        lines = _revenue_lines(conn, oid)
        assert lines[CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert lines[TIEN_RUT_HELD_CODE]["credit"] == 300000.0
        assert lines[ORDER_REVENUE_CODE]["credit"] == 200000.0
        _assert_double_entry_integrity(conn)
        conn.commit()


def test_revenue_entry_idempotent_when_already_correct():
    """Re-syncing an already-correct revenue entry is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-IDEM", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-IDEM")
        entry_id = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-IDEM")
        entry_id_after = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        assert int(entry_id) == int(entry_id_after)
        assert _revenue_entry_count(conn, oid) == 1
        conn.commit()


def test_revenue_entry_reverses_locked_stale_entry():
    """Locked stale entry is reversed; a corrected entry is created."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-LOCK", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-LOCK")
        entry_id = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchone()[0]
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (entry_id,),
        )

        # Add a tien_rut and re-sync — locked entry is reversed, new one created.
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-LOCK")
        entries = conn.execute(
            "SELECT id, locked_at FROM journal_entries "
            "WHERE source_type='order' AND source_id=?",
            (oid,),
        ).fetchall()
        assert len(entries) == 3  # original + reversal + corrected
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
        assert float(net2100) == 500000.0
        conn.commit()