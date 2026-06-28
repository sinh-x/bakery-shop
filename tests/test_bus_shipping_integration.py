"""DG-191 Phase 7 — Integration tests + regression guard.

End-to-end coverage of the bus shipping fee accounting lifecycle and a
regression guard proving non-bus (pickup, door) orders are unaffected by the
new 2200 hold/release accounting.

Covers:

- ``test_bus_order_full_lifecycle_journal_entries`` — full lifecycle:
  create bus order → pay deposit → deliver → verify every journal entry
  (payment split, revenue exclusion, shipping release) and re-sync
  idempotency.  AC2/AC3/AC4.
- ``test_pickup_order_no_shipping_split`` — pickup order regression:
  payment entry has no 2200 line, revenue entry includes shipping_fee,
  no shipping release entry exists.  FR7 / AC8.
- ``test_door_order_no_shipping_split`` — door order regression: same
  guarantees as the pickup guard for ``delivery_type='door'``.  FR7 / AC8.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _sync_delivered_order_journal,
    _sync_payment_journal,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _insert_order(
    conn,
    *,
    order_ref: str,
    customer_name: str = "Khách thử",
    total_price: float = 125000.0,
    status: str = "new",
    delivery_type: str = "bus",
    shipping_fee: float = 25000.0,
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


def _pay(conn, *, order_id: int, amount: float) -> int:
    """Insert a deposit and run the payment journal sync (bus split aware)."""
    txn_id = _insert_payment(conn, order_id=order_id, amount=amount, ptype="deposit")
    _sync_payment_journal(conn, txn_id, amount, "deposit", "cash", order_id=order_id)
    return txn_id


def _entry_lines(conn, source_type: str, source_id: int) -> dict[str, dict[str, float]]:
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = ? AND je.source_id = ?
        """,
        (source_type, source_id),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
        out[r["code"]]["debit"] += float(r["debit"] or 0)
        out[r["code"]]["credit"] += float(r["credit"] or 0)
    return out


def _entry_count(conn, source_type: str, source_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type = ? AND source_id = ?",
        (source_type, source_id),
    ).fetchone()
    return int(row[0])


def _assert_balanced(lines: dict[str, dict[str, float]]) -> None:
    """Double-entry integrity: total debit == total credit (0.005 VND tol)."""
    total_debit = sum(v["debit"] for v in lines.values())
    total_credit = sum(v["credit"] for v in lines.values())
    assert abs(total_debit - total_credit) < 0.005, (
        f"unbalanced: debit={total_debit} credit={total_credit}"
    )


# ---------------------------------------------------------------------------
# End-to-end bus order lifecycle
# ---------------------------------------------------------------------------


def test_bus_order_full_lifecycle_journal_entries():
    """Full lifecycle: create bus order → pay → deliver → verify all entries.

    shipping_fee=25000, total_price=125000, deposit=125000.
    Payment entry:   debit 1100 125000, credit 2100 100000, credit 2200 25000
    Revenue entry:   debit 2100 100000, credit 4100 100000  (shipping excluded)
    Release entry:   debit 2200 25000,  credit 1100 25000
    Re-sync:          no duplicate entries created.
    """
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-E2E-001",
            total_price=125000,
            status="new",
            delivery_type="bus",
            shipping_fee=25000,
        )

        # 1. Deposit payment of 125000.
        txn_id = _pay(conn, order_id=oid, amount=125000)
        payment_lines = _entry_lines(conn, "payment_transaction", txn_id)
        assert payment_lines["1100"]["debit"] == 125000.0
        assert payment_lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0
        assert payment_lines[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0
        _assert_balanced(payment_lines)

        # 2. Transition order to delivered and run delivery journal sync.
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id = ?", (oid,))
        _sync_delivered_order_journal(conn, oid, "ORD-E2E-001")

        # 3. Revenue entry: 2100 debit 100000, 4100 credit 100000 (shipping excluded).
        assert _entry_count(conn, "order", oid) == 1
        revenue_rows = conn.execute(
            """
            SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.source_type = 'order' AND je.source_id = ?
            """,
            (oid,),
        ).fetchall()
        revenue_lines = {r["code"]: {"debit": float(r["debit"]), "credit": float(r["credit"])} for r in revenue_rows}
        # Aggregate duplicates if any.
        agg: dict[str, dict[str, float]] = {}
        for r in revenue_rows:
            agg.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
            agg[r["code"]]["debit"] += float(r["debit"] or 0)
            agg[r["code"]]["credit"] += float(r["credit"] or 0)
        assert agg[CUSTOMER_DEPOSITS_CODE]["debit"] == 100000.0
        assert agg[ORDER_REVENUE_CODE]["credit"] == 100000.0
        _assert_balanced(agg)

        # 4. Shipping release entry: debit 2200 25000, credit 1100 25000.
        assert _entry_count(conn, "order_shipping_release", oid) == 1
        release_lines = _entry_lines(conn, "order_shipping_release", oid)
        assert release_lines[BUS_SHIPPING_HELD_CODE]["debit"] == 25000.0
        assert release_lines["1100"]["credit"] == 25000.0
        _assert_balanced(release_lines)

        # 5. Re-sync must not duplicate any entries.
        payment_before = _entry_count(conn, "payment_transaction", txn_id)
        revenue_before = _entry_count(conn, "order", oid)
        release_before = _entry_count(conn, "order_shipping_release", oid)
        _sync_delivered_order_journal(conn, oid, "ORD-E2E-001")
        assert _entry_count(conn, "payment_transaction", txn_id) == payment_before
        assert _entry_count(conn, "order", oid) == revenue_before
        assert _entry_count(conn, "order_shipping_release", oid) == release_before
        conn.commit()


# ---------------------------------------------------------------------------
# Regression guard — non-bus orders unchanged (FR7 / AC8)
# ---------------------------------------------------------------------------


def _run_non_bus_regression(order_ref: str, delivery_type: str) -> None:
    """Shared body for the pickup/door regression guards."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref=order_ref,
            total_price=125000,
            status="new",
            delivery_type=delivery_type,
            shipping_fee=25000,
        )
        txn_id = _pay(conn, order_id=oid, amount=125000)
        lines = _entry_lines(conn, "payment_transaction", txn_id)
        # No 2200 involvement at all.
        assert BUS_SHIPPING_HELD_CODE not in lines, (
            f"{delivery_type} payment must not involve 2200"
        )
        assert lines["1100"]["debit"] == 125000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 125000.0
        _assert_balanced(lines)

        # Transition to delivered.
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id = ?", (oid,))
        _sync_delivered_order_journal(conn, oid, order_ref)

        # Revenue entry includes the full deposit (no shipping_fee exclusion).
        revenue_rows = conn.execute(
            """
            SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.source_type = 'order' AND je.source_id = ?
            """,
            (oid,),
        ).fetchall()
        agg: dict[str, dict[str, float]] = {}
        for r in revenue_rows:
            agg.setdefault(r["code"], {"debit": 0.0, "credit": 0.0})
            agg[r["code"]]["debit"] += float(r["debit"] or 0)
            agg[r["code"]]["credit"] += float(r["credit"] or 0)
        assert agg[CUSTOMER_DEPOSITS_CODE]["debit"] == 125000.0
        assert agg[ORDER_REVENUE_CODE]["credit"] == 125000.0
        _assert_balanced(agg)

        # No shipping release entry.
        assert _entry_count(conn, "order_shipping_release", oid) == 0
        conn.commit()


def test_pickup_order_no_shipping_split():
    """FR7 / AC8: pickup order is unaffected by the bus shipping accounting.

    Payment entry:   debit 1100 125000, credit 2100 125000 (no 2200 split)
    Revenue entry:   debit 2100 125000, credit 4100 125000 (shipping included)
    Release entry:   none.
    """
    _run_non_bus_regression("ORD-E2E-PICKUP", "pickup")


def test_door_order_no_shipping_split():
    """FR7 / AC8: door order is unaffected by the bus shipping accounting.

    Payment entry:   debit 1100 125000, credit 2100 125000 (no 2200 split)
    Revenue entry:   debit 2100 125000, credit 4100 125000 (shipping included)
    Release entry:   none.
    """
    _run_non_bus_regression("ORD-E2E-DOOR", "door")