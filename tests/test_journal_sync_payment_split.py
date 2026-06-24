"""Tests for DG-191 Phase 2 — bus shipping fee payment journal split.

Covers:

- Bus order with shipping_fee > 0: inflow payment splits credit between
  2100 (Customer Deposits, product portion) and 2200 (Bus Shipping Held,
  shipping portion). AC2.
- Bus order with shipping_fee = 0: no split, all credit to 2100.
- Pickup order: no split, all credit to 2100.
- Door order: no split, all credit to 2100.
- Multiple payments: first payment covers shipping up to shipping_fee,
  remainder to 2100; subsequent payments all to 2100.
- Outflow (refund/tien_rut) on a bus order: no 2200 involvement in Phase 2
  (release deferred to Phase 3); standard reverse lines.
- Payment update re-sync: editing amount re-computes the split correctly.
- Double-entry integrity: debit == credit for every split entry.
- Non-bus regression: behavior identical to pre-change.
"""

from baker.db.connection import get_db
from baker.db.schema import (
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    ensure_schema,
)
from baker.services.journal_sync import _sync_payment_journal


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
    total_price: float = 100000.0,
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


def _payment_line_amounts(conn, txn_id: int) -> dict[str, dict[str, float]]:
    """Return per-account debit/credit for the payment txn's journal entry."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'payment_transaction' AND je.source_id = ?
        """,
        (txn_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _payment_entry_count(conn, txn_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = 'payment_transaction' AND source_id = ?",
        (txn_id,),
    ).fetchone()
    return int(row[0])


# ---------------------------------------------------------------------------
# AC2 — Bus order split
# ---------------------------------------------------------------------------


def test_bus_order_deposit_splits_credit_to_2100_and_2200():
    """AC2: bus order, shipping_fee=25000, deposit=100000 →
    debit 1100 100000, credit 2100 75000, credit 2200 25000."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-100", shipping_fee=25000, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(
            conn, txn_id, 100000, "deposit", "cash", order_id=oid
        )

        lines = _payment_line_amounts(conn, txn_id)
        assert lines["1100"]["debit"] == 100000.0
        assert lines["1100"]["credit"] == 0.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 75000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["debit"] == 0.0
        assert lines[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0
        assert lines[BUS_SHIPPING_HELD_CODE]["debit"] == 0.0

        # Double-entry integrity: total debit == total credit.
        total_debit = sum(v["debit"] for v in lines.values())
        total_credit = sum(v["credit"] for v in lines.values())
        assert abs(total_debit - total_credit) < 0.005


# ---------------------------------------------------------------------------
# No-split cases
# ---------------------------------------------------------------------------


def test_bus_order_shipping_fee_zero_no_split():
    """Bus order with shipping_fee=0 → all credit to 2100 (no 2200 line)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-101", shipping_fee=0, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(
            conn, txn_id, 100000, "deposit", "cash", order_id=oid
        )

        lines = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in lines
        assert lines["1100"]["debit"] == 100000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0


def test_pickup_order_no_split():
    """Pickup order → all credit to 2100 (no 2200 involvement)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-PICK-102",
            delivery_type="pickup",
            shipping_fee=25000,
            total_price=100000,
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(
            conn, txn_id, 100000, "deposit", "cash", order_id=oid
        )

        lines = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in lines
        assert lines["1100"]["debit"] == 100000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0


def test_door_order_no_split():
    """Door order → all credit to 2100 (no 2200 involvement)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn,
            order_ref="ORD-DOOR-103",
            delivery_type="door",
            shipping_fee=20000,
            total_price=100000,
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(
            conn, txn_id, 100000, "deposit", "cash", order_id=oid
        )

        lines = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in lines
        assert lines["1100"]["debit"] == 100000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0


# ---------------------------------------------------------------------------
# Multiple payments — first covers shipping, rest to 2100
# ---------------------------------------------------------------------------


def test_multiple_payments_first_covers_shipping_second_all_to_2100():
    """Bus order, shipping_fee=25000, two deposits of 20000 + 80000.
    First payment: all 20000 to 2200 (covers part of shipping), 0 to 2100.
    Second payment: 5000 to 2200 (remaining shipping), 75000 to 2100."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-104", shipping_fee=25000, total_price=100000
        )

        txn1 = _insert_payment(conn, order_id=oid, amount=20000, ptype="deposit")
        _sync_payment_journal(conn, txn1, 20000, "deposit", "cash", order_id=oid)
        lines1 = _payment_line_amounts(conn, txn1)
        assert lines1[BUS_SHIPPING_HELD_CODE]["credit"] == 20000.0
        assert lines1[CUSTOMER_DEPOSITS_CODE]["credit"] == 0.0
        assert lines1["1100"]["debit"] == 20000.0

        txn2 = _insert_payment(conn, order_id=oid, amount=80000, ptype="deposit")
        _sync_payment_journal(conn, txn2, 80000, "deposit", "cash", order_id=oid)
        lines2 = _payment_line_amounts(conn, txn2)
        # Remaining shipping = 25000 - 20000 = 5000 → 2200
        assert lines2[BUS_SHIPPING_HELD_CODE]["credit"] == 5000.0
        # Remainder = 80000 - 5000 = 75000 → 2100
        assert lines2[CUSTOMER_DEPOSITS_CODE]["credit"] == 75000.0
        assert lines2["1100"]["debit"] == 80000.0


def test_third_payment_after_shipping_covered_all_to_2100():
    """Bus order, shipping_fee=25000, three deposits. Third payment: all 2100."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-105", shipping_fee=25000, total_price=200000
        )

        txn1 = _insert_payment(conn, order_id=oid, amount=25000, ptype="deposit")
        _sync_payment_journal(conn, txn1, 25000, "deposit", "cash", order_id=oid)

        txn2 = _insert_payment(conn, order_id=oid, amount=50000, ptype="deposit")
        _sync_payment_journal(conn, txn2, 50000, "deposit", "cash", order_id=oid)
        lines2 = _payment_line_amounts(conn, txn2)
        assert lines2[CUSTOMER_DEPOSITS_CODE]["credit"] == 50000.0
        assert BUS_SHIPPING_HELD_CODE not in lines2

        txn3 = _insert_payment(conn, order_id=oid, amount=30000, ptype="deposit")
        _sync_payment_journal(conn, txn3, 30000, "deposit", "cash", order_id=oid)
        lines3 = _payment_line_amounts(conn, txn3)
        assert lines3[CUSTOMER_DEPOSITS_CODE]["credit"] == 30000.0
        assert BUS_SHIPPING_HELD_CODE not in lines3


# ---------------------------------------------------------------------------
# Outflow — no 2200 split in Phase 2 (release deferred to Phase 3)
# ---------------------------------------------------------------------------


def test_bus_order_outflow_no_2200_split():
    """Bus order, refund/tien_rut → standard reverse lines, no 2200 involvement.
    Phase 2 defers 2200 release to Phase 3 (delivery shipping release)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-106", shipping_fee=25000, total_price=100000
        )
        # First a deposit that splits.
        txn1 = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(conn, txn1, 100000, "deposit", "cash", order_id=oid)
        # Then a refund (outflow).
        txn2 = _insert_payment(conn, order_id=oid, amount=30000, ptype="tien_rut")
        _sync_payment_journal(conn, txn2, 30000, "tien_rut", "cash", order_id=oid)

        lines2 = _payment_line_amounts(conn, txn2)
        # Outflow: debit 2100 30000, credit 1100 30000 — no 2200 line.
        assert BUS_SHIPPING_HELD_CODE not in lines2
        assert lines2[CUSTOMER_DEPOSITS_CODE]["debit"] == 30000.0
        assert lines2["1100"]["credit"] == 30000.0


# ---------------------------------------------------------------------------
# Payment update re-sync
# ---------------------------------------------------------------------------


def test_payment_update_re_syncs_split_correctly():
    """Create a 100000 deposit (split 75000/25000), update to 80000 →
    re-sync should split 55000/25000 (shipping unchanged, product reduced)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-107", shipping_fee=25000, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(conn, txn_id, 100000, "deposit", "cash", order_id=oid)
        lines_before = _payment_line_amounts(conn, txn_id)
        assert lines_before[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0
        assert lines_before[CUSTOMER_DEPOSITS_CODE]["credit"] == 75000.0

        # Update payment amount to 80000 and re-sync.
        conn.execute(
            "UPDATE payment_transactions SET amount = ? WHERE id = ?",
            (80000, txn_id),
        )
        _sync_payment_journal(conn, txn_id, 80000, "deposit", "cash", order_id=oid)

        lines_after = _payment_line_amounts(conn, txn_id)
        # Shipping still 25000 (unchanged), product = 80000 - 25000 = 55000.
        assert lines_after[BUS_SHIPPING_HELD_CODE]["credit"] == 25000.0
        assert lines_after[CUSTOMER_DEPOSITS_CODE]["credit"] == 55000.0
        assert lines_after["1100"]["debit"] == 80000.0
        # Only one entry (updated in place, not duplicated).
        assert _payment_entry_count(conn, txn_id) == 1


def test_payment_update_amount_below_shipping_all_to_2200():
    """Bus order shipping_fee=25000, deposit 100000 → update to 20000.
    After re-sync: 20000 all to 2200 (shipping), 0 to 2100."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-108", shipping_fee=25000, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(conn, txn_id, 100000, "deposit", "cash", order_id=oid)

        conn.execute(
            "UPDATE payment_transactions SET amount = ? WHERE id = ?",
            (20000, txn_id),
        )
        _sync_payment_journal(conn, txn_id, 20000, "deposit", "cash", order_id=oid)
        lines = _payment_line_amounts(conn, txn_id)
        assert lines[BUS_SHIPPING_HELD_CODE]["credit"] == 20000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 0.0
        assert lines["1100"]["debit"] == 20000.0
        assert _payment_entry_count(conn, txn_id) == 1


# ---------------------------------------------------------------------------
# No order_id — backwards compatibility (no split)
# ---------------------------------------------------------------------------


def test_no_order_id_no_split_backwards_compatible():
    """When order_id is not passed, behavior is identical to pre-change:
    all credit to 2100, no 2200 involvement (even for bus orders)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-109", shipping_fee=25000, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        # Intentionally omit order_id — old callers must keep working.
        _sync_payment_journal(conn, txn_id, 100000, "deposit", "cash")

        lines = _payment_line_amounts(conn, txn_id)
        assert BUS_SHIPPING_HELD_CODE not in lines
        assert lines["1100"]["debit"] == 100000.0
        assert lines[CUSTOMER_DEPOSITS_CODE]["credit"] == 100000.0


# ---------------------------------------------------------------------------
# Delete path — _sync_payment_journal(deleted=True)
# ---------------------------------------------------------------------------


def test_sync_payment_journal_deleted_removes_unlocked_entry():
    """Mn-1: ``_sync_payment_journal(deleted=True)`` removes an unlocked journal
    entry for the payment transaction. Covers the unlock-and-delete branch
    (vs. the locked-and-reverse branch)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-200", shipping_fee=25000, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        _sync_payment_journal(conn, txn_id, 100000, "deposit", "cash", order_id=oid)

        # Entry exists and is unlocked (no locked_at set by the live sync path).
        assert _payment_entry_count(conn, txn_id) == 1
        assert _payment_line_amounts(conn, txn_id)  # lines present

        # Deleting the payment should cascade-delete its unlocked journal entry.
        _sync_payment_journal(
            conn, txn_id, 0, "deposit", "cash", order_id=oid, deleted=True
        )

        assert _payment_entry_count(conn, txn_id) == 0
        assert _payment_line_amounts(conn, txn_id) == {}


def test_sync_payment_journal_deleted_no_existing_entry_is_noop():
    """``deleted=True`` with no existing journal entry is a no-op (not an error)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-BUS-201", shipping_fee=0, total_price=100000
        )
        txn_id = _insert_payment(conn, order_id=oid, amount=100000, ptype="deposit")
        # Never synced — no journal entry exists yet.
        assert _payment_entry_count(conn, txn_id) == 0

        _sync_payment_journal(
            conn, txn_id, 0, "deposit", "cash", order_id=oid, deleted=True
        )

        assert _payment_entry_count(conn, txn_id) == 0