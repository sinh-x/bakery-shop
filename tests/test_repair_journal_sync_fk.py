"""Regression tests for the repair-journal-sync-fk command."""

from unittest.mock import patch

import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema


def _invoke(args):
    return click.testing.CliRunner().invoke(app, args)


def _insert_order(conn, *, order_ref: str, status: str = "delivered") -> int:
    row = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, 'Test customer', 100000, ?, '2026-08-01')",
        (order_ref, status),
    )
    return int(row.lastrowid)


def _insert_failure(conn, *, source_type: str, source_id: int, message: str):
    conn.execute(
        "INSERT INTO journal_sync_failure_log "
        "(source_type, source_id, error_message) VALUES (?, ?, ?)",
        (source_type, source_id, message),
    )


def _failure_rows(conn, *, source_id: int | None = None):
    sql = "SELECT source_type, source_id, error_message FROM journal_sync_failure_log"
    params = ()
    if source_id is not None:
        sql += " WHERE source_id = ?"
        params = (source_id,)
    return conn.execute(sql, params).fetchall()


def test_successful_repair_cleans_only_matching_fk_rows_and_is_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_order(conn, order_ref="ORD-FK-001")
        _insert_failure(
            conn,
            source_type="order",
            source_id=order_id,
            message="FOREIGN KEY constraint failed",
        )
        _insert_failure(
            conn,
            source_type="order",
            source_id=order_id,
            message="some unrelated sync failure",
        )
        _insert_failure(
            conn,
            source_type="expense",
            source_id=order_id,
            message="FOREIGN KEY constraint failed",
        )

    with patch(
        "baker.commands.repair.journal_sync_fk._sync_delivered_order_journal"
    ) as sync:
        first = _invoke(["repair-journal-sync-fk", "--all"])
        second = _invoke(["repair-journal-sync-fk", "--all"])

    assert first.exit_code == 0, first.output
    assert "đã sửa: 1" in first.output
    assert second.exit_code == 0, second.output
    assert "không có đơn hàng nào cần đồng bộ lại" in second.output
    sync.assert_called_once()

    with get_db() as conn:
        rows = _failure_rows(conn, source_id=order_id)
        assert {(row["source_type"], row["error_message"]) for row in rows} == {
            ("order", "some unrelated sync failure"),
            ("expense", "FOREIGN KEY constraint failed"),
        }


def test_failed_repair_preserves_fk_failure_row():
    with get_db() as conn:
        ensure_schema(conn)
        order_id = _insert_order(conn, order_ref="ORD-FK-002", status="completed")
        _insert_failure(
            conn,
            source_type="order",
            source_id=order_id,
            message="FOREIGN KEY constraint failed",
        )

    with patch(
        "baker.commands.repair.journal_sync_fk._sync_completed_order_journal",
        side_effect=RuntimeError("simulated repair failure"),
    ):
        result = _invoke(["repair-journal-sync-fk", "--all"])

    assert result.exit_code == 0, result.output
    assert "lỗi: 1" in result.output

    with get_db() as conn:
        rows = _failure_rows(conn, source_id=order_id)
        assert len(rows) == 1
        assert rows[0]["source_type"] == "order"
        assert rows[0]["error_message"] == "FOREIGN KEY constraint failed"
