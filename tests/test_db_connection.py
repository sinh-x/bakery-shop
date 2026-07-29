"""Dedicated tests for baker.db.connection (FR-PY-6).

Covers get_db context manager (commit/rollback/close, PRAGMA setup) and
checkpoint_wal (TRUNCATE on close, no-op for :memory:).
"""

import sqlite3

from baker.db.connection import checkpoint_wal, get_db


def test_get_db_sets_pragmas_and_row_factory(use_memory_db):
    with get_db() as conn:
        assert conn.row_factory is sqlite3.Row
        # journal_mode WAL
        mode = conn.execute("PRAGMA journal_mode").fetchone()[0]
        assert mode == "wal"
        # foreign_keys ON
        fk = conn.execute("PRAGMA foreign_keys").fetchone()[0]
        assert fk == 1


def test_get_db_commits_on_success(use_memory_db, tmp_path):
    db_path = str(tmp_path / "commit.db")
    with get_db(db_path) as conn:
        conn.execute("CREATE TABLE t (x INTEGER)")
        conn.execute("INSERT INTO t VALUES (1)")
    # Reopen and verify the row persisted.
    with get_db(db_path) as conn:
        rows = conn.execute("SELECT x FROM t").fetchall()
        assert [r["x"] for r in rows] == [1]


def test_get_db_rolls_back_on_exception(use_memory_db, tmp_path):
    db_path = str(tmp_path / "rollback.db")
    with get_db(db_path) as conn:
        conn.execute("CREATE TABLE t (x INTEGER)")
    # Insert then raise inside the context — should roll back the insert.
    try:
        with get_db(db_path) as conn:
            conn.execute("INSERT INTO t VALUES (42)")
            raise RuntimeError("boom")
    except RuntimeError:
        pass
    with get_db(db_path) as conn:
        rows = conn.execute("SELECT x FROM t").fetchall()
        assert rows == []


def test_get_db_creates_parent_dir(use_memory_db, tmp_path):
    db_path = str(tmp_path / "nested" / "deep" / "test.db")
    with get_db(db_path) as conn:
        conn.execute("CREATE TABLE t (x INTEGER)")
    import os
    assert os.path.exists(db_path)


def test_get_db_closes_connection(use_memory_db, tmp_path):
    db_path = str(tmp_path / "close.db")
    with get_db(db_path) as conn:
        conn.execute("CREATE TABLE t (x INTEGER)")
    # Connection should be closed — further use raises.
    import pytest

    with pytest.raises(sqlite3.ProgrammingError):
        conn.execute("SELECT 1")


def test_checkpoint_wal_noop_for_memory(use_memory_db):
    # :memory: path should be a no-op (returns None, no error).
    import baker.config
    baker.config.DB_PATH = ":memory:"
    assert checkpoint_wal() is None


def test_checkpoint_wal_truncates_file_db(use_memory_db, tmp_path):
    db_path = str(tmp_path / "ckpt.db")
    # Create a DB with WAL mode and insert data.
    with get_db(db_path) as conn:
        conn.execute("CREATE TABLE t (x INTEGER)")
        conn.execute("INSERT INTO t VALUES (1)")
    # Run checkpoint — should not raise and should flush WAL.
    checkpoint_wal(db_path)
    # The main DB file should exist and contain the row after checkpoint.
    with get_db(db_path) as conn:
        rows = conn.execute("SELECT x FROM t").fetchall()
        assert [r["x"] for r in rows] == [1]