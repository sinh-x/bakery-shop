"""Tests for DG-226 Phase 1 — audit log writes on journal sync failure.

Covers:
- AC3: run_journal_sync writes to journal_sync_failure_log on failure
- NFR2: audit log write failure must never throw
- NFR4: auto-truncation to 10,000 rows, oldest-first
"""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.journal_sync import _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS, _log_journal_sync_failure, run_journal_sync


def _table_exists(conn, name: str) -> bool:
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?", (name,)
    ).fetchone()
    return row is not None


def _failing_sync_fn(*args, **kwargs):
    raise RuntimeError("simulated journal sync failure")


def _failure_row_count(conn) -> int:
    return int(
        conn.execute("SELECT COUNT(*) FROM journal_sync_failure_log").fetchone()[0]
    )


def test_audit_log_writes_on_failure():
    """AC3: when run_journal_sync catches an exception with source_type and
    source_id provided, a row is written to journal_sync_failure_log."""
    with get_db() as conn:
        ensure_schema(conn)
        assert _table_exists(conn, "journal_sync_failure_log")

        result = run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="test sync failure",
            source_type="order",
            source_id=42,
        )

        assert result == "failed"
        assert _failure_row_count(conn) == 1

        row = conn.execute(
            "SELECT source_type, source_id, error_message, stack_trace, created_at "
            "FROM journal_sync_failure_log ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row["source_type"] == "order"
        assert row["source_id"] == 42
        assert "simulated journal sync failure" in row["error_message"]
        assert "RuntimeError" in row["stack_trace"]
        assert row["created_at"] is not None


def test_audit_log_writes_expense_source():
    with get_db() as conn:
        ensure_schema(conn)
        run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="expense sync failure",
            source_type="expense",
            source_id=7,
        )
        row = conn.execute(
            "SELECT source_type, source_id FROM journal_sync_failure_log ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row["source_type"] == "expense"
        assert row["source_id"] == 7


def test_audit_log_writes_payment_source():
    with get_db() as conn:
        ensure_schema(conn)
        run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="payment sync failure",
            source_type="payment_transaction",
            source_id=99,
        )
        row = conn.execute(
            "SELECT source_type, source_id FROM journal_sync_failure_log ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert row["source_type"] == "payment_transaction"
        assert row["source_id"] == 99


def test_audit_log_skips_when_source_type_not_provided():
    """Backward compatibility: when source_type is None, no audit write happens."""
    with get_db() as conn:
        ensure_schema(conn)
        run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="legacy sync failure",
        )
        assert _failure_row_count(conn) == 0


def test_audit_log_skips_when_source_id_not_provided():
    with get_db() as conn:
        ensure_schema(conn)
        run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="legacy sync failure",
            source_type="order",
        )
        assert _failure_row_count(conn) == 0


def test_audit_log_never_throws_nfr2():
    """NFR2: if the audit log write itself fails, it must not throw."""
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DROP TABLE journal_sync_failure_log")
        result = run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="sync with missing log table",
            source_type="order",
            source_id=1,
        )
        assert result == "failed"


def test_audit_log_auto_truncation():
    """NFR4: when the log exceeds 10,000 rows, oldest entries are deleted."""
    from baker.services.journal_sync import _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS

    with get_db() as conn:
        ensure_schema(conn)
        for i in range(_JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS + 5):
            run_journal_sync(
                _failing_sync_fn,
                conn,
                log_label=f"sync failure {i}",
                source_type="order",
                source_id=i,
            )
        assert _failure_row_count(conn) == _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS

        min_id = conn.execute(
            "SELECT MIN(id) FROM journal_sync_failure_log"
        ).fetchone()[0]
        assert min_id == 6


def test_audit_log_success_does_not_write():
    """Successful syncs do not produce audit log rows."""
    with get_db() as conn:
        ensure_schema(conn)

        def _success_sync_fn(*args, **kwargs):
            pass

        result = run_journal_sync(
            _success_sync_fn,
            conn,
            log_label="successful sync",
            source_type="order",
            source_id=1,
        )
        assert result == "ok"
        assert _failure_row_count(conn) == 0


def test_audit_log_returns_failed_when_sync_raises():
    """Return value is 'failed' when sync raises."""
    with get_db() as conn:
        ensure_schema(conn)
        result = run_journal_sync(
            _failing_sync_fn,
            conn,
            log_label="test return value",
        )
        assert result == "failed"


def test_audit_log_returns_ok_when_sync_succeeds():
    """Return value is 'ok' when sync succeeds."""
    with get_db() as conn:
        ensure_schema(conn)

        def _ok(*args, **kwargs):
            pass

        result = run_journal_sync(
            _ok,
            conn,
            log_label="test ok return",
        )
        assert result == "ok"
