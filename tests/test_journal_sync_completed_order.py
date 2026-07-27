"""Tests for DG-269 Phase 2 — `_sync_completed_order_journal`.

Covers the three completion paths defined in the plan §4 / AC3a–AC3c:

  (a) Fresh completion with no prior order-level revenue entries (order
      bypassed "delivered") → entries are created (AC3c).
  (b) Delivered→completed with **no** payment changes between delivery and
      completion → completion sync is a no-op: zero new entries, the
      delivery-time entry is retained unchanged (AC3a).
  (c) Delivered→completed with **extra** payments made between delivery and
      completion → the existing delivery revenue entry is updated in place
      (not duplicated) to reflect the new total (AC3b).

The completion function delegates to :func:`_reconcile_order_revenue_entry`,
which already queries **all** non-invalidated payment transactions for the
order and reconciles against existing `source_type='order'` entries within
the 0.005 VND tolerance. These tests pin that behaviour at the
`_sync_completed_order_journal` entry point.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    ACCOUNTS_RECEIVABLE_CODE,
    COGS_CODE,
    CUSTOMER_DEPOSITS_CODE,
    INVENTORY_CODE,
    ORDER_REVENUE_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _sync_completed_order_journal,
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
    status: str = "completed",
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


def _ar_1500_debit(conn, order_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) AS debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ? AND a.code = ?
        """,
        (order_id, ACCOUNTS_RECEIVABLE_CODE),
    ).fetchone()
    return float(row["debit"])


def _order_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'order' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


def _order_entry_ids(conn, order_id: int) -> list[int]:
    rows = conn.execute(
        "SELECT id FROM journal_entries WHERE source_type = 'order' AND source_id = ? "
        "ORDER BY id",
        (order_id,),
    ).fetchall()
    return [int(r[0]) for r in rows]


# ---------------------------------------------------------------------------
# AC3c — Fresh completion (order bypassed "delivered", no prior entries)
# ---------------------------------------------------------------------------


def test_fresh_completion_creates_revenue_entry():
    """AC3c: order goes directly to "completed" with no prior order-level
    entries → completion sync creates the revenue entry (DR 2100 / CR 4100)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-CMP-100", total_price=500000, status="completed"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        assert _order_entry_count(conn, oid) == 0

        _sync_completed_order_journal(conn, oid, "ORD-CMP-100")

        assert _order_entry_count(conn, oid) == 1
        assert _revenue_2100_debit(conn, oid) == 500000.0
        assert _revenue_4100_credit(conn, oid) == 500000.0
        conn.commit()


def test_fresh_completion_unpaid_creates_ar_entry():
    """AC3c variant: unpaid completed order (no deposits) → AR entry
    (DR 1500 / CR 4100) for total_price."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-CMP-101", total_price=400000, status="completed"
        )
        # No payments.
        _sync_completed_order_journal(conn, oid, "ORD-CMP-101")

        assert _order_entry_count(conn, oid) == 1
        assert _ar_1500_debit(conn, oid) == 400000.0
        assert _revenue_4100_credit(conn, oid) == 400000.0
        conn.commit()


# ---------------------------------------------------------------------------
# AC3a — Delivered→completed, no payment changes → no-op
# ---------------------------------------------------------------------------


def test_delivered_to_completed_no_payment_changes_is_noop():
    """AC3a: order goes delivered→completed with no payment changes between
    delivery and completion → completion sync is a no-op (zero new entries,
    delivery entry retained)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-CMP-200", total_price=500000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        # Delivery sync creates the revenue entry.
        _sync_delivered_order_journal(conn, oid, "ORD-CMP-200")
        delivery_entry_ids = _order_entry_ids(conn, oid)
        assert len(delivery_entry_ids) == 1
        assert _revenue_2100_debit(conn, oid) == 500000.0

        # Transition to completed (no payment changes). Completion sync must
        # not duplicate or replace the delivery entry.
        conn.execute("UPDATE orders SET status = 'completed' WHERE id = ?", (oid,))
        _sync_completed_order_journal(conn, oid, "ORD-CMP-200")

        assert _order_entry_ids(conn, oid) == delivery_entry_ids
        assert _revenue_2100_debit(conn, oid) == 500000.0
        assert _revenue_4100_credit(conn, oid) == 500000.0
        conn.commit()


# ---------------------------------------------------------------------------
# AC3b — Delivered→completed with extra payments → existing entry updated
# ---------------------------------------------------------------------------


def test_delivered_to_completed_with_extra_payment_updates_existing_entry():
    """AC3b: order delivered→completed with an additional deposit recorded
    between delivery and completion → the existing delivery revenue entry is
    updated (not duplicated) to reflect the new total."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-CMP-300", total_price=800000, status="delivered"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        # Delivery sync: 2100 debit = 500k.
        _sync_delivered_order_journal(conn, oid, "ORD-CMP-300")
        delivery_entry_ids = _order_entry_ids(conn, oid)
        assert len(delivery_entry_ids) == 1
        assert _revenue_2100_debit(conn, oid) == 500000.0

        # Additional 300k deposit recorded between delivery and completion.
        _insert_payment(conn, order_id=oid, amount=300000, ptype="deposit")
        conn.execute("UPDATE orders SET status = 'completed' WHERE id = ?", (oid,))

        _sync_completed_order_journal(conn, oid, "ORD-CMP-300")

        # The 2100 debit must now reflect the full 800k total.
        assert _revenue_2100_debit(conn, oid) == 800000.0
        assert _revenue_4100_credit(conn, oid) == 800000.0
        # No duplicate entries: still exactly one order-level entry.
        assert len(_order_entry_ids(conn, oid)) == 1
        conn.commit()


def test_completion_sync_is_idempotent_on_repeat_calls():
    """Re-running completion sync on an already-correct order is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-CMP-400", total_price=500000, status="completed"
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        _sync_completed_order_journal(conn, oid, "ORD-CMP-400")
        first_ids = _order_entry_ids(conn, oid)

        _sync_completed_order_journal(conn, oid, "ORD-CMP-400")
        _sync_completed_order_journal(conn, oid, "ORD-CMP-400")

        assert _order_entry_ids(conn, oid) == first_ids
        assert _revenue_2100_debit(conn, oid) == 500000.0
        conn.commit()


# ---------------------------------------------------------------------------
# COGS helpers (DG-276)
# ---------------------------------------------------------------------------


def _insert_product(conn, *, name: str, category: str = "banh_mi", base_price: float = 100000) -> int:
    cur = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (name, category, base_price, base_price),
    )
    return int(cur.lastrowid)


def _add_order_item(
    conn,
    *,
    order_id: int,
    product_id: int,
    product_name: str = "Bánh mì",
    qty: int = 1,
    unit_price: float = 100000,
    cost_at_sale: float = 0,
    is_extra: int = 0,
    is_gift: int = 0,
) -> None:
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift) "
        "VALUES (?, ?, ?, ?, ?, 0, 'delivered', ?, ?, ?)",
        (order_id, product_id, product_name, qty, unit_price,
         cost_at_sale, is_extra, is_gift),
    )


def _cogs_entry_count(conn, order_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'order_cogs' AND source_id = ?",
        (order_id,),
    ).fetchone()
    return int(row[0])


def _cogs_5900_debit(conn, order_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) AS debit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_cogs' AND je.source_id = ? AND a.code = ?
        """,
        (order_id, COGS_CODE),
    ).fetchone()
    return float(row["debit"])


def _cogs_1300_credit(conn, order_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.credit), 0) AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order_cogs' AND je.source_id = ? AND a.code = ?
        """,
        (order_id, INVENTORY_CODE),
    ).fetchone()
    return float(row["credit"])


# ---------------------------------------------------------------------------
# AC1 / AC6 — COGS created on bypassed-delivery completion (cost_history)
# ---------------------------------------------------------------------------


def test_fresh_completion_creates_cogs_entry_via_cost_history():
    """AC1/AC6: an order that transitions directly to "completed" (bypassing
    "delivered") with items carrying cost_history gets an ``order_cogs`` entry
    (DR 5900 / CR 1300) at completion time."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, name="SP-COGS-CMP-1", base_price=100000)
        # cost_history cost 25000 (overrides the 30% baseline) effective now.
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) "
            "VALUES (?, ?, ?)",
            (pid, 25000, "2020-01-01T00:00:00Z"),
        )
        oid = _insert_order(
            conn, order_ref="ORD-CMP-COGS-500", total_price=500000, status="completed"
        )
        _add_order_item(
            conn, order_id=oid, product_id=pid, product_name="SP-COGS-CMP-1",
            qty=2, unit_price=50000,
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        assert _cogs_entry_count(conn, oid) == 0

        _sync_completed_order_journal(conn, oid, "ORD-CMP-COGS-500")

        # cost_history 25000 × qty 2 = 50000
        assert _cogs_entry_count(conn, oid) == 1
        assert _cogs_5900_debit(conn, oid) == 50000.0
        assert _cogs_1300_credit(conn, oid) == 50000.0
        conn.commit()


# ---------------------------------------------------------------------------
# AC2 — delivered→completed must not duplicate the COGS entry
# ---------------------------------------------------------------------------


def test_delivered_to_completed_does_not_duplicate_cogs_entry():
    """AC2: an order that already has an ``order_cogs`` entry from the delivery
    sync must not get a duplicate when transitioning delivered→completed."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, name="SP-COGS-CMP-2", base_price=100000)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) "
            "VALUES (?, ?, ?)",
            (pid, 25000, "2020-01-01T00:00:00Z"),
        )
        oid = _insert_order(
            conn, order_ref="ORD-CMP-COGS-600", total_price=500000, status="delivered"
        )
        _add_order_item(
            conn, order_id=oid, product_id=pid, product_name="SP-COGS-CMP-2",
            qty=2, unit_price=50000,
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        # Delivery sync creates the COGS entry.
        _sync_delivered_order_journal(conn, oid, "ORD-CMP-COGS-600")
        assert _cogs_entry_count(conn, oid) == 1
        assert _cogs_5900_debit(conn, oid) == 50000.0

        conn.execute("UPDATE orders SET status = 'completed' WHERE id = ?", (oid,))
        _sync_completed_order_journal(conn, oid, "ORD-CMP-COGS-600")

        # No duplicate COGS entry.
        assert _cogs_entry_count(conn, oid) == 1
        assert _cogs_5900_debit(conn, oid) == 50000.0
        assert _cogs_1300_credit(conn, oid) == 50000.0
        conn.commit()


# ---------------------------------------------------------------------------
# AC3 — completion sync re-run must not duplicate COGS
# ---------------------------------------------------------------------------


def test_completion_sync_cogs_is_idempotent_on_repeat_calls():
    """AC3: re-running completion sync on an order that already has an
    ``order_cogs`` entry must not create a duplicate."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, name="SP-COGS-CMP-3", base_price=100000)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) "
            "VALUES (?, ?, ?)",
            (pid, 25000, "2020-01-01T00:00:00Z"),
        )
        oid = _insert_order(
            conn, order_ref="ORD-CMP-COGS-700", total_price=500000, status="completed"
        )
        _add_order_item(
            conn, order_id=oid, product_id=pid, product_name="SP-COGS-CMP-3",
            qty=2, unit_price=50000,
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")

        _sync_completed_order_journal(conn, oid, "ORD-CMP-COGS-700")
        first_cogs_count = _cogs_entry_count(conn, oid)
        assert first_cogs_count == 1

        _sync_completed_order_journal(conn, oid, "ORD-CMP-COGS-700")
        _sync_completed_order_journal(conn, oid, "ORD-CMP-COGS-700")

        assert _cogs_entry_count(conn, oid) == 1
        assert _cogs_5900_debit(conn, oid) == 50000.0
        conn.commit()