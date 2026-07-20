"""Tests for ``baker repair-delivered-dates`` CLI command — DG-260 Phase 2.

Covers:

- Registration and ``--help``
- Single-entry repair (re-dates order, order_cogs, order_shipping_release)
- Idempotency: second run changes 0 rows
- Dry-run reports per-type counts without mutating
- Locked entries are skipped and reported
- Per-type count summary output
- Amount integrity: debit/credit lines unchanged after repair
"""

import json

import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _insert_order(
    conn,
    *,
    order_ref: str,
    customer_name: str = "Khách thử",
    total_price: float = 500000.0,
    status: str = "delivered",
    due_date: str | None = "2026-07-01",
) -> int:
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, ?, ?, ?, ?)",
        (order_ref, customer_name, total_price, status, due_date),
    )
    return int(cur.lastrowid)


def _insert_payment(conn, *, order_id: int, amount: float, ptype: str = "deposit", method: str = "cash") -> int:
    cur = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method) "
        "VALUES (?, ?, ?, ?)",
        (order_id, amount, ptype, method),
    )
    return int(cur.lastrowid)


def _insert_order_event(conn, *, order_id: int, order_ref: str, timestamp: str):
    """Insert a delivered event for the order (both order_id and JSON ref match)."""
    data = json.dumps({"order_ref": order_ref, "to_status": "delivered"})
    conn.execute(
        "INSERT INTO events (type, summary, data, order_id, timestamp) "
        "VALUES ('order', ?, ?, ?, ?)",
        (f"Giao hàng: {order_ref}", data, order_id, timestamp),
    )


def _insert_journal_entry(conn, *, source_type: str, source_id: int, description: str,
                           transaction_date: str = "", locked: bool = False):
    """Insert a journal entry with optional transaction_date and lock."""
    locked_at = "'2026-07-01T00:00:00Z'" if locked else "NULL"
    cur = conn.execute(
        f"INSERT INTO journal_entries "
        f"(description, source_type, source_id, transaction_date, locked_at) "
        f"VALUES (?, ?, ?, ?, {locked_at})",
        (description, source_type, source_id, transaction_date),
    )
    entry_id = int(cur.lastrowid)
    # Insert a minimal journal line so the entry is valid.
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, 1, 1000.0, 1000.0, 'test line')",
        (entry_id,),
    )
    return entry_id


def _count_journal_lines(conn, entry_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) AS c FROM journal_lines WHERE journal_entry_id = ?",
        (entry_id,),
    ).fetchone()
    return int(row["c"])


def _sum_4100_credit(conn) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.credit), 0) AS total
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '4100'
        """
    ).fetchone()
    return float(row["total"])


def _sum_5900_net(conn) -> float:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS net
        FROM journal_lines jl
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '5900'
        """
    ).fetchone()
    return float(row["net"])


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_command_registered():
    result = _invoke(["repair-delivered-dates", "--help"])
    assert result.exit_code == 0, result.output
    assert "--dry-run" in result.output


# ---------------------------------------------------------------------------
# Re-dates order entries
# ---------------------------------------------------------------------------


def test_repair_re_dates_order_entry():
    DELIVERED_TS = "2026-07-15T10:30:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-001", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-001", timestamp=DELIVERED_TS)
        eid = _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-001",
            transaction_date="2026-07-01T00:00:00Z",
        )
        assert conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0] == "2026-07-01T00:00:00Z"

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "ORD-DD-001" in result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        updated = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]
        assert updated == DELIVERED_TS


def test_repair_re_dates_order_cogs_entry():
    DELIVERED_TS = "2026-07-15T11:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-002", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-002", timestamp=DELIVERED_TS)
        eid = _insert_journal_entry(
            conn, source_type="order_cogs", source_id=oid,
            description="COGS: ORD-DD-002",
            transaction_date="2026-07-01T00:00:00Z",
        )

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "đã sửa: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        updated = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]
        assert updated == DELIVERED_TS


def test_repair_re_dates_shipping_release_entry():
    DELIVERED_TS = "2026-07-15T12:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-003", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-003", timestamp=DELIVERED_TS)
        eid = _insert_journal_entry(
            conn, source_type="order_shipping_release", source_id=oid,
            description="Shipping release: ORD-DD-003",
            transaction_date="2026-07-01T00:00:00Z",
        )

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "đã sửa: 1" in result.output
    assert "Giải phóng ship" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        updated = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]
        assert updated == DELIVERED_TS


# ---------------------------------------------------------------------------
# Idempotency: second run changes 0 rows (NFR2, AC2)
# ---------------------------------------------------------------------------


def test_repair_idempotent_second_run_no_changes():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-010", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-010", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-010",
            transaction_date="2026-07-01T00:00:00Z",
        )

    result1 = _invoke(["repair-delivered-dates"])
    assert result1.exit_code == 0, result1.output
    assert "đã sửa: 1" in result1.output

    result2 = _invoke(["repair-delivered-dates"])
    assert result2.exit_code == 0, result2.output
    assert "không có bút toán nào cần sửa" in result2.output


# ---------------------------------------------------------------------------
# Dry-run: no mutation (AC2)
# ---------------------------------------------------------------------------


def test_repair_dry_run_does_not_mutate():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-020", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-020", timestamp=DELIVERED_TS)
        eid = _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-020",
            transaction_date="2026-07-01T00:00:00Z",
        )
        original_td = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]

    result = _invoke(["repair-delivered-dates", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa: 1" in result.output
    assert "đã sửa" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        unchanged = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]
        assert unchanged == original_td


def test_repair_dry_run_shows_locked():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-021", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-021", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-021",
            transaction_date="2026-07-01T00:00:00Z",
            locked=True,
        )

    result = _invoke(["repair-delivered-dates", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "khoá" in result.output
    assert "sẽ sửa: 0" in result.output


# ---------------------------------------------------------------------------
# Locked entries are skipped (FR4)
# ---------------------------------------------------------------------------


def test_repair_skips_locked_entry():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-030", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-030", timestamp=DELIVERED_TS)
        eid = _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-030",
            transaction_date="2026-07-01T00:00:00Z",
            locked=True,
        )
        original_td = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "khoá: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        unchanged = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]
        assert unchanged == original_td


# ---------------------------------------------------------------------------
# Per-type count output
# ---------------------------------------------------------------------------


def test_repair_per_type_counts():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid1 = _insert_order(conn, order_ref="ORD-DD-040", status="delivered")
        _insert_payment(conn, order_id=oid1, amount=500000)
        _insert_order_event(conn, order_id=oid1, order_ref="ORD-DD-040", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order", source_id=oid1,
            description="Order revenue: ORD-DD-040",
            transaction_date="2026-07-01T00:00:00Z",
        )
        oid2 = _insert_order(conn, order_ref="ORD-DD-041", status="delivered")
        _insert_payment(conn, order_id=oid2, amount=500000)
        _insert_order_event(conn, order_id=oid2, order_ref="ORD-DD-041", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order_cogs", source_id=oid2,
            description="COGS: ORD-DD-041",
            transaction_date="2026-07-01T00:00:00Z",
        )
        oid3 = _insert_order(conn, order_ref="ORD-DD-042", status="delivered")
        _insert_payment(conn, order_id=oid3, amount=500000)
        _insert_order_event(conn, order_id=oid3, order_ref="ORD-DD-042", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order_shipping_release", source_id=oid3,
            description="Shipping release: ORD-DD-042",
            transaction_date="2026-07-01T00:00:00Z",
        )

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "đã sửa: 3" in result.output
    assert "Doanh thu" in result.output
    assert "Giá vốn (COGS)" in result.output
    assert "Giải phóng ship" in result.output


# ---------------------------------------------------------------------------
# Already-correct entries are skipped
# ---------------------------------------------------------------------------


def test_repair_skips_already_correct():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-050", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-050", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-050",
            transaction_date=DELIVERED_TS,
        )

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "không có bút toán nào cần sửa" in result.output


# ---------------------------------------------------------------------------
# Amount integrity: debit/credit lines unchanged, 4100/5900 sums preserved
# (NFR3, AC5)
# ---------------------------------------------------------------------------


def test_repair_preserves_amount_integrity():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-060", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-060", timestamp=DELIVERED_TS)
        eid = _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-060",
            transaction_date="2026-07-01T00:00:00Z",
        )
        line_count_before = _count_journal_lines(conn, eid)
        sum_4100_before = _sum_4100_credit(conn)
        sum_5900_before = _sum_5900_net(conn)

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "đã sửa: 1" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        line_count_after = _count_journal_lines(conn, eid)
        sum_4100_after = _sum_4100_credit(conn)
        sum_5900_after = _sum_5900_net(conn)

    assert line_count_before == line_count_after
    assert sum_4100_before == sum_4100_after
    assert sum_5900_before == sum_5900_after


# ---------------------------------------------------------------------------
# Missing event for order → skipped (no delivered timestamp to compare)
# ---------------------------------------------------------------------------


def test_repair_skips_order_without_delivered_event():
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-070", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        eid = _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-070",
            transaction_date="2026-07-01T00:00:00Z",
        )
        original_td = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "không có bút toán nào cần sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        unchanged = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?", (eid,)
        ).fetchone()[0]
        assert unchanged == original_td


# ---------------------------------------------------------------------------
# Reversal entries are excluded
# ---------------------------------------------------------------------------


def test_repair_ignores_reversal_entries():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-080", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-080", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Reversal: Order revenue: ORD-DD-080",
            transaction_date="2026-07-01T00:00:00Z",
        )

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "không có bút toán nào cần sửa" in result.output


# ---------------------------------------------------------------------------
# VN labels
# ---------------------------------------------------------------------------


def test_repair_vn_labels():
    DELIVERED_TS = "2026-07-15T10:00:00Z"
    with get_db() as conn:
        ensure_schema(conn)
        oid = _insert_order(conn, order_ref="ORD-DD-090", status="delivered")
        _insert_payment(conn, order_id=oid, amount=500000)
        _insert_order_event(conn, order_id=oid, order_ref="ORD-DD-090", timestamp=DELIVERED_TS)
        _insert_journal_entry(
            conn, source_type="order", source_id=oid,
            description="Order revenue: ORD-DD-090",
            transaction_date="2026-07-01T00:00:00Z",
        )

    result = _invoke(["repair-delivered-dates"])
    assert result.exit_code == 0, result.output
    assert "Sửa ngày giao dịch" in result.output
    assert "Mã đơn" in result.output
    assert "Loại" in result.output
    assert "Ngày cũ" in result.output
    assert "Ngày mới" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output
