"""Tests for ``baker repair-tien-rut-gap`` CLI command — DG-198 reversal backfill
(FR4, AC4).

Covers:

- ``--all`` detects and backfills orders whose ``tien_rut`` journal entry
  debited 2100 (pre-fix outflow state) instead of crediting 2400 (the current
  deposit-inflow routing).
- ``--order-id`` backfills a single affected order.
- ``--dry-run`` reports the gap without mutating.
- Idempotency: a second run is a no-op (NFR3).
- Non-affected orders (no tien_rut, or already crediting 2400) are skipped.
- AC4: after backfill each order has 2400 credited at payment time (inflow)
  and a separate tien rut return entry (DR 2400 / CR Asset) at delivery, plus
  a deposits→revenue entry (DR 2100 / CR 4100).
- Command registration / ``--help``.
- Service-level helper coverage (``_process_tien_rut_gap_order``).
"""

import click
import click.testing

from baker.cli import app
from baker.commands.repair import (
    _process_tien_rut_gap_order,
    _tien_rut_orders_needing_backfill,
)
from baker.db.connection import get_db
from baker.db.schema import (
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    TIEN_RUT_HELD_CODE,
    ensure_schema,
)
from baker.services.journal_sync import _sync_delivered_order_journal


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
    total_price: float = 700000.0,
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


def _insert_prefixed_tien_rut_journal(
    conn,
    *,
    txn_id: int,
    amount: float,
    method: str = "cash",
) -> int:
    """Insert a PRE-FIX tien_rut journal entry that debits 2100 (the old,
    broken outflow routing) instead of crediting 2400.

    This simulates the state of the 8 existing orders before the DG-198
    reversal: the ``tien_rut`` payment transaction exists, its journal entry
    debits 2100 (Customer Deposits) and credits the asset account (treated as
    an outflow), leaving 2100 overdrawn and 2400 empty.
    """
    asset_code = "1100" if method == "cash" else "1200"
    asset_acc = _account_id(conn, asset_code)
    deposits_acc = _account_id(conn, CUSTOMER_DEPOSITS_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'payment_transaction', ?)",
        (f"Payment: tien_rut {amount}", txn_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Hoàn tiền khách')",
        (entry_id, deposits_acc, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Trả lại tiền')",
        (entry_id, asset_acc, amount),
    )
    return entry_id


def _insert_stale_revenue_entry(
    conn,
    *,
    order_id: int,
    order_ref: str,
    deposit_balance: float,
) -> int:
    """Insert a PRE-FIX revenue entry that debits 2100 and credits 4100 for the
    full deposit balance, with NO 2400 credit line.

    This mirrors the pre-reversal revenue entry for orders with tien_rut: the
    2100 debit cleared the full deposit balance, but 2400 was never cleared
    via a separate return entry.
    """
    deposits_acc = _account_id(conn, CUSTOMER_DEPOSITS_CODE)
    revenue_acc = _account_id(conn, ORDER_REVENUE_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order', ?)",
        (f"Order revenue: {order_ref}", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Chuyển cọc sang doanh thu')",
        (entry_id, deposits_acc, deposit_balance),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Doanh thu bán hàng')",
        (entry_id, revenue_acc, deposit_balance),
    )
    return entry_id


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _payment_journal_2400_credit(conn, txn_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.credit), 0) AS c
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'payment_transaction' AND je.source_id = ?
          AND a.code = ?
        """,
        (txn_id, TIEN_RUT_HELD_CODE),
    ).fetchone()
    return float(row["c"] or 0)


def _payment_journal_2100_debit(conn, txn_id: int) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0) AS d
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'payment_transaction' AND je.source_id = ?
          AND a.code = ?
        """,
        (txn_id, CUSTOMER_DEPOSITS_CODE),
    ).fetchone()
    return float(row["d"] or 0)


def _tien_rut_return_entry(conn, order_id: int) -> dict:
    """Return the tien rut return entry lines (DR 2400 / CR Asset)."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ?
          AND je.description LIKE 'Tien rut return:%'
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _revenue_entry(conn, order_id: int) -> dict:
    """Return the deposits→revenue entry lines (DR 2100 / CR 4100)."""
    rows = conn.execute(
        """
        SELECT a.code AS code, jl.debit AS debit, jl.credit AS credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ?
          AND je.description LIKE 'Order revenue:%'
        """,
        (order_id,),
    ).fetchall()
    out: dict[str, dict[str, float]] = {}
    for r in rows:
        out[r["code"]] = {"debit": float(r["debit"] or 0), "credit": float(r["credit"] or 0)}
    return out


def _seed_gap_order(
    conn,
    *,
    order_ref: str,
    deposit: float = 500000.0,
    tien_rut: float = 300000.0,
    total_price: float = 700000.0,
    status: str = "delivered",
) -> tuple[int, int]:
    """Seed an order in the PRE-FIX state: deposit journaled normally, tien_rut
    journaled to 2100 (broken), revenue entry without 2400 (broken).

    Returns (order_id, tien_rut_txn_id).
    """
    oid = _insert_order(conn, order_ref=order_ref, total_price=total_price, status=status)
    # Deposit payment + journal entry (correct routing — unaffected by backfill).
    dep_txn = _insert_payment(conn, order_id=oid, amount=deposit, ptype="deposit")
    from baker.services.journal_sync import _sync_payment_journal

    _sync_payment_journal(conn, dep_txn, deposit, "deposit", "cash", order_id=oid)
    # tien_rut payment + PRE-FIX journal entry (debits 2100 — the gap).
    rut_txn = _insert_payment(conn, order_id=oid, amount=tien_rut, ptype="tien_rut")
    _insert_prefixed_tien_rut_journal(conn, txn_id=rut_txn, amount=tien_rut)
    # Stale revenue entry: debits 2100 for the full deposit balance, credits
    # 4100, no 2400 line (pre-Phase-4).
    _insert_stale_revenue_entry(
        conn, order_id=oid, order_ref=order_ref, deposit_balance=deposit
    )
    return oid, rut_txn


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_repair_tien_rut_gap_registered():
    result = _invoke(["repair-tien-rut-gap", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_repair_tien_rut_gap_requires_one_mode():
    result = _invoke(["repair-tien-rut-gap"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_repair_tien_rut_gap_rejects_both_modes():
    result = _invoke(["repair-tien-rut-gap", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# Detection — _tien_rut_orders_needing_backfill
# ---------------------------------------------------------------------------


def test_detection_finds_orders_with_prefixed_tien_rut():
    with get_db() as conn:
        ensure_schema(conn)
        oid, _ = _seed_gap_order(conn, order_ref="GAP-DET-1")
        affected = _tien_rut_orders_needing_backfill(conn)
        assert oid in affected
        conn.commit()


def test_detection_excludes_orders_without_tien_rut():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="GAP-DET-2", total_price=500000)
        dep = _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal

        _sync_payment_journal(conn, dep, 500000, "deposit", "cash", order_id=oid)
        affected = _tien_rut_orders_needing_backfill(conn)
        assert oid not in affected
        conn.commit()


def test_detection_excludes_orders_already_on_2400():
    """An order whose tien_rut already credits 2400 is NOT affected (already fixed)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="GAP-DET-3", total_price=700000)
        from baker.services.journal_sync import _sync_payment_journal

        dep = _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        _sync_payment_journal(conn, dep, 500000, "deposit", "cash", order_id=oid)
        rut = _insert_payment(conn, order_id=oid, amount=300000, ptype="tien_rut")
        # Correct (post-reversal) routing: credits 2400 (deposit inflow).
        _sync_payment_journal(conn, rut, 300000, "tien_rut", "cash", order_id=oid)
        affected = _tien_rut_orders_needing_backfill(conn)
        assert oid not in affected
        conn.commit()


# ---------------------------------------------------------------------------
# AC4 — backfill fixes the gap (2400 credited, separate return + revenue entries)
# ---------------------------------------------------------------------------


def test_backfill_all_clears_2400_and_balances_revenue():
    """AC4: a gap order backfilled via ``--all`` ends with the tien_rut payment
    journal entry crediting 2400 (not debiting 2100), plus a separate tien rut
    return entry (DR 2400 / CR Asset) and a deposits→revenue entry
    (DR 2100 / CR 4100)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid, rut_txn = _seed_gap_order(
            conn, order_ref="GAP-AC4-1", deposit=500000, tien_rut=300000
        )
        # Pre-state: tien_rut journal debits 2100, 2400 untouched.
        assert _payment_journal_2100_debit(conn, rut_txn) == 300000.0
        assert _payment_journal_2400_credit(conn, rut_txn) == 0.0
        conn.commit()

    result = _invoke(["repair-tien-rut-gap", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        # Post-state: tien_rut journal now credits 2400, 2100 untouched.
        assert _payment_journal_2400_credit(conn, rut_txn) == 300000.0
        assert _payment_journal_2100_debit(conn, rut_txn) == 0.0
        # Revenue entry: debit 2100 500k, credit 4100 500k (deposits only).
        rev = _revenue_entry(conn, oid)
        assert rev[CUSTOMER_DEPOSITS_CODE]["debit"] == 500000.0
        assert rev[ORDER_REVENUE_CODE]["credit"] == 500000.0
        assert TIEN_RUT_HELD_CODE not in rev
        # Tien rut return entry: debit 2400 300k, credit 1100 300k.
        ret = _tien_rut_return_entry(conn, oid)
        assert ret[TIEN_RUT_HELD_CODE]["debit"] == 300000.0
        assert ret["1100"]["credit"] == 300000.0


def test_backfill_single_order_id():
    with get_db() as conn:
        ensure_schema(conn)
        oid, _ = _seed_gap_order(conn, order_ref="GAP-AC4-2")
        conn.commit()

    result = _invoke(["repair-tien-rut-gap", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ret = _tien_rut_return_entry(conn, oid)
        assert ret[TIEN_RUT_HELD_CODE]["debit"] == 300000.0


def test_backfill_single_order_id_not_affected_reports_empty():
    """--order-id on an order without the gap reports no work (not an error)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="GAP-AC4-3", total_price=500000)
        dep = _insert_payment(conn, order_id=oid, amount=500000, ptype="deposit")
        from baker.services.journal_sync import _sync_payment_journal

        _sync_payment_journal(conn, dep, 500000, "deposit", "cash", order_id=oid)
        conn.commit()

    result = _invoke(["repair-tien-rut-gap", "--order-id", str(oid)])
    assert result.exit_code == 0, result.output
    assert "không có đơn hàng nào" in result.output


# ---------------------------------------------------------------------------
# Dry-run — no mutation
# ---------------------------------------------------------------------------


def test_dry_run_reports_gap_without_mutating():
    with get_db() as conn:
        ensure_schema(conn)
        oid, rut_txn = _seed_gap_order(conn, order_ref="GAP-DRY-1")
        conn.commit()

    result = _invoke(["repair-tien-rut-gap", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        # No mutation: tien_rut journal still debits 2100, 2400 still empty.
        assert _payment_journal_2100_debit(conn, rut_txn) == 300000.0
        assert _payment_journal_2400_credit(conn, rut_txn) == 0.0
        # Stale revenue entry untouched: no 2400 credit, no return entry.
        assert _tien_rut_return_entry(conn, oid) == {}


# ---------------------------------------------------------------------------
# Idempotency (NFR3)
# ---------------------------------------------------------------------------


def test_backfill_is_idempotent():
    """Running the backfill twice produces the same result; the second run is a
    no-op (no orders detected)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid, rut_txn = _seed_gap_order(conn, order_ref="GAP-IDEM-1")
        conn.commit()

    r1 = _invoke(["repair-tien-rut-gap", "--all"])
    assert r1.exit_code == 0, r1.output

    with get_db() as conn:
        first_2400 = _payment_journal_2400_credit(conn, rut_txn)
        first_rev = _revenue_entry(conn, oid)
        first_ret = _tien_rut_return_entry(conn, oid)
        conn.commit()

    # Second run: detection should return no affected orders.
    r2 = _invoke(["repair-tien-rut-gap", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "không có đơn hàng nào" in r2.output

    with get_db() as conn:
        assert _payment_journal_2400_credit(conn, rut_txn) == first_2400
        assert _revenue_entry(conn, oid) == first_rev
        assert _tien_rut_return_entry(conn, oid) == first_ret


def test_process_tien_rut_gap_order_idempotent_service_level():
    """Calling _process_tien_rut_gap_order twice yields identical journal state."""
    with get_db() as conn:
        ensure_schema(conn)
        oid, rut_txn = _seed_gap_order(conn, order_ref="GAP-IDEM-2")
        _process_tien_rut_gap_order(conn, oid, dry_run=False)
        first_2400 = _payment_journal_2400_credit(conn, rut_txn)
        first_rev = _revenue_entry(conn, oid)
        first_ret = _tien_rut_return_entry(conn, oid)
        # Second call: detection already excludes the order, so re-applying the
        # service function on the same order must not change anything (the
        # sync helpers are idempotent).
        _process_tien_rut_gap_order(conn, oid, dry_run=False)
        assert _payment_journal_2400_credit(conn, rut_txn) == first_2400
        assert _revenue_entry(conn, oid) == first_rev
        assert _tien_rut_return_entry(conn, oid) == first_ret
        conn.commit()


# ---------------------------------------------------------------------------
# Dry-run service-level helper
# ---------------------------------------------------------------------------


def test_process_tien_rut_gap_order_dry_run_no_mutation():
    with get_db() as conn:
        ensure_schema(conn)
        oid, rut_txn = _seed_gap_order(conn, order_ref="GAP-SVC-1")
        result = _process_tien_rut_gap_order(conn, oid, dry_run=True)
        assert result["action"] == "will-backfill"
        assert result["tien_rut_total"] == 300000.0
        # No mutation occurred.
        assert _payment_journal_2400_credit(conn, rut_txn) == 0.0
        conn.commit()


# ---------------------------------------------------------------------------
# Double-entry integrity after backfill
# ---------------------------------------------------------------------------


def test_backfill_preserves_double_entry_integrity():
    with get_db() as conn:
        ensure_schema(conn)
        _seed_gap_order(conn, order_ref="GAP-INT-1", deposit=500000, tien_rut=300000)
        _seed_gap_order(conn, order_ref="GAP-INT-2", deposit=400000, tien_rut=400000)
        conn.commit()

    result = _invoke(["repair-tien-rut-gap", "--all"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        rows = conn.execute(
            """
            SELECT je.id, SUM(jl.debit) AS td, SUM(jl.credit) AS tc
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            GROUP BY je.id
            """
        ).fetchall()
        assert len(rows) > 0
        for row in rows:
            assert abs(float(row["td"]) - float(row["tc"])) < 0.005, (
                f"Entry {row['id']}: debit {row['td']} != credit {row['tc']}"
            )