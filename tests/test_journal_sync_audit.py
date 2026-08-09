"""Tests for DG-226 Phase 1 — audit log writes on journal sync failure.

Covers:
- AC3: run_journal_sync writes to journal_sync_failure_log on failure
- NFR2: audit log write failure must never throw
- NFR4: auto-truncation to 10,000 rows, oldest-first
"""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.journal_sync import _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS, _log_journal_sync_failure, run_journal_sync
from baker.services.journal_sync._common import _delete_journal_entry_cascade


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


def test_delete_journal_entry_cascade_removes_drawer_link():
    """DG-380 Phase 2 / AC1 + AC6: a journal entry linked to a cash drawer via
    ``cash_drawer_journal_entries`` must be fully cleaned up by
    ``_delete_journal_entry_cascade`` — the drawer link is deleted before the
    ``journal_entries`` row so no FOREIGN KEY violation occurs.

    Regression coverage for the Phase 1 fix that added the
    ``DELETE FROM cash_drawer_journal_entries`` step before the
    ``DELETE FROM journal_entries`` step.
    """
    with get_db() as conn:
        ensure_schema(conn)

        # Fixture: open a cash drawer to link the journal entry against.
        drawer_row = conn.execute(
            "INSERT INTO cash_drawer (opening_balance, status) VALUES (0, 'open')"
        )
        drawer_id = int(drawer_row.lastrowid)

        # Fixture: pick two real account IDs (cash-on-hand 1101 debit, revenue
        # credit) so the journal entry satisfies double-entry integrity.
        cash_account_id = int(
            conn.execute("SELECT id FROM accounts WHERE code = '1101'").fetchone()[0]
        )
        revenue_account_id = int(
            conn.execute("SELECT id FROM accounts WHERE code = '4000'").fetchone()[0]
        )

        entry_id = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES (?, ?, ?)",
            ("drawer-linked test entry", "order", 4242),
        ).lastrowid
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, cash_account_id, 100.0, 0.0, "cash debit"),
        )
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, revenue_account_id, 0.0, 100.0, "revenue credit"),
        )
        conn.execute(
            "INSERT INTO cash_drawer_journal_entries "
            "(cash_drawer_id, journal_entry_id) VALUES (?, ?)",
            (drawer_id, entry_id),
        )

        # Sanity: all three rows exist before the cascade delete.
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM journal_entries WHERE id = ?", (entry_id,)
            ).fetchone()[0]
            == 1
        )
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM journal_lines WHERE journal_entry_id = ?",
                (entry_id,),
            ).fetchone()[0]
            == 2
        )
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM cash_drawer_journal_entries "
                "WHERE journal_entry_id = ?",
                (entry_id,),
            ).fetchone()[0]
            == 1
        )

        # AC1: deleting the drawer-linked entry must not raise an FK violation
        # (this is the exact failure the Phase 1 fix addresses).
        _delete_journal_entry_cascade(conn, entry_id)

        # All three tables cleaned up.
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM journal_entries WHERE id = ?", (entry_id,)
            ).fetchone()[0]
            == 0
        )
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM journal_lines WHERE journal_entry_id = ?",
                (entry_id,),
            ).fetchone()[0]
            == 0
        )
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM cash_drawer_journal_entries "
                "WHERE journal_entry_id = ?",
                (entry_id,),
            ).fetchone()[0]
            == 0
        )

        # The cash drawer itself must be untouched (cascade targets the link
        # table, not the drawer).
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM cash_drawer WHERE id = ?", (drawer_id,)
            ).fetchone()[0]
            == 1
        )
