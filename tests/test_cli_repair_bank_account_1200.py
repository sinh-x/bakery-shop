"""Tests for ``baker repair-bank-account-1200`` — DG-285 Phase 2 historical
credit-side journal repair (FR3, FR4, FR5, AC3, AC4).

Covers:
  - ``--all`` re-points ``tien_rut`` return entries (``source_type='order'``)
    whose credit-side asset line is on 1200 to 1290 (FR3, AC3).
  - ``--all`` re-points ``refund`` payment-transaction entries whose
    credit-side asset line is on 1200 to 1290 (FR4, AC4).
  - Idempotent: a second run finds nothing to repair (FR5).
  - Entries whose credit side is already on 1290 (or any non-1200 code) are
    skipped.
  - ``--order-id`` scopes to a single order.
  - ``--dry-run`` reports planned actions without mutating.
  - Locked entries are reversed + recreated (no double-entry).
  - Reversal entries (``description LIKE 'Reversal:%'``) are excluded.
  - Command registration / ``--help`` / arg validation.
  - Vietnamese labels in the report.
  - 1200 balance decreases by the moved amount after the repair.
"""

import json

import click
import click.testing

from baker.cli import app
from baker.commands.repair import (
    _expense_entries_on_1200,
    _refund_entries_on_1200,
    _tien_rut_return_entries_on_1200,
)
from baker.db.connection import get_db
from baker.db.schema import (
    CUSTOMER_DEPOSITS_CODE,
    TIEN_RUT_HELD_CODE,
    UNALLOCATED_BANK_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _TIEN_RUT_RETURN_PREFIX,
    _sync_payment_journal,
)


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
    status: str = "delivered",
    due_date: str | None = "2026-06-10",
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
) -> int:
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date, "
        "delivery_type, shipping_fee) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date, delivery_type, shipping_fee),
    )
    return int(cur.lastrowid)


def _insert_payment(
    conn,
    *,
    order_id: int,
    amount: float,
    ptype: str = "deposit",
    method: str = "cash",
    payment_source: str = "",
) -> int:
    cur = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, payment_source) "
        "VALUES (?, ?, ?, ?, ?)",
        (order_id, amount, ptype, method, payment_source),
    )
    return int(cur.lastrowid)


def _insert_tien_rut_return_entry_on(
    conn,
    *,
    order_id: int,
    order_ref: str,
    amount: float,
    asset_code: str,
) -> int:
    """Insert a ``Tien rut return:`` order journal entry whose credit (asset)
    line references ``asset_code``. Mirrors the structure produced by
    ``_reconcile_tien_rut_return_entry``.
    """
    asset_acc = _account_id(conn, asset_code)
    tien_rut_acc = _account_id(conn, TIEN_RUT_HELD_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'order', ?)",
        (f"{_TIEN_RUT_RETURN_PREFIX} {order_ref}", order_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Trả tiền rút cho khách')",
        (entry_id, tien_rut_acc, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Tiền rút đã trả')",
        (entry_id, asset_acc, amount),
    )
    return entry_id


def _insert_refund_journal_entry_on(
    conn,
    *,
    txn_id: int,
    amount: float,
    asset_code: str,
) -> int:
    """Insert a refund ``payment_transaction`` journal entry whose credit
    (asset) line references ``asset_code``. Mirrors the structure produced by
    ``_build_payment_journal_lines`` for the outflow path.
    """
    asset_acc = _account_id(conn, asset_code)
    deposits_acc = _account_id(conn, CUSTOMER_DEPOSITS_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'payment_transaction', ?)",
        (f"Payment: refund {amount}", txn_id),
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


def _insert_expense_event(
    conn,
    *,
    event_id: int | None = None,
    payment_source: str = "TK Ân VCB",
    amount_vnd: float = 500000.0,
    category: str = "Vận chuyển",
    summary: str = "Chi phí thử",
    data_override: dict | None = None,
) -> int:
    """Insert an ``expense`` event row and return its id.

    ``data_override`` (if provided) replaces the default ``data`` JSON — used
    by the malformed/missing-field tests.
    """
    data = {
        "payment_source": payment_source,
        "amount_vnd": amount_vnd,
        "category": category,
    }
    if data_override is not None:
        data = data_override
    cur = conn.execute(
        "INSERT INTO events (type, summary, data, timestamp) "
        "VALUES ('expense', ?, ?, datetime('now'))",
        (summary, json.dumps(data)),
    )
    return int(cur.lastrowid)


def _insert_expense_journal_entry_on(
    conn,
    *,
    event_id: int,
    amount: float,
    asset_code: str,
    locked: bool = False,
) -> int:
    """Insert an ``expense`` journal entry whose credit (asset) line references
    ``asset_code``. Mirrors the structure produced by
    ``_build_expense_journal_lines``.
    """
    asset_acc = _account_id(conn, asset_code)
    expense_acc = _account_id(conn, "5300")
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'expense', ?)",
        (f"Expense: Chi phí thử", event_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Chi phí')",
        (entry_id, expense_acc, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Thanh toán')",
        (entry_id, asset_acc, amount),
    )
    if locked:
        conn.execute(
            "UPDATE journal_entries SET locked_at = datetime('now') WHERE id = ?",
            (entry_id,),
        )
    return entry_id


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _entry_credit_code(conn, entry_id: int) -> str | None:
    row = conn.execute(
        """
        SELECT a.code AS code
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE jl.journal_entry_id = ? AND jl.credit > 0
        ORDER BY jl.id LIMIT 1
        """,
        (entry_id,),
    ).fetchone()
    return row["code"] if row else None


def _latest_non_reversal_entry(conn, source_type: str, source_id: int) -> int | None:
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = ? AND source_id = ? "
        "AND description NOT LIKE 'Reversal:%' "
        "ORDER BY id DESC LIMIT 1",
        (source_type, source_id),
    ).fetchone()
    return int(row["id"]) if row else None


def _account_net_balance(conn, code: str) -> float:
    """Return the net balance (debits − credits) for an account code."""
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS net
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = ?
        """,
        (code,),
    ).fetchone()
    return float(row["net"] or 0)


# ---------------------------------------------------------------------------
# Registration & help / arg validation
# ---------------------------------------------------------------------------


def test_repair_bank_account_1200_registered():
    result = _invoke(["repair-bank-account-1200", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output
    assert "1290" in result.output


def test_repair_bank_account_1200_requires_one_mode():
    result = _invoke(["repair-bank-account-1200"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_repair_bank_account_1200_rejects_both_modes():
    result = _invoke(["repair-bank-account-1200", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# Detection helpers
# ---------------------------------------------------------------------------


def test_detection_finds_tien_rut_return_on_1200():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-DET-1", total_price=200000)
        _insert_tien_rut_return_entry_on(
            conn, order_id=oid, order_ref="BA-DET-1", amount=200000, asset_code="1200",
        )
        found = _tien_rut_return_entries_on_1200(conn)
        assert len(found) == 1
        assert found[0]["order_id"] == oid
        assert found[0]["kind"] == "tien_rut_return"
        assert found[0]["amount"] == 200000.0


def test_detection_excludes_tien_rut_return_already_on_1290():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-DET-2", total_price=200000)
        _insert_tien_rut_return_entry_on(
            conn, order_id=oid, order_ref="BA-DET-2", amount=200000, asset_code="1290",
        )
        assert _tien_rut_return_entries_on_1200(conn) == []


def test_detection_finds_refund_on_1200():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-DET-3", total_price=100000)
        txn = _insert_payment(
            conn, order_id=oid, amount=100000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn, amount=100000, asset_code="1200")
        found = _refund_entries_on_1200(conn)
        assert len(found) == 1
        assert found[0]["txn_id"] == txn
        assert found[0]["kind"] == "refund"


def test_detection_excludes_refund_already_on_1290():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-DET-4", total_price=100000)
        txn = _insert_payment(
            conn, order_id=oid, amount=100000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn, amount=100000, asset_code="1290")
        assert _refund_entries_on_1200(conn) == []


def test_detection_excludes_reversal_entries():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-DET-5", total_price=200000)
        asset_acc = _account_id(conn, "1200")
        tien_rut_acc = _account_id(conn, TIEN_RUT_HELD_CODE)
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, 'order', ?)",
            (f"Reversal: {_TIEN_RUT_RETURN_PREFIX} BA-DET-5", oid),
        )
        entry_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, ?, 'reverse')",
            (entry_id, tien_rut_acc, 200000),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, 0.0, 'reverse')",
            (entry_id, asset_acc, 200000),
        )
        assert _tien_rut_return_entries_on_1200(conn) == []


# ---------------------------------------------------------------------------
# AC3 — tien_rut return entries repaired to 1290
# ---------------------------------------------------------------------------


def test_all_repairs_tien_rut_return_to_1290():
    """AC3: a historical tien rut return entry crediting 1200 is re-pointed
    to 1290 after running ``--all``."""
    with get_db() as conn:
        ensure_schema(conn)
        oid_a = _insert_order(conn, order_ref="BA-AC3-A", total_price=2000000)
        oid_b = _insert_order(conn, order_ref="BA-AC3-B", total_price=4000000)
        # Seed a deposit + tien_rut payment so the re-sync has the source
        # data needed to rebuild the return entry via the single source of
        # truth.
        dep_a = _insert_payment(
            conn, order_id=oid_a, amount=2000000, ptype="deposit", method="transfer",
        )
        _sync_payment_journal(conn, dep_a, 2000000, "deposit", "transfer", order_id=oid_a)
        rut_a = _insert_payment(
            conn, order_id=oid_a, amount=2000000, ptype="tien_rut", method="transfer",
        )
        _sync_payment_journal(conn, rut_a, 2000000, "tien_rut", "transfer", order_id=oid_a)
        dep_b = _insert_payment(
            conn, order_id=oid_b, amount=4000000, ptype="deposit", method="transfer",
        )
        _sync_payment_journal(conn, dep_b, 4000000, "deposit", "transfer", order_id=oid_b)
        rut_b = _insert_payment(
            conn, order_id=oid_b, amount=4000000, ptype="tien_rut", method="transfer",
        )
        _sync_payment_journal(conn, rut_b, 4000000, "tien_rut", "transfer", order_id=oid_b)
        # Mark both orders delivered so the delivered-order journal can
        # rebuild the return entry.
        conn.execute("UPDATE orders SET status = 'delivered' WHERE id IN (?, ?)", (oid_a, oid_b))
        # Insert a delivered event so ``_resolve_delivered_timestamp`` finds one.
        import json
        for oid, ref in ((oid_a, "BA-AC3-A"), (oid_b, "BA-AC3-B")):
            conn.execute(
                "INSERT INTO events (type, order_id, timestamp, summary, data) "
                "VALUES ('order', ?, datetime('now'), ?, ?)",
                (oid, f"Deliver {ref}", json.dumps({"order_ref": ref, "to_status": "delivered"})),
            )
        # Build the correct return entry, then deliberately re-point its
        # credit line to 1200 to simulate the historical broken state.
        from baker.services.journal_sync import _reconcile_order_revenue_entry
        _reconcile_order_revenue_entry(conn, oid_a, "BA-AC3-A", respect_locks=True)
        _reconcile_order_revenue_entry(conn, oid_b, "BA-AC3-B", respect_locks=True)
        for oid, ref, amount in ((oid_a, "BA-AC3-A", 2000000), (oid_b, "BA-AC3-B", 4000000)):
            entry_id = _latest_non_reversal_entry(conn, "order", oid)
            assert entry_id is not None
            # Rewrite the credit (asset) line onto 1200 to simulate legacy.
            asset_acc_1290 = _account_id(conn, UNALLOCATED_BANK_CODE)
            asset_acc_1200 = _account_id(conn, "1200")
            conn.execute(
                "UPDATE journal_lines SET account_id = ? "
                "WHERE journal_entry_id = ? AND account_id = ? AND credit > 0",
                (asset_acc_1200, entry_id, asset_acc_1290),
            )
            assert _entry_credit_code(conn, entry_id) == "1200"
        conn.commit()

    result = _invoke(["repair-bank-account-1200", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        for oid in (oid_a, oid_b):
            entry_id = _latest_non_reversal_entry(conn, "order", oid)
            assert _entry_credit_code(conn, entry_id) == UNALLOCATED_BANK_CODE


# ---------------------------------------------------------------------------
# AC4 — refund entry repaired to 1290
# ---------------------------------------------------------------------------


def test_all_repairs_refund_to_1290():
    """AC4: a historical refund entry (transfer, no source) crediting 1200
    is re-pointed to 1290."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-AC4", total_price=10000)
        txn = _insert_payment(
            conn, order_id=oid, amount=10000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn, amount=10000, asset_code="1200")
        assert _entry_credit_code(
            conn, _latest_non_reversal_entry(conn, "payment_transaction", txn)
        ) == "1200"
        conn.commit()

    result = _invoke(["repair-bank-account-1200", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _latest_non_reversal_entry(conn, "payment_transaction", txn)
        assert _entry_credit_code(conn, entry_id) == UNALLOCATED_BANK_CODE


# ---------------------------------------------------------------------------
# AC3 balance assertion — 1200 balance decreases by 6,000,000
# ---------------------------------------------------------------------------


def test_1200_balance_decreases_for_tien_rut_returns():
    """AC3: after repairing both tien rut return entries the 1200 account
    balance decreases by 6,000,000 (2M + 4M)."""
    with get_db() as conn:
        ensure_schema(conn)
        oid_a = _insert_order(conn, order_ref="BA-BAL-A", total_price=2000000)
        oid_b = _insert_order(conn, order_ref="BA-BAL-B", total_price=4000000)
        for oid, ref, amt in (
            (oid_a, "BA-BAL-A", 2000000), (oid_b, "BA-BAL-B", 4000000),
        ):
            dep = _insert_payment(
                conn, order_id=oid, amount=amt, ptype="deposit", method="transfer",
            )
            _sync_payment_journal(conn, dep, amt, "deposit", "transfer", order_id=oid)
            rut = _insert_payment(
                conn, order_id=oid, amount=amt, ptype="tien_rut", method="transfer",
            )
            _sync_payment_journal(conn, rut, amt, "tien_rut", "transfer", order_id=oid)
        conn.execute(
            "UPDATE orders SET status = 'delivered' WHERE id IN (?, ?)", (oid_a, oid_b)
        )
        import json
        for oid, ref in ((oid_a, "BA-BAL-A"), (oid_b, "BA-BAL-B")):
            conn.execute(
                "INSERT INTO events (type, order_id, timestamp, summary, data) "
                "VALUES ('order', ?, datetime('now'), ?, ?)",
                (oid, f"Deliver {ref}", json.dumps({"order_ref": ref, "to_status": "delivered"})),
            )
        from baker.services.journal_sync import _reconcile_order_revenue_entry
        _reconcile_order_revenue_entry(conn, oid_a, "BA-BAL-A", respect_locks=True)
        _reconcile_order_revenue_entry(conn, oid_b, "BA-BAL-B", respect_locks=True)
        asset_acc_1290 = _account_id(conn, UNALLOCATED_BANK_CODE)
        asset_acc_1200 = _account_id(conn, "1200")
        for oid in (oid_a, oid_b):
            entry_id = _latest_non_reversal_entry(conn, "order", oid)
            conn.execute(
                "UPDATE journal_lines SET account_id = ? "
                "WHERE journal_entry_id = ? AND account_id = ? AND credit > 0",
                (asset_acc_1200, entry_id, asset_acc_1290),
            )
        conn.commit()
        balance_before = _account_net_balance(conn, "1200")

    result = _invoke(["repair-bank-account-1200", "--all"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        ensure_schema(conn)
        balance_after = _account_net_balance(conn, "1200")
        # The 6,000,000 credit lines that were incorrectly on 1200 move to
        # 1290, so the 1200 balance moves 6,000,000 toward zero (the
        # magnitude of any negative balance shrinks by 6,000,000).
        delta = balance_after - balance_before
        assert abs(delta - 6000000) < 0.005


# ---------------------------------------------------------------------------
# Idempotency (FR5)
# ---------------------------------------------------------------------------


def test_idempotent_second_run_is_noop():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-IDEM", total_price=10000)
        txn = _insert_payment(
            conn, order_id=oid, amount=10000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn, amount=10000, asset_code="1200")
        conn.commit()

    r1 = _invoke(["repair-bank-account-1200", "--all"])
    assert r1.exit_code == 0, r1.output
    assert "đã sửa" in r1.output

    r2 = _invoke(["repair-bank-account-1200", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "không có bút toán nào cần chuyển sang TK 1290" in r2.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _latest_non_reversal_entry(conn, "payment_transaction", txn)
        assert _entry_credit_code(conn, entry_id) == UNALLOCATED_BANK_CODE


# ---------------------------------------------------------------------------
# --order-id scope
# ---------------------------------------------------------------------------


def test_order_id_scoped_repair():
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(conn, order_ref="BA-SCO-1", total_price=15000)
        oid2 = _insert_order(conn, order_ref="BA-SCO-2", total_price=25000)
        txn1 = _insert_payment(
            conn, order_id=oid1, amount=15000, ptype="refund", method="transfer",
        )
        txn2 = _insert_payment(
            conn, order_id=oid2, amount=25000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn1, amount=15000, asset_code="1200")
        _insert_refund_journal_entry_on(conn, txn_id=txn2, amount=25000, asset_code="1200")
        conn.commit()

    result = _invoke(["repair-bank-account-1200", "--order-id", str(oid1)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        e1 = _latest_non_reversal_entry(conn, "payment_transaction", txn1)
        e2 = _latest_non_reversal_entry(conn, "payment_transaction", txn2)
        assert _entry_credit_code(conn, e1) == UNALLOCATED_BANK_CODE
        # txn2 untouched.
        assert _entry_credit_code(conn, e2) == "1200"


# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------


def test_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-DRY", total_price=10000)
        txn = _insert_payment(
            conn, order_id=oid, amount=10000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn, amount=10000, asset_code="1200")
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_before = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        conn.commit()

    result = _invoke(["repair-bank-account-1200", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_after = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        assert je_before == je_after
        assert jl_before == jl_after
        entry_id = _latest_non_reversal_entry(conn, "payment_transaction", txn)
        assert _entry_credit_code(conn, entry_id) == "1200"


# ---------------------------------------------------------------------------
# Locked entry is reversed + recreated (no double-entry)
# ---------------------------------------------------------------------------


def test_locked_entry_reversed_and_recreated():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-LOCK", total_price=10000)
        txn = _insert_payment(
            conn, order_id=oid, amount=10000, ptype="refund", method="transfer",
        )
        entry_id = _insert_refund_journal_entry_on(
            conn, txn_id=txn, amount=10000, asset_code="1200",
        )
        conn.execute(
            "UPDATE journal_entries SET locked_at = datetime('now') WHERE id = ?",
            (entry_id,),
        )
        pre_lines = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_lines WHERE journal_entry_id = ?",
            (entry_id,),
        ).fetchone()["c"]
        conn.commit()

    result = _invoke(["repair-bank-account-1200", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        new_entry = _latest_non_reversal_entry(conn, "payment_transaction", txn)
        assert _entry_credit_code(conn, new_entry) == UNALLOCATED_BANK_CODE
        rev = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries "
            "WHERE source_type = 'payment_transaction' AND source_id = ? "
            "AND description LIKE 'Reversal:%'",
            (txn,),
        ).fetchone()["c"]
        assert int(rev) >= 1
        new_lines = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_lines WHERE journal_entry_id = ?",
            (new_entry,),
        ).fetchone()["c"]
        assert int(new_lines) == pre_lines


# ---------------------------------------------------------------------------
# Vietnamese labels
# ---------------------------------------------------------------------------


def test_vn_labels_in_report():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="BA-VN", total_price=10000)
        txn = _insert_payment(
            conn, order_id=oid, amount=10000, ptype="refund", method="transfer",
        )
        _insert_refund_journal_entry_on(conn, txn_id=txn, amount=10000, asset_code="1200")
        conn.commit()

    result = _invoke(["repair-bank-account-1200", "--all"])
    assert result.exit_code == 0, result.output
    assert "Chuyển bút toán Có TK ngân hàng cũ (1200) sang TK chưa phân bổ (1290)" in result.output
    assert "Mã đơn" in result.output
    assert "Số tiền" in result.output
    assert "Loại" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


# ---------------------------------------------------------------------------
# Expense detection (DG-286 Phase 1 — FR1, AC5)
# ---------------------------------------------------------------------------


def test_expense_detection_finds_entries_on_1200():
    """FR1: expense journal entries with credit on 1200 are detected."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(conn, payment_source="TK Ân VCB", amount_vnd=300000)
        _insert_expense_journal_entry_on(
            conn, event_id=eid, amount=300000, asset_code="1200",
        )
        found = _expense_entries_on_1200(conn)
        assert len(found) == 1
        assert found[0]["entry_id"] > 0
        assert found[0]["event_id"] == eid
        assert found[0]["amount"] == 300000.0
        assert found[0]["payment_source"] == "TK Ân VCB"
        assert found[0]["kind"] == "expense"
        assert found[0]["target_code"] == "1220"
        assert found[0]["locked"] is False


def test_expense_detection_excludes_already_correct():
    """AC5: expense entries already on 1220 (non-1200) are excluded."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(conn, payment_source="TK Ân VCB", amount_vnd=300000)
        _insert_expense_journal_entry_on(
            conn, event_id=eid, amount=300000, asset_code="1220",
        )
        assert _expense_entries_on_1200(conn) == []


def test_expense_detection_excludes_reversal():
    """Reversal:% expense entries are excluded."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(conn, payment_source="TK Ân VCB", amount_vnd=300000)
        asset_acc = _account_id(conn, "1200")
        expense_acc = _account_id(conn, "5300")
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, 'expense', ?)",
            ("Reversal: Expense: Chi phí thử", eid),
        )
        entry_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, 0.0, 'reverse')",
            (entry_id, expense_acc, 300000),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, ?, 'reverse')",
            (entry_id, asset_acc, 300000),
        )
        assert _expense_entries_on_1200(conn) == []


def test_expense_detection_target_code_from_mapping():
    """target_code is derived from EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(
            conn, payment_source="TK Phượng VCB", amount_vnd=150000,
        )
        _insert_expense_journal_entry_on(
            conn, event_id=eid, amount=150000, asset_code="1200",
        )
        found = _expense_entries_on_1200(conn)
        assert len(found) == 1
        assert found[0]["payment_source"] == "TK Phượng VCB"
        assert found[0]["target_code"] == "1210"


def test_expense_detection_skips_malformed_data():
    """Malformed JSON event data is skipped."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO events (type, summary, data, timestamp) "
            "VALUES ('expense', ?, ?, datetime('now'))",
            ("Chi phí hỏng", "not-valid-json{"),
        )
        eid = int(cur.lastrowid)
        _insert_expense_journal_entry_on(
            conn, event_id=eid, amount=200000, asset_code="1200",
        )
        assert _expense_entries_on_1200(conn) == []


def test_expense_detection_skips_missing_payment_source():
    """Missing payment_source field → entry is skipped."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO events (type, summary, data, timestamp) "
            "VALUES ('expense', ?, ?, datetime('now'))",
            ("Chi phí thiếu nguồn", json.dumps({"amount_vnd": 100000, "category": "Khác"})),
        )
        eid = int(cur.lastrowid)
        _insert_expense_journal_entry_on(
            conn, event_id=eid, amount=100000, asset_code="1200",
        )
        assert _expense_entries_on_1200(conn) == []


def test_expense_detection_locked_entry():
    """Locked expense entries return locked=True."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_expense_event(conn, payment_source="TK Ân VCB", amount_vnd=400000)
        _insert_expense_journal_entry_on(
            conn, event_id=eid, amount=400000, asset_code="1200", locked=True,
        )
        found = _expense_entries_on_1200(conn)
        assert len(found) == 1
        assert found[0]["locked"] is True