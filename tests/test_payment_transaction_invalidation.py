"""Tests for PaymentTransaction soft-delete (invalidation) fields and totals.

Covers DG-196 Phase 1: schema migration v53 adds ``invalidated_at`` /
``invalidated_by`` columns and the ``total_*`` static methods exclude
invalidated rows. FR5 / AC5 (partial).
"""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.payment_transaction import PaymentTransaction


def _seed_order(conn, total=300000):
    """Insert a minimal order and return its id."""
    cur = conn.execute(
        "INSERT INTO orders (customer_name, due_date, total_price, status, order_ref) "
        "VALUES (?, ?, ?, 'new', ?)",
        ("Test Khách", "2026-06-25", total, "ref-test-1"),
    )
    return int(cur.lastrowid)


def _insert_txn(conn, order_id, amount, type_="deposit", method="cash",
                invalidated_at=None, invalidated_by=""):
    cur = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, note, "
        "invalidated_at, invalidated_by) VALUES (?, ?, ?, ?, '', ?, ?)",
        (order_id, amount, type_, method, invalidated_at, invalidated_by),
    )
    return int(cur.lastrowid)


def test_v53_columns_present_after_schema():
    """invalidated_at/invalidated_by columns exist after ensure_schema."""
    with get_db() as conn:
        ensure_schema(conn)
        cols = {r["name"] for r in conn.execute(
            "PRAGMA table_info(payment_transactions)"
        ).fetchall()}
    assert "invalidated_at" in cols
    assert "invalidated_by" in cols


def test_from_row_reads_invalidation_fields():
    """from_row populates invalidated_at/invalidated_by when present."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        txn_id = _insert_txn(conn, order_id, 100000,
                             invalidated_at="2026-06-25T10:00:00Z",
                             invalidated_by="sinh")
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        txn = PaymentTransaction.from_row(row)
        assert txn.invalidated_at == "2026-06-25T10:00:00Z"
        assert txn.invalidated_by == "sinh"


def test_from_row_handles_absent_columns_gracefully():
    """from_row returns None/'' when columns are missing (defensive)."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        txn_id = _insert_txn(conn, order_id, 50000)
        row = conn.execute(
            "SELECT id, order_id, amount, type, method, note, created_at "
            "FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        txn = PaymentTransaction.from_row(row)
        assert txn.invalidated_at is None
        assert txn.invalidated_by == ""


def test_to_api_dict_includes_invalidation_fields():
    """to_api_dict emits invalidatedAt/invalidatedBy (FR6 / AC7 partial)."""
    txn = PaymentTransaction(
        order_id=1, amount=100000, id=42, created_at="2026-06-25T09:00:00Z",
        invalidated_at="2026-06-25T10:00:00Z", invalidated_by="sinh",
    )
    d = txn.to_api_dict()
    assert d["invalidatedAt"] == "2026-06-25T10:00:00Z"
    assert d["invalidatedBy"] == "sinh"


def test_to_api_dict_invalidation_fields_none_for_valid_txn():
    """Valid transactions emit None/empty invalidated fields."""
    txn = PaymentTransaction(order_id=1, amount=100000, id=1,
                             created_at="2026-06-25T09:00:00Z")
    d = txn.to_api_dict()
    assert d["invalidatedAt"] is None
    assert d["invalidatedBy"] == ""


def test_total_paid_excl_outflows_excludes_invalidated():
    """AC5 (partial): valid deposit 200k + invalidated deposit 100k -> 200k."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        _insert_txn(conn, order_id, 200000, type_="deposit")
        _insert_txn(conn, order_id, 100000, type_="deposit",
                    invalidated_at="2026-06-25T10:00:00Z", invalidated_by="sinh")
        total = PaymentTransaction.total_paid_excl_outflows(conn, order_id)
        assert total == 200000.0


def test_total_for_order_excludes_invalidated():
    """total_for_order excludes invalidated rows."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        _insert_txn(conn, order_id, 200000, type_="deposit")
        _insert_txn(conn, order_id, 100000, type_="deposit",
                    invalidated_at="2026-06-25T10:00:00Z")
        assert PaymentTransaction.total_for_order(conn, order_id) == 200000.0


def test_total_outflows_excludes_invalidated():
    """Invalidated outflows (refund only — tien_rut is no longer an outflow per
    the DG-198 reversal) are excluded from total_outflows."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        _insert_txn(conn, order_id, 50000, type_="refund")
        _insert_txn(conn, order_id, 30000, type_="refund",
                    invalidated_at="2026-06-25T10:00:00Z")
        assert PaymentTransaction.total_outflows(conn, order_id) == 50000.0


def test_total_paid_net_excludes_invalidated():
    """total_paid_net excludes invalidated rows on both sides. tien_rut is now
    a deposit inflow (included in excl_outflows), not an outflow."""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        # valid payment 200k, invalidated payment 100k, valid refund 50k,
        # invalidated refund 30k -> net = 200k - 50k = 150k
        _insert_txn(conn, order_id, 200000, type_="payment")
        _insert_txn(conn, order_id, 100000, type_="payment",
                    invalidated_at="2026-06-25T10:00:00Z")
        _insert_txn(conn, order_id, 50000, type_="refund")
        _insert_txn(conn, order_id, 30000, type_="refund",
                    invalidated_at="2026-06-25T10:00:00Z")
        assert PaymentTransaction.total_paid_net(conn, order_id) == 150000.0


def test_all_invalidated_yields_zero_totals():
    """When every transaction is invalidated, all totals are zero. (tien_rut is
    no longer an outflow — it is included in excl_outflows — but when
    invalidated it contributes 0 to every total.)"""
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _seed_order(conn)
        _insert_txn(conn, order_id, 200000, type_="payment",
                    invalidated_at="2026-06-25T10:00:00Z")
        _insert_txn(conn, order_id, 50000, type_="refund",
                    invalidated_at="2026-06-25T10:00:00Z")
        assert PaymentTransaction.total_for_order(conn, order_id) == 0.0
        assert PaymentTransaction.total_paid_excl_outflows(conn, order_id) == 0.0
        assert PaymentTransaction.total_outflows(conn, order_id) == 0.0
        assert PaymentTransaction.total_paid_net(conn, order_id) == 0.0