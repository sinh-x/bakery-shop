"""Tests for ``baker repair-unallocated-transfers`` — DG-244 Phase 5.

Historical transaction backfill (FR5 backfill aspect, NFR1, NFR3, AC6).

Covers:
  - ``--all`` re-points transfer transactions whose journal entry asset line
    is on the legacy default (1200) to the un-allocated bank account (1290)
    when ``payment_source`` is empty (AC6).
  - Idempotent: a second run reports no transactions to backfill (NFR1).
  - Transactions WITH an explicit ``payment_source`` (1210/1220) are
    untouched (NFR3).
  - Non-transfer methods (cash/card) are untouched — they never used 1200.
  - Expense journal entries are untouched (NFR1).
  - No double-entry: journal line count per payment_transaction entry is
    unchanged after backfill (only the asset account moves from 1200 to 1290).
  - ``--order-id`` scopes to a single order.
  - ``--dry-run`` reports planned actions without mutating.
  - Command registration / ``--help`` / arg validation.
  - Vietnamese labels in the report.
  - Locked entries are reversed + recreated (no double-entry).
"""

import click
import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import (
    TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE,
    UNALLOCATED_BANK_CODE,
    ensure_schema,
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


def _insert_expense_event(conn, *, amount_vnd: float, payment_source: str = "Shop tiền mặt") -> int:
    import json

    cur = conn.execute(
        "INSERT INTO events (type, summary, data, timestamp) VALUES (?, ?, ?, datetime('now'))",
        (
            "expense",
            f"Chi phí {payment_source}",
            json.dumps({
                "amount_vnd": amount_vnd,
                "category": "Khác",
                "payment_source": payment_source,
                "payment_method": "cash",
            }),
        ),
    )
    return int(cur.lastrowid)


def _insert_payment_journal_entry(
    conn,
    *,
    txn_id: int,
    amount: float,
    asset_code: str,
    ptype: str = "deposit",
    delivery_type: str = "pickup",
    shipping_fee: float = 0.0,
) -> int:
    """Create a journal entry for a payment_transaction with the asset line on
    ``asset_code``. Mirrors :func:`_build_payment_journal_lines` for the
    legacy default-routing case (no shipping split, deposit inflow).
    """
    asset_acc = _account_id(conn, asset_code)
    deposits_acc = _account_id(conn, "2100")
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'payment_transaction', ?)",
        (f"Payment: {ptype} {amount}", txn_id),
    )
    entry_id = int(cur.lastrowid)
    if ptype == "tien_rut":
        tien_rut_acc = _account_id(conn, "2400")
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, 0.0, 'Tiền khách gửi giữ hộ')",
            (entry_id, asset_acc, amount),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, ?, 'Tiền rút tạm giữ')",
            (entry_id, tien_rut_acc, amount),
        )
    else:
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, 0.0, 'Tiền khách đặt/cọc')",
            (entry_id, asset_acc, amount),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, ?, 'Tiền khách đặt cọc')",
            (entry_id, deposits_acc, amount),
        )
    return entry_id


def _insert_expense_journal_entry(conn, *, event_id: int, amount: float, credit_code: str) -> int:
    """Create a journal entry for an expense event with a credit line on
    ``credit_code``. Used to assert expense journals are untouched.
    """
    expense_acc = _account_id(conn, "5800")
    credit_acc = _account_id(conn, credit_code)
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'expense', ?)",
        (f"Expense: {event_id}", event_id),
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
        (entry_id, credit_acc, amount),
    )
    return entry_id


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _payment_journal_entry(conn, txn_id: int):
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'payment_transaction' AND source_id = ? "
        "AND description NOT LIKE 'Reversal:%' "
        "ORDER BY id DESC LIMIT 1",
        (txn_id,),
    ).fetchone()
    return int(row["id"]) if row else None


def _payment_journal_line_counts(conn, txn_id: int) -> dict:
    """Return per-entry line counts and the asset (debit) account code for
    the txn's latest non-reversal payment journal entry.
    """
    entry_id = _payment_journal_entry(conn, txn_id)
    if entry_id is None:
        return {"entry_id": None, "lines": 0, "asset_code": None}
    lines = conn.execute(
        "SELECT COUNT(*) AS c FROM journal_lines WHERE journal_entry_id = ?",
        (entry_id,),
    ).fetchone()["c"]
    asset_row = conn.execute(
        """
        SELECT a.code AS code
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE jl.journal_entry_id = ? AND jl.debit > 0
        ORDER BY jl.id LIMIT 1
        """,
        (entry_id,),
    ).fetchone()
    return {
        "entry_id": entry_id,
        "lines": int(lines),
        "asset_code": asset_row["code"] if asset_row else None,
    }


def _expense_journal_credit_code(conn, event_id: int) -> str | None:
    row = conn.execute(
        """
        SELECT a.code AS code
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'expense' AND je.source_id = ?
          AND je.description NOT LIKE 'Reversal:%' AND jl.credit > 0
        ORDER BY jl.id LIMIT 1
        """,
        (event_id,),
    ).fetchone()
    return row["code"] if row else None


# ---------------------------------------------------------------------------
# Registration & help / arg validation
# ---------------------------------------------------------------------------


def test_unallocated_transfers_command_registered():
    result = _invoke(["repair-unallocated-transfers", "--help"])
    assert result.exit_code == 0, result.output
    assert "--order-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output
    assert "1290" in result.output


def test_unallocated_transfers_requires_one_mode():
    result = _invoke(["repair-unallocated-transfers"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_unallocated_transfers_rejects_both_modes():
    result = _invoke(["repair-unallocated-transfers", "--order-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# --all backfill: AC6 — historical transfer entries moved 1200 -> 1290
# ---------------------------------------------------------------------------


def test_all_backfills_legacy_transfer_to_1290():
    """AC6: historical transfer txn without payment_source → asset line
    moves from 1200 to 1290."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-101", total_price=400000)
        txn = _insert_payment(
            conn, order_id=oid, amount=400000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn, amount=400000, asset_code="1200", ptype="deposit",
        )
        pre = _payment_journal_line_counts(conn, txn)
        assert pre["asset_code"] == "1200"

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert f"#{txn}" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        post = _payment_journal_line_counts(conn, txn)
        assert post["asset_code"] == UNALLOCATED_BANK_CODE
        # No double-entry: line count unchanged.
        assert post["lines"] == pre["lines"]


def test_all_idempotent_second_run_is_noop():
    """NFR1: second run finds nothing to backfill."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-102", total_price=300000)
        txn = _insert_payment(
            conn, order_id=oid, amount=300000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn, amount=300000, asset_code="1200",
        )

    r1 = _invoke(["repair-unallocated-transfers", "--all"])
    assert r1.exit_code == 0, r1.output
    assert "đã sửa" in r1.output

    r2 = _invoke(["repair-unallocated-transfers", "--all"])
    assert r2.exit_code == 0, r2.output
    assert "không có giao dịch chuyển khoản nào cần chuyển sang TK 1290" in r2.output

    with get_db() as conn:
        ensure_schema(conn)
        post = _payment_journal_line_counts(conn, txn)
        assert post["asset_code"] == UNALLOCATED_BANK_CODE


# ---------------------------------------------------------------------------
# NFR3 — transactions WITH payment_source are untouched
# ---------------------------------------------------------------------------


def test_payment_source_untouched():
    """NFR3: transactions with explicit payment_source (1210/1220) stay on
    their bank sub-account. Backfill must not move them to 1290."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-103", total_price=200000)
        for source, expected_code in TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE.items():
            txn = _insert_payment(
                conn, order_id=oid, amount=200000, ptype="deposit", method="transfer",
                payment_source=source,
            )
            _insert_payment_journal_entry(
                conn, txn_id=txn, amount=200000, asset_code=expected_code,
            )

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    # No transactions matched the legacy-default + empty-source predicate.
    assert "không có giao dịch chuyển khoản nào cần chuyển sang TK 1290" in result.output


# ---------------------------------------------------------------------------
# Non-transfer methods are untouched
# ---------------------------------------------------------------------------


def test_cash_and_card_untouched():
    """Cash/card transactions never used 1200 (they route to 1100). The
    backfill predicate scopes to ``method='transfer'`` only."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-104", total_price=150000)
        cash_txn = _insert_payment(
            conn, order_id=oid, amount=150000, ptype="deposit", method="cash",
        )
        card_txn = _insert_payment(
            conn, order_id=oid, amount=50000, ptype="deposit", method="card",
        )
        _insert_payment_journal_entry(
            conn, txn_id=cash_txn, amount=150000, asset_code="1100",
        )
        _insert_payment_journal_entry(
            conn, txn_id=card_txn, amount=50000, asset_code="1100",
        )

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có giao dịch chuyển khoản nào cần chuyển sang TK 1290" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _payment_journal_line_counts(conn, cash_txn)["asset_code"] == "1100"
        assert _payment_journal_line_counts(conn, card_txn)["asset_code"] == "1100"


# ---------------------------------------------------------------------------
# NFR1 — expense journals untouched
# ---------------------------------------------------------------------------


def test_expense_journals_untouched():
    """NFR1: backfill touches only payment_transaction entries — expense
    journal entries (which may credit 1200 via the expense mapping) are
    untouched."""
    with get_db() as conn:
        ensure_schema(conn)
        # Expense event with payment_source='TK Phượng VCB' → credit 1200.
        event_id = _insert_expense_event(
            conn, amount_vnd=250000, payment_source="TK Phượng VCB",
        )
        _insert_expense_journal_entry(
            conn, event_id=event_id, amount=250000, credit_code="1200",
        )
        # Seed one transfer payment txn so the command runs in --all mode.
        oid = _insert_order(conn, order_ref="ORD-260707-105", total_price=200000)
        txn = _insert_payment(
            conn, order_id=oid, amount=200000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn, amount=200000, asset_code="1200",
        )

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        ensure_schema(conn)
        # Expense credit account is still 1200 — not moved to 1290.
        assert _expense_journal_credit_code(conn, event_id) == "1200"
        # Payment txn asset moved to 1290.
        assert _payment_journal_line_counts(conn, txn)["asset_code"] == UNALLOCATED_BANK_CODE


# ---------------------------------------------------------------------------
# --order-id scope
# ---------------------------------------------------------------------------


def test_order_id_scoped_backfill():
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(conn, order_ref="ORD-260707-106", total_price=200000)
        oid2 = _insert_order(conn, order_ref="ORD-260707-107", total_price=300000)
        txn1 = _insert_payment(
            conn, order_id=oid1, amount=200000, ptype="deposit", method="transfer",
        )
        txn2 = _insert_payment(
            conn, order_id=oid2, amount=300000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn1, amount=200000, asset_code="1200",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn2, amount=300000, asset_code="1200",
        )

    result = _invoke(["repair-unallocated-transfers", "--order-id", str(oid1)])
    assert result.exit_code == 0, result.output
    assert f"#{txn1}" in result.output
    assert f"#{txn2}" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _payment_journal_line_counts(conn, txn1)["asset_code"] == UNALLOCATED_BANK_CODE
        # txn2 untouched
        assert _payment_journal_line_counts(conn, txn2)["asset_code"] == "1200"


# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------


def test_dry_run_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-108", total_price=350000)
        txn = _insert_payment(
            conn, order_id=oid, amount=350000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn, amount=350000, asset_code="1200",
        )
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_before = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]

    result = _invoke(["repair-unallocated-transfers", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output
    assert f"#{txn}" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        jl_after = conn.execute("SELECT COUNT(*) AS c FROM journal_lines").fetchone()["c"]
        assert je_before == je_after
        assert jl_before == jl_after
        # Asset line still on 1200 — dry-run did not re-sync.
        assert _payment_journal_line_counts(conn, txn)["asset_code"] == "1200"


# ---------------------------------------------------------------------------
# Invalidated transactions are skipped
# ---------------------------------------------------------------------------


def test_invalidated_txn_skipped():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-109", total_price=100000)
        txn = _insert_payment(
            conn, order_id=oid, amount=100000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn, amount=100000, asset_code="1200",
        )
        conn.execute(
            "UPDATE payment_transactions SET invalidated_at = datetime('now') WHERE id = ?",
            (txn,),
        )

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có giao dịch chuyển khoản nào cần chuyển sang TK 1290" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # Entry unchanged (still 1200) — invalidated excluded from predicate.
        assert _payment_journal_line_counts(conn, txn)["asset_code"] == "1200"


# ---------------------------------------------------------------------------
# No journal entry → not in scope (handled by repair-payment-journal)
# ---------------------------------------------------------------------------


def test_txn_without_journal_entry_not_in_scope():
    """Transactions without a journal entry have no asset line to reassign —
    they are the domain of ``repair-payment-journal`` and excluded here."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-110", total_price=120000)
        txn = _insert_payment(
            conn, order_id=oid, amount=120000, ptype="deposit", method="transfer",
        )
        # No journal entry created.

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có giao dịch chuyển khoản nào cần chuyển sang TK 1290" in result.output


# ---------------------------------------------------------------------------
# Locked entry is reversed + recreated (no double-entry)
# ---------------------------------------------------------------------------


def test_locked_entry_reversed_and_recreated():
    """A locked journal entry is reversed and a new entry created on 1290 —
    not deleted/rewritten in place. No double-entry: the original is
    reversed (debit/credit swapped), and the new entry carries the same
    debit on 1290."""
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-111", total_price=220000)
        txn = _insert_payment(
            conn, order_id=oid, amount=220000, ptype="deposit", method="transfer",
        )
        entry_id = _insert_payment_journal_entry(
            conn, txn_id=txn, amount=220000, asset_code="1200",
        )
        conn.execute(
            "UPDATE journal_entries SET locked_at = datetime('now') WHERE id = ?",
            (entry_id,),
        )
        pre_lines = _payment_journal_line_counts(conn, txn)["lines"]

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # The latest non-reversal entry now references 1290.
        post = _payment_journal_line_counts(conn, txn)
        assert post["asset_code"] == UNALLOCATED_BANK_CODE
        # A reversal entry exists (the locked original was reversed).
        rev = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries "
            "WHERE source_type = 'payment_transaction' AND source_id = ? "
            "AND description LIKE 'Reversal:%'",
            (txn,),
        ).fetchone()["c"]
        assert int(rev) >= 1
        # New entry line count equals the original's (no double-entry).
        assert post["lines"] == pre_lines


# ---------------------------------------------------------------------------
# Vietnamese labels
# ---------------------------------------------------------------------------


def test_vn_labels_in_report():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-260707-112", total_price=180000)
        txn = _insert_payment(
            conn, order_id=oid, amount=180000, ptype="deposit", method="transfer",
        )
        _insert_payment_journal_entry(
            conn, txn_id=txn, amount=180000, asset_code="1200",
        )

    result = _invoke(["repair-unallocated-transfers", "--all"])
    assert result.exit_code == 0, result.output
    assert "Chuyển bút toán chuyển khoản cũ sang TK chưa phân bổ (1290)" in result.output
    assert "Mã GD" in result.output
    assert "Số tiền" in result.output
    assert "Đơn hàng" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output