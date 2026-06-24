"""Tests for ``baker pipeline`` CLI group — DG-190 Phase 4.1.

Covers the five read-only pipeline subcommands:

- ``undelivered-deposits`` — orders not delivered/completed/cancelled with deposits
- ``cancelled-unrefunded``  — cancelled orders where deposits > refunds
- ``deposit-revenue-gap``   — per-order reconciliation of net deposits vs 2100 debits
- ``refunds``               — all tien_rut transactions with order context
- ``new-no-deposit``        — new/confirmed orders with zero deposits

Each test seeds a small known dataset and asserts the expected values appear
in the CLI output. The empty-DB case is also covered for each command.
"""

import click
import click.testing

from baker.cli import app
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
    status: str = "new",
    due_date: str | None = "2026-07-01",
    created_at: str | None = None,
) -> int:
    """Insert an order and return its id."""
    if created_at:
        cur = conn.execute(
            "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (order_ref, customer_name, total_price, status, due_date, created_at),
        )
    else:
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
    created_at: str | None = None,
) -> int:
    """Insert a payment_transaction and return its id."""
    if created_at:
        cur = conn.execute(
            "INSERT INTO payment_transactions (order_id, amount, type, method, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (order_id, amount, ptype, method, created_at),
        )
    else:
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
    created_at: str = "2026-06-20T10:00:00",
) -> int:
    """Insert a balanced order-revenue journal entry debiting 2100."""
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id, created_at) "
        "VALUES (?, 'order', ?, ?)",
        (f"Order revenue: {order_id}", order_id, created_at),
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


# ---------------------------------------------------------------------------
# Group registration sanity
# ---------------------------------------------------------------------------


def test_pipeline_group_registered():
    result = _invoke(["pipeline", "--help"])
    assert result.exit_code == 0, result.output
    assert "undelivered-deposits" in result.output
    assert "cancelled-unrefunded" in result.output
    assert "deposit-revenue-gap" in result.output
    assert "refunds" in result.output
    assert "new-no-deposit" in result.output


# ---------------------------------------------------------------------------
# undelivered-deposits
# ---------------------------------------------------------------------------


def test_undelivered_deposits_lists_orders_with_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260624-001", customer_name="Anh A",
            total_price=1500000, status="confirmed", due_date="2026-06-28",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        # An undelivered order with NO deposit should be excluded.
        _insert_order(
            conn, order_ref="ORD-260624-002", customer_name="Anh B",
            total_price=800000, status="new", due_date="2026-06-29",
        )
        # A delivered order with a deposit should be excluded.
        delivered_id = _insert_order(
            conn, order_ref="ORD-260624-003", customer_name="Anh C",
            total_price=2000000, status="delivered", due_date="2026-06-20",
        )
        _insert_payment(conn, order_id=delivered_id, amount=2000000, ptype="full_payment")

    result = _invoke(["pipeline", "undelivered-deposits"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-001" in result.output
    assert "Anh A" in result.output
    assert "500.000" in result.output  # VN-formatted deposit
    assert "1.500.000" in result.output  # total price
    assert "ORD-260624-002" not in result.output  # no deposit
    assert "ORD-260624-003" not in result.output  # delivered


def test_undelivered_deposits_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["pipeline", "undelivered-deposits"])
    assert result.exit_code == 0, result.output
    assert "không có" in result.output


# ---------------------------------------------------------------------------
# cancelled-unrefunded
# ---------------------------------------------------------------------------


def test_cancelled_unrefunded_lists_unrefunded_orders():
    with get_db() as conn:
        ensure_schema(conn)
        # Cancelled order: 500k deposit, 200k refunded → 300k unrefunded.
        oid = _insert_order(
            conn, order_ref="ORD-260624-010", customer_name="Chị X",
            total_price=1000000, status="cancelled", due_date="2026-06-15",
        )
        _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _insert_payment(conn, order_id=oid, amount=200000, ptype="refund")
        # Cancelled order fully refunded → excluded.
        full_id = _insert_order(
            conn, order_ref="ORD-260624-011", customer_name="Chị Y",
            total_price=800000, status="cancelled", due_date="2026-06-16",
        )
        _insert_payment(conn, order_id=full_id, amount=300000, ptype="deposit")
        _insert_payment(conn, order_id=full_id, amount=300000, ptype="refund")
        # Active (non-cancelled) order with deposit → excluded.
        active_id = _insert_order(
            conn, order_ref="ORD-260624-012", customer_name="Chị Z",
            total_price=900000, status="confirmed", due_date="2026-06-30",
        )
        _insert_payment(conn, order_id=active_id, amount=900000, ptype="deposit")

    result = _invoke(["pipeline", "cancelled-unrefunded"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-010" in result.output
    assert "Chị X" in result.output
    assert "500.000" in result.output
    assert "200.000" in result.output
    assert "300.000" in result.output  # net unrefunded
    assert "ORD-260624-011" not in result.output  # fully refunded
    assert "ORD-260624-012" not in result.output  # not cancelled


def test_cancelled_unrefunded_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["pipeline", "cancelled-unrefunded"])
    assert result.exit_code == 0, result.output
    assert "không có" in result.output


# ---------------------------------------------------------------------------
# deposit-revenue-gap
# ---------------------------------------------------------------------------


def test_deposit_revenue_gap_surfaces_mismatch():
    with get_db() as conn:
        ensure_schema(conn)
        deposits_acc = _account_id(conn, "2100")
        revenue_acc = _account_id(conn, "4100")
        # Delivered order: 500k deposit (net = 500k, no refund), revenue entry
        # debits 2100 for 500k — no mismatch (baseline).
        oid1 = _insert_order(
            conn, order_ref="ORD-260624-020", customer_name="Khách 1",
            total_price=500000, status="delivered", due_date="2026-06-10",
        )
        _insert_payment(conn, order_id=oid1, amount=500000, ptype="deposit")
        _insert_revenue_entry(
            conn, order_id=oid1, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=500000,
        )
        # Delivered order: 500k deposit + 200k tien_rut (refund). Net deposits
        # = 500k − 200k = 300k (Phase 4.3 net semantics). The stale revenue
        # entry debits 2100 for 700k (the old gross double-debit bug), so the
        # gap is 300k − 700k = -400k.
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-021", customer_name="Khách 2",
            total_price=700000, status="delivered", due_date="2026-06-12",
        )
        _insert_payment(conn, order_id=oid2, amount=500000, ptype="deposit")
        _insert_payment(conn, order_id=oid2, amount=200000, ptype="tien_rut")
        _insert_revenue_entry(
            conn, order_id=oid2, deposits_account_id=deposits_acc,
            revenue_account_id=revenue_acc, amount=700000,
        )

    result = _invoke(["pipeline", "deposit-revenue-gap"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-020" in result.output
    # Order 2: net deposits 300k, debit 2100 = 700k, gap = -400k
    assert "ORD-260624-021" in result.output
    assert "700.000" in result.output  # 2100 debit for the buggy order
    assert "300.000" in result.output  # net deposits (500k − 200k)
    # Aggregate gap = (500k - 500k) + (300k - 700k) = -400k
    assert "-400.000" in result.output
    assert "Số đơn lệch" in result.output
    assert "2/2" not in result.output  # order 1 has no mismatch
    assert "1/2" in result.output  # only order 2 mismatches


def test_deposit_revenue_gap_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["pipeline", "deposit-revenue-gap"])
    assert result.exit_code == 0, result.output
    assert "không có" in result.output


# ---------------------------------------------------------------------------
# refunds
# ---------------------------------------------------------------------------


def test_refunds_lists_outflow_transactions():
    """`refunds` lists both `tien_rut` and `refund` outflow transactions (Mn-3)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(
            conn, order_ref="ORD-260624-030", customer_name="Anh R",
            total_price=1000000, status="delivered", due_date="2026-06-10",
        )
        _insert_payment(conn, order_id=oid, amount=1000000, ptype="deposit")
        _insert_payment(
            conn, order_id=oid, amount=300000, ptype="tien_rut", method="cash",
            created_at="2026-06-12T09:00:00",
        )
        # A `refund` outflow should also appear now (Mn-3 parameterization).
        oid2 = _insert_order(
            conn, order_ref="ORD-260624-031", customer_name="Anh N",
            total_price=500000, status="delivered", due_date="2026-06-11",
        )
        _insert_payment(
            conn, order_id=oid2, amount=500000, ptype="refund",
            created_at="2026-06-13T09:00:00",
        )
        # A `deposit` payment is NOT an outflow and must NOT appear.
        oid3 = _insert_order(
            conn, order_ref="ORD-260624-032", customer_name="Anh D",
            total_price=400000, status="delivered", due_date="2026-06-14",
        )
        _insert_payment(conn, order_id=oid3, amount=400000, ptype="deposit")

    result = _invoke(["pipeline", "refunds"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-030" in result.output
    assert "Anh R" in result.output
    assert "300.000" in result.output
    assert "tien_rut" in result.output
    # `refund` outflow now appears (Mn-3 fix).
    assert "ORD-260624-031" in result.output
    assert "refund" in result.output
    assert "500.000" in result.output
    # A non-outflow deposit must NOT appear.
    assert "ORD-260624-032" not in result.output


def test_refunds_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["pipeline", "refunds"])
    assert result.exit_code == 0, result.output
    assert "không có" in result.output


# ---------------------------------------------------------------------------
# new-no-deposit
# ---------------------------------------------------------------------------


def test_new_no_deposit_lists_orders_without_deposits():
    with get_db() as conn:
        ensure_schema(conn)
        # New order, no payments → should appear.
        _insert_order(
            conn, order_ref="ORD-260624-040", customer_name="Khách M",
            total_price=600000, status="new", due_date="2026-07-02",
        )
        # Confirmed order with no payments → should appear.
        _insert_order(
            conn, order_ref="ORD-260624-041", customer_name="Khách C",
            total_price=450000, status="confirmed", due_date="2026-07-03",
        )
        # New order WITH a deposit → excluded.
        paid_id = _insert_order(
            conn, order_ref="ORD-260624-042", customer_name="Khách P",
            total_price=700000, status="new", due_date="2026-07-04",
        )
        _insert_payment(conn, order_id=paid_id, amount=300000, ptype="deposit")
        # Delivered order with no payments → excluded (not new/confirmed).
        _insert_order(
            conn, order_ref="ORD-260624-043", customer_name="Khách D",
            total_price=800000, status="delivered", due_date="2026-06-20",
        )

    result = _invoke(["pipeline", "new-no-deposit"])
    assert result.exit_code == 0, result.output
    assert "ORD-260624-040" in result.output
    assert "ORD-260624-041" in result.output
    assert "600.000" in result.output
    assert "450.000" in result.output
    assert "ORD-260624-042" not in result.output  # has deposit
    assert "ORD-260624-043" not in result.output  # delivered, not new


def test_new_no_deposit_empty_db():
    with get_db() as conn:
        ensure_schema(conn)
    result = _invoke(["pipeline", "new-no-deposit"])
    assert result.exit_code == 0, result.output
    assert "không có" in result.output


# ---------------------------------------------------------------------------
# VN amount formatting
# ---------------------------------------------------------------------------


def test_vn_amount_formatting():
    from baker.commands.pipeline import _vn_amount

    assert _vn_amount(0) == "0"
    assert _vn_amount(500000) == "500.000"
    assert _vn_amount(1500000) == "1.500.000"
    assert _vn_amount(548000000) == "548.000.000"
    assert _vn_amount(-200000) == "-200.000"