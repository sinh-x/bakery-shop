"""Tests for DG-198 reversal — revenue entry and tien rut return entry at
delivery (FR3, AC3).

Covers:

- Order with deposits + tien_rut, delivered → TWO separate journal entries:
  - Revenue entry: DR 2100 (full deposit balance), CR 4100 (net revenue =
    deposit balance). Deposits only — tien_rut is NOT netted.
  - Tien rut return entry: DR 2400 (full tien_rut held), CR Asset (cash
    returned to customer).
- Order with deposits == tien_rut → revenue entry debits 2100 and credits
  4100 for the full deposit balance (tien_rut does not reduce revenue); a
  separate return entry returns the tien_rut.
- Order with deposits and no tien_rut → unchanged single-line 2100/4100 entry,
  no return entry.
- _held_tien_rut_for_order returns the net 2400 balance (credit at payment
  time minus debit at return) for the order.
- Double-entry integrity holds for every entry.
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


def _order_entries(conn, order_id: int) -> list[dict]:
    """Return all ``source_type='order'`` entries for the order with their
    per-account debit/credit lines grouped by entry."""
    rows = conn.execute(
        """
        SELECT je.id AS entry_id, je.description AS description,
               a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ?
        ORDER BY je.id, a.code
        """,
        (order_id,),
    ).fetchall()
    entries: dict[int, dict] = {}
    for r in rows:
        eid = int(r["entry_id"])
        entries.setdefault(eid, {"id": eid, "description": r["description"], "lines": {}})
        entries[eid]["lines"][r["code"]] = {
            "debit": float(r["debit"] or 0),
            "credit": float(r["credit"] or 0),
        }
    return list(entries.values())


def _revenue_entry(conn, order_id: int) -> dict:
    """Return the deposits→revenue entry (description starts with 'Order revenue')."""
    for e in _order_entries(conn, order_id):
        if e["description"].startswith("Order revenue:"):
            return e
    return {}


def _tien_rut_return_entry(conn, order_id: int) -> dict:
    """Return the tien rut return entry (description starts with 'Tien rut return')."""
    for e in _order_entries(conn, order_id):
        if e["description"].startswith("Tien rut return:"):
            return e
    return {}


def _order_entry_count(conn, order_id: int) -> int:
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
    """300k tien_rut → 2400 holds 300k (credit at payment time). Reversal
    (delete) reduces it back to 0."""
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
# AC3 — separate revenue + tien rut return entries at delivery
# ---------------------------------------------------------------------------


def test_revenue_entry_and_tien_rut_return_at_delivery():
    """AC3: 500k deposits + 300k tien_rut →
    - Revenue entry: DR 2100 500k, CR 4100 500k (deposits only, tien_rut not netted)
    - Tien rut return entry: DR 2400 300k, CR 1100 300k (cash returned to customer)
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-AC3", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-AC3")
        # Two separate order entries: revenue + tien rut return.
        assert _order_entry_count(conn, oid) == 2

        rev = _revenue_entry(conn, oid)
        assert rev["lines"][CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert rev["lines"][ORDER_REVENUE_CODE]["credit"] == 500000.0
        assert TIEN_RUT_HELD_CODE not in rev["lines"]

        ret = _tien_rut_return_entry(conn, oid)
        assert ret["lines"][TIEN_RUT_HELD_CODE]["debit"] == 300000.0
        assert ret["lines"]["1100"]["credit"] == 300000.0
        _assert_double_entry_integrity(conn)
        conn.commit()


def test_revenue_entry_deposits_equal_tien_rut():
    """Deposits == tien_rut (500k each) → revenue entry debits 2100 and credits
    4100 for the full 500k deposit balance (tien_rut does NOT reduce revenue);
    a separate return entry returns the 500k tien_rut."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-NET0", total_price=500000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="tien_rut")

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-NET0")
        assert _order_entry_count(conn, oid) == 2

        rev = _revenue_entry(conn, oid)
        assert rev["lines"][CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert rev["lines"][ORDER_REVENUE_CODE]["credit"] == 500000.0

        ret = _tien_rut_return_entry(conn, oid)
        assert ret["lines"][TIEN_RUT_HELD_CODE]["debit"] == 500000.0
        assert ret["lines"]["1100"]["credit"] == 500000.0
        _assert_double_entry_integrity(conn)
        conn.commit()


def test_revenue_entry_unchanged_when_no_tien_rut():
    """No tien_rut → single-line debit 2100 / credit 4100 (regression). No
    tien rut return entry is created."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-NORUT", total_price=500000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-NORUT")
        assert _order_entry_count(conn, oid) == 1
        rev = _revenue_entry(conn, oid)
        assert rev["lines"][CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert rev["lines"][ORDER_REVENUE_CODE]["credit"] == 500000.0
        assert _tien_rut_return_entry(conn, oid) == {}
        _assert_double_entry_integrity(conn)
        conn.commit()


# ---------------------------------------------------------------------------
# Update detection + idempotency
# ---------------------------------------------------------------------------


def test_revenue_entry_updates_when_tien_rut_added_after_delivery():
    """500k deposit delivered (revenue entry 2100=500k, 4100=500k), then 300k
    tien_rut → re-sync creates a separate tien rut return entry (DR 2400 300k,
    CR 1100 300k); the revenue entry is unchanged (deposits not netted)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-UPD", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-UPD")
        assert _order_entry_count(conn, oid) == 1
        rev = _revenue_entry(conn, oid)
        assert rev["lines"][CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert _tien_rut_return_entry(conn, oid) == {}

        # Issue a tien_rut after delivery; re-sync must create the return entry.
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-UPD")
        assert _order_entry_count(conn, oid) == 2
        rev = _revenue_entry(conn, oid)
        assert rev["lines"][CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert rev["lines"][ORDER_REVENUE_CODE]["credit"] == 500000.0
        ret = _tien_rut_return_entry(conn, oid)
        assert ret["lines"][TIEN_RUT_HELD_CODE]["debit"] == 300000.0
        assert ret["lines"]["1100"]["credit"] == 300000.0
        _assert_double_entry_integrity(conn)
        conn.commit()


def test_revenue_entry_idempotent_when_already_correct():
    """Re-syncing already-correct revenue + return entries is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-IDEM", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _pay_and_sync(conn, order_id=oid, amount=300000, ptype="tien_rut")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-IDEM")
        entry_ids_before = {
            int(r["id"])
            for r in conn.execute(
                "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
                (oid,),
            ).fetchall()
        }

        _sync_delivered_order_journal(conn, oid, "ORD-RUT-IDEM")
        entry_ids_after = {
            int(r["id"])
            for r in conn.execute(
                "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
                (oid,),
            ).fetchall()
        }
        assert entry_ids_before == entry_ids_after
        assert _order_entry_count(conn, oid) == 2
        conn.commit()


def test_revenue_entry_reverses_locked_stale_entry():
    """Locked stale revenue entry is reversed; a corrected entry is created.
    The tien rut return entry is separate and unaffected by the lock test."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-RUT-LOCK", total_price=700000, status="delivered"
        )
        _pay_and_sync(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-LOCK")
        rev_id = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type='order' AND source_id=? AND description LIKE 'Order revenue:%'",
            (oid,),
        ).fetchone()[0]
        conn.execute(
            "UPDATE journal_entries SET locked_at = CURRENT_TIMESTAMP WHERE id = ?",
            (rev_id,),
        )

        # Add a deposit so the revenue entry is stale (deposit balance grew).
        _pay_and_sync(conn, order_id=oid, amount=200000, ptype="deposit")
        _sync_delivered_order_journal(conn, oid, "ORD-RUT-LOCK")
        # The locked revenue entry is reversed; a corrected one is created.
        # Net 2100 balance (debit − credit across all order entries) = 700k.
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
        assert float(net2100) == 700000.0
        conn.commit()