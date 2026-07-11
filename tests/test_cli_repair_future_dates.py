"""Tests for ``baker repair-future-dates`` CLI command — DG-233 Phase 5.

Covers:

- ``--all`` fixes future-dated entries
- ``--entry-id`` single entry fix
- ``--dry-run`` shows what would change without mutating
- Idempotent no-op on already-fixed entries
- Locked entries are skipped
- Normal-date entries are not touched
- Vietnamese labels
- Command registration / --help
"""

import click
import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.utils.time import now_utc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _entry_created_at(conn, entry_id: int) -> str | None:
    row = conn.execute(
        "SELECT created_at FROM journal_entries WHERE id = ?", (entry_id,)
    ).fetchone()
    return row["created_at"] if row else None


def _insert_future_entry(conn, *, description="Future entry", locked=False):
    """Insert a journal entry with a far-future created_at."""
    cur = conn.execute(
        "INSERT INTO journal_entries "
        "(description, source_type, source_id, created_at, locked_at) "
        "VALUES (?, ?, ?, ?, ?)",
        (
            description,
            "manual",
            None,
            "2999-12-31T23:59:59Z",
            now_utc() if locked else None,
        ),
    )
    return int(cur.lastrowid)


def _insert_normal_entry(conn, *, description="Normal entry"):
    """Insert a journal entry with a past created_at."""
    cur = conn.execute(
        "INSERT INTO journal_entries "
        "(description, source_type, source_id, created_at) "
        "VALUES (?, ?, ?, ?)",
        (description, "manual", None, "2020-01-01T10:00:00Z"),
    )
    return int(cur.lastrowid)


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_repair_future_dates_command_registered():
    result = _invoke(["repair-future-dates", "--help"])
    assert result.exit_code == 0, result.output
    assert "--entry-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_repair_future_dates_requires_one_mode():
    result = _invoke(["repair-future-dates"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_repair_future_dates_rejects_both_modes():
    result = _invoke(["repair-future-dates", "--entry-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# --all backfill
# ---------------------------------------------------------------------------


def test_repair_future_dates_all_fixes_future_entries():
    with get_db() as conn:
        ensure_schema(conn)
        eid1 = _insert_future_entry(conn, description="Future entry 1")
        eid2 = _insert_future_entry(conn, description="Future entry 2")
        _insert_normal_entry(conn, description="Normal entry")

    result = _invoke(["repair-future-dates", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert str(eid1) in result.output
    assert str(eid2) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        created1 = _entry_created_at(conn, eid1)
        created2 = _entry_created_at(conn, eid2)
        assert created1 is not None
        assert created2 is not None
        # After repair, created_at should no longer be in the future
        assert created1 <= now_utc()
        assert created2 <= now_utc()


def test_repair_future_dates_all_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_future_entry(conn, description="Future entry")

    # First run — fixes
    result1 = _invoke(["repair-future-dates", "--all"])
    assert result1.exit_code == 0, result1.output
    assert "đã sửa" in result1.output

    # Second run — idempotent, no entries need repair
    result2 = _invoke(["repair-future-dates", "--all"])
    assert result2.exit_code == 0, result2.output
    assert "không có bút toán nào cần sửa ngày" in result2.output


# ---------------------------------------------------------------------------
# --entry-id single entry fix
# ---------------------------------------------------------------------------


def test_repair_future_dates_entry_id_fixes_single():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_future_entry(conn, description="Fix me")
        _insert_future_entry(conn, description="Leave me")

    result = _invoke(["repair-future-dates", "--entry-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert "Fix me" in result.output
    assert "Leave me" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _entry_created_at(conn, eid) <= now_utc()


def test_repair_future_dates_entry_id_not_found():
    result = _invoke(["repair-future-dates", "--entry-id", "99999"])
    assert result.exit_code == 0, result.output
    assert "không tìm thấy bút toán" in result.output


def test_repair_future_dates_entry_id_normal_date():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_normal_entry(conn, description="Normal entry")

    result = _invoke(["repair-future-dates", "--entry-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "không tìm thấy bút toán" in result.output or "không có ngày trong tương lai" in result.output


# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------


def test_repair_future_dates_dry_run_all_does_not_mutate():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_future_entry(conn, description="Future entry")
        je_before = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        created_before = _entry_created_at(conn, eid)

    result = _invoke(["repair-future-dates", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output
    assert str(eid) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        je_after = conn.execute("SELECT COUNT(*) AS c FROM journal_entries").fetchone()["c"]
        created_after = _entry_created_at(conn, eid)

    assert je_before == je_after
    assert created_before == created_after


def test_repair_future_dates_dry_run_entry_id():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_future_entry(conn, description="Future entry")
        created_before = _entry_created_at(conn, eid)

    result = _invoke(["repair-future-dates", "--entry-id", str(eid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _entry_created_at(conn, eid) == created_before


# ---------------------------------------------------------------------------
# Locked entries are skipped
# ---------------------------------------------------------------------------


def test_repair_future_dates_skips_locked_entries():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_future_entry(conn, description="Locked entry", locked=True)

    result = _invoke(["repair-future-dates", "--all"])
    assert result.exit_code == 0, result.output
    assert "khoá" in result.output
    assert str(eid) in result.output

    with get_db() as conn:
        ensure_schema(conn)
        # Locked entry should still have its future date (not fixed)
        assert _entry_created_at(conn, eid) == "2999-12-31T23:59:59Z"


# ---------------------------------------------------------------------------
# Normal-date entries are not touched
# ---------------------------------------------------------------------------


def test_repair_future_dates_all_normal_dates_untouched():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_normal_entry(conn, description="Normal entry")

    result = _invoke(["repair-future-dates", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có bút toán nào cần sửa ngày" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _entry_created_at(conn, eid) == "2020-01-01T10:00:00Z"


# ---------------------------------------------------------------------------
# Vietnamese labels
# ---------------------------------------------------------------------------


def test_repair_future_dates_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_future_entry(conn, description="Future entry")

    result = _invoke(["repair-future-dates", "--all"])
    assert result.exit_code == 0, result.output
    assert "Sửa bút toán có ngày trong tương lai" in result.output
    assert "ID bút toán" in result.output
    assert "Mô tả" in result.output
    assert "Ngày cũ" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


def test_repair_future_dates_dry_run_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_future_entry(conn, description="Future entry")

    result = _invoke(["repair-future-dates", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output


def test_repair_future_dates_locked_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_future_entry(conn, description="Locked entry", locked=True)

    result = _invoke(["repair-future-dates", "--all"])
    assert result.exit_code == 0, result.output
    assert "Khoá" in result.output or "khoá" in result.output
