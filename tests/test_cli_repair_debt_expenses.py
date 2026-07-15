"""Tests for ``baker repair-debt-expenses`` CLI command — DG-245 Phase 6.

Covers (FR6, NFR4, NFR5, AC3, AC10):

- ``--all`` repairs both missing-JE (e.g. live event 6346) and stale-JE
  (e.g. live event 6348 crediting 1100 instead of a vendor 25xx sub-account)
- ``--event-id`` single-event repair (create + fix paths)
- ``--dry-run`` shows planned actions without mutating
- Idempotent: a second run is a no-op (no events flagged) (NFR4)
- Double-entry integrity preserved on created/repaired JEs (NFR5)
- Locked entries are skipped (not mutated)
- Non-debt expense events whose JE is correct are skipped
- Command registration / ``--help``
- Service-level helpers (``_expense_events_needing_debt_repair``,
  ``_process_debt_expense_repair``)
- After repair, ``expense_payment_account_mismatch`` validator passes for the
  repaired events (AC3 end-state)
"""

import json

import click
import click.testing

from baker.cli import app
from baker.commands.repair import (
    _expense_events_needing_debt_repair,
    _process_debt_expense_repair,
)
from baker.db.connection import get_db
from baker.db.schema import (
    ACCOUNTS_PAYABLE_CODE,
    EXPENSE_DEBT_PAYMENT_METHOD,
    ensure_schema,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _account_id(conn, code: str) -> int:
    return int(conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (code,)
    ).fetchone()[0])


def _account_row(conn, account_id: int):
    return conn.execute(
        "SELECT id, code, name, parent_id FROM accounts WHERE id = ?",
        (account_id,),
    ).fetchone()


def _insert_debt_expense_event(
    conn,
    *,
    summary: str,
    amount: float = 300000,
    vendor: str = "Nhà cung cấp A",
    category: str = "Vận chuyển",
) -> int:
    data = json.dumps({
        "amount_vnd": amount,
        "category": category,
        "payment_method": EXPENSE_DEBT_PAYMENT_METHOD,
        "payment_source": "",
        "vendor": vendor,
        "note": "ghi nợ",
        "paid_by_name": "",
    })
    cur = conn.execute(
        "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
        ("expense", summary, data),
    )
    return int(cur.lastrowid)


def _insert_cash_expense_event(
    conn,
    *,
    summary: str,
    amount: float = 200000,
    category: str = "Vận chuyển",
    payment_source: str = "Shop tiền mặt",
) -> int:
    data = json.dumps({
        "amount_vnd": amount,
        "category": category,
        "payment_source": payment_source,
        "payment_method": "",
        "vendor": "",
        "note": "",
        "paid_by_name": "",
    })
    cur = conn.execute(
        "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
        ("expense", summary, data),
    )
    return int(cur.lastrowid)


def _insert_expense_journal_entry(
    conn,
    *,
    event_id: int,
    debit_account_id: int,
    credit_account_id: int,
    amount: float,
    description: str = "Expense: test",
) -> int:
    cur = conn.execute(
        "INSERT INTO journal_entries (description, source_type, source_id) "
        "VALUES (?, 'expense', ?)",
        (description, event_id),
    )
    entry_id = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'Chi phí')",
        (entry_id, debit_account_id, amount),
    )
    conn.execute(
        "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'Thanh toán')",
        (entry_id, credit_account_id, amount),
    )
    return entry_id


def _expense_entry(conn, event_id: int):
    row = conn.execute(
        "SELECT id FROM journal_entries "
        "WHERE source_type = 'expense' AND source_id = ? "
        "AND description NOT LIKE 'Reversal:%' "
        "ORDER BY id DESC LIMIT 1",
        (event_id,),
    ).fetchone()
    return int(row["id"]) if row else None


def _expense_credit_account_id(conn, entry_id: int):
    row = conn.execute(
        "SELECT account_id FROM journal_lines "
        "WHERE journal_entry_id = ? AND credit > 0 "
        "ORDER BY id LIMIT 1",
        (entry_id,),
    ).fetchone()
    return int(row["account_id"]) if row else None


def _expense_debit_account_id(conn, entry_id: int):
    row = conn.execute(
        "SELECT account_id FROM journal_lines "
        "WHERE journal_entry_id = ? AND debit > 0 "
        "ORDER BY id LIMIT 1",
        (entry_id,),
    ).fetchone()
    return int(row["account_id"]) if row else None


def _double_entry_balanced(conn, entry_id: int) -> bool:
    row = conn.execute(
        "SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c "
        "FROM journal_lines WHERE journal_entry_id = ?",
        (entry_id,),
    ).fetchone()
    return abs(float(row["d"]) - float(row["c"])) < 0.005


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


# ---------------------------------------------------------------------------
# Registration & help
# ---------------------------------------------------------------------------


def test_debt_expenses_command_registered():
    result = _invoke(["repair-debt-expenses", "--help"])
    assert result.exit_code == 0, result.output
    assert "--event-id" in result.output
    assert "--all" in result.output
    assert "--dry-run" in result.output


def test_debt_expenses_requires_one_mode():
    result = _invoke(["repair-debt-expenses"])
    assert result.exit_code != 0
    assert "Cần chỉ định" in result.output


def test_debt_expenses_rejects_both_modes():
    result = _invoke(["repair-debt-expenses", "--event-id", "1", "--all"])
    assert result.exit_code != 0
    assert "cùng lúc" in result.output


# ---------------------------------------------------------------------------
# --all: create missing JE (event-6346-style)
# ---------------------------------------------------------------------------


def test_all_creates_missing_je_for_debt_expense():
    """Debt expense with no JE → repair creates JE crediting vendor 25xx sub-account."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ bột mì (missing JE)",
            amount=400000, vendor="Nhà cung cấp X",
        )
        assert _expense_entry(conn, eid) is None

    result = _invoke(["repair-debt-expenses", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert f"#{eid}" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_entry(conn, eid)
        assert entry_id is not None
        credit_acc_id = _expense_credit_account_id(conn, entry_id)
        credit_acc = _account_row(conn, credit_acc_id)
        assert credit_acc["code"].startswith("25") and credit_acc["code"] != "2500"
        assert credit_acc["name"] == "Nhà cung cấp X"
        parent = _account_row(conn, int(credit_acc["parent_id"]))
        assert parent["code"] == "2500"
        assert _double_entry_balanced(conn, entry_id)


def test_all_creates_inventory_debt_je_debits_1300():
    """Debt expense for an inventory category creates JE debiting 1300 (Inventory)."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ nguyên liệu (missing JE)",
            amount=250000, vendor="Nhà cung cấp Inv",
            category="Nguyên liệu",
        )
        assert _expense_entry(conn, eid) is None

    result = _invoke(["repair-debt-expenses", "--all"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_entry(conn, eid)
        assert entry_id is not None
        debit_acc_id = _expense_debit_account_id(conn, entry_id)
        debit_acc = _account_row(conn, debit_acc_id)
        assert debit_acc["code"] == "1300"
        assert _double_entry_balanced(conn, entry_id)


# ---------------------------------------------------------------------------
# --all: fix stale JE (event-6348-style)
# ---------------------------------------------------------------------------


def test_all_fixes_stale_je_crediting_cash():
    """Stale JE crediting 1100 (Cash) → repaired to credit vendor 25xx sub-account."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ bao bì (stale JE)",
            amount=500000, vendor="Chợ Ninh Diêm",
            category="Bao bì",
        )
        cash_acc = _account_id(conn, "1100")
        inv_acc = _account_id(conn, "1300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=inv_acc, credit_account_id=cash_acc,
            amount=500000,
        )
        stale_entry = _expense_entry(conn, eid)
        assert stale_entry is not None
        assert _expense_credit_account_id(conn, stale_entry) == cash_acc

    result = _invoke(["repair-debt-expenses", "--all"])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert f"#{eid}" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_entry(conn, eid)
        assert entry_id is not None
        credit_acc_id = _expense_credit_account_id(conn, entry_id)
        credit_acc = _account_row(conn, credit_acc_id)
        assert credit_acc["code"].startswith("25") and credit_acc["code"] != "2500"
        assert credit_acc["name"] == "Chợ Ninh Diêm"
        # Old stale entry is gone (cascaded delete); only one non-reversal entry
        rows = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ? "
            "AND description NOT LIKE 'Reversal:%'",
            (eid,),
        ).fetchall()
        assert len(rows) == 1
        assert _double_entry_balanced(conn, entry_id)


# ---------------------------------------------------------------------------
# --event-id: single-event create + fix
# ---------------------------------------------------------------------------


def test_event_id_creates_missing_je():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ đơn lẻ (missing)",
            amount=150000, vendor="Nhà cung cấp Single",
        )

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output
    assert f"#{eid}" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_entry(conn, eid) is not None


def test_event_id_fixes_stale_je():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ đơn lẻ (stale)",
            amount=220000, vendor="Nhà cung cấp Fix",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=220000,
        )

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_entry(conn, eid)
        credit_acc_id = _expense_credit_account_id(conn, entry_id)
        credit_acc = _account_row(conn, credit_acc_id)
        assert credit_acc["name"] == "Nhà cung cấp Fix"
        assert credit_acc["code"].startswith("25") and credit_acc["code"] != "2500"


def test_event_id_not_found_is_noop():
    result = _invoke(["repair-debt-expenses", "--event-id", "99999"])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện chi phí nợ nào cần sửa" in result.output


# ---------------------------------------------------------------------------
# Idempotency: second run is a no-op (NFR4, AC3)
# ---------------------------------------------------------------------------


def test_all_idempotent_second_run_no_events():
    """After --all repairs both create and fix cases, a second run finds nothing."""
    with get_db() as conn:
        ensure_schema(conn)
        eid_missing = _insert_debt_expense_event(
            conn, summary="Nợ idem (missing)",
            amount=300000, vendor="Nhà cung cấp Idem1",
        )
        eid_stale = _insert_debt_expense_event(
            conn, summary="Nợ idem (stale)",
            amount=180000, vendor="Nhà cung cấp Idem2",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid_stale,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=180000,
        )

    result1 = _invoke(["repair-debt-expenses", "--all"])
    assert result1.exit_code == 0, result1.output
    assert "đã sửa: 2" in result1.output

    # Second run — idempotent: no events need repair.
    result2 = _invoke(["repair-debt-expenses", "--all"])
    assert result2.exit_code == 0, result2.output
    assert "không có sự kiện chi phí nợ nào cần sửa" in result2.output


def test_double_run_preserves_single_entry_per_event():
    """Idempotency at the JE level: each event still has exactly one entry after two runs."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ double-run",
            amount=350000, vendor="Nhà cung cấp DR",
        )

    _invoke(["repair-debt-expenses", "--all"])
    _invoke(["repair-debt-expenses", "--all"])

    with get_db() as conn:
        ensure_schema(conn)
        rows = conn.execute(
            "SELECT id FROM journal_entries "
            "WHERE source_type = 'expense' AND source_id = ? "
            "AND description NOT LIKE 'Reversal:%'",
            (eid,),
        ).fetchall()
        assert len(rows) == 1
        assert _double_entry_balanced(conn, int(rows[0]["id"]))


# ---------------------------------------------------------------------------
# Dry-run
# ---------------------------------------------------------------------------


def test_dry_run_does_not_mutate_missing_je():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ dry (missing)",
            amount=100000, vendor="Nhà cung cấp Dry",
        )
        je_before = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries"
        ).fetchone()["c"]

    result = _invoke(["repair-debt-expenses", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output
    assert "đã sửa" not in result.output

    with get_db() as conn:
        ensure_schema(conn)
        assert _expense_entry(conn, eid) is None
        je_after = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries"
        ).fetchone()["c"]
        assert je_before == je_after


def test_dry_run_does_not_mutate_stale_je():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ dry (stale)",
            amount=120000, vendor="Nhà cung cấp DryS",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=120000,
        )

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid), "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_entry(conn, eid)
        assert entry_id is not None
        # Credit account unchanged (still cash 1100).
        assert _expense_credit_account_id(conn, entry_id) == _account_id(conn, "1100")


# ---------------------------------------------------------------------------
# Locked entries are skipped
# ---------------------------------------------------------------------------


def test_locked_stale_entry_is_skipped():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ locked",
            amount=200000, vendor="Nhà cung cấp Lock",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        entry_id = _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=200000,
        )
        conn.execute(
            "UPDATE journal_entries SET locked_at = ? WHERE id = ?",
            ("2026-07-01T00:00:00Z", entry_id),
        )

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện chi phí nợ nào cần sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        entry_id = _expense_entry(conn, eid)
        # Locked entry still credits cash (unchanged).
        assert _expense_credit_account_id(conn, entry_id) == _account_id(conn, "1100")


# ---------------------------------------------------------------------------
# Correct events are skipped
# ---------------------------------------------------------------------------


def test_correct_debt_je_is_skipped():
    """A debt expense whose JE already credits the vendor 25xx sub-account is skipped."""
    from baker.db.schema import _ensure_ap_vendor_sub_account

    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ correct",
            amount=300000, vendor="Nhà cung cấp OK",
        )
        vendor_acc = _ensure_ap_vendor_sub_account(conn, "Nhà cung cấp OK")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=vendor_acc,
            amount=300000,
        )

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện chi phí nợ nào cần sửa" in result.output


def test_correct_cash_je_is_skipped():
    """A non-debt cash expense whose JE credits the correct asset account is skipped."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_cash_expense_event(
            conn, summary="Cash correct",
            amount=150000, category="Vận chuyển",
            payment_source="Shop tiền mặt",
        )
        # Leave it without a JE — it would be a candidate for create, but we
        # instead build a correct JE and assert it is skipped.
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=150000,
        )

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện chi phí nợ nào cần sửa" in result.output


# ---------------------------------------------------------------------------
# Deleted events are excluded
# ---------------------------------------------------------------------------


def test_deleted_events_excluded():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ deleted",
            amount=200000, vendor="Nhà cung cấp Del",
        )
        conn.execute(
            "UPDATE events SET deleted_at = datetime('now') WHERE id = ?",
            (eid,),
        )

    result = _invoke(["repair-debt-expenses", "--all"])
    assert result.exit_code == 0, result.output
    assert "không có sự kiện chi phí nợ nào cần sửa" in result.output


# ---------------------------------------------------------------------------
# Vietnamese labels
# ---------------------------------------------------------------------------


def test_debt_expenses_vn_labels():
    with get_db() as conn:
        ensure_schema(conn)
        _insert_debt_expense_event(
            conn, summary="Nợ labels",
            amount=200000, vendor="Nhà cung cấp VN",
        )

    result = _invoke(["repair-debt-expenses", "--all"])
    assert result.exit_code == 0, result.output
    assert "Sửa bút toán chi phí nợ" in result.output
    assert "Mã SK" in result.output
    assert "Số tiền" in result.output
    assert "Hành động" in result.output
    assert "đã sửa" in result.output


# ---------------------------------------------------------------------------
# Service-level function tests
# ---------------------------------------------------------------------------


def test_service_detects_missing_je():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ svc missing",
            amount=200000, vendor="Nhà cung cấp SvcM",
        )
        events = _expense_events_needing_debt_repair(conn, event_id=eid)
        assert len(events) == 1
        assert events[0]["id"] == eid
        assert events[0]["action_kind"] == "create"


def test_service_detects_stale_je():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ svc stale",
            amount=200000, vendor="Nhà cung cấp SvcS",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=200000,
        )
        events = _expense_events_needing_debt_repair(conn, event_id=eid)
        assert len(events) == 1
        assert events[0]["id"] == eid
        assert events[0]["action_kind"] == "fix"


def test_service_process_create():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ svc create",
            amount=210000, vendor="Nhà cung cấp SvcC",
        )
        events = _expense_events_needing_debt_repair(conn, event_id=eid)
        result = _process_debt_expense_repair(conn, events[0], dry_run=False)
        assert result["action"] == "created"
        assert _expense_entry(conn, eid) is not None


def test_service_process_fix():
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ svc fix",
            amount=230000, vendor="Nhà cung cấp SvcF",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=230000,
        )
        events = _expense_events_needing_debt_repair(conn, event_id=eid)
        result = _process_debt_expense_repair(conn, events[0], dry_run=False)
        assert result["action"] == "repaired"
        entry_id = _expense_entry(conn, eid)
        credit_acc_id = _expense_credit_account_id(conn, entry_id)
        credit_acc = _account_row(conn, credit_acc_id)
        assert credit_acc["name"] == "Nhà cung cấp SvcF"


def test_service_dry_run_returns_will_actions():
    with get_db() as conn:
        ensure_schema(conn)
        eid_create = _insert_debt_expense_event(
            conn, summary="Nợ svc dry create",
            amount=200000, vendor="Nhà cung cấp SvcDC",
        )
        eid_fix = _insert_debt_expense_event(
            conn, summary="Nợ svc dry fix",
            amount=200000, vendor="Nhà cung cấp SvcDF",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid_fix,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=200000,
        )
        events = _expense_events_needing_debt_repair(conn)
        assert len(events) == 2
        for e in events:
            r = _process_debt_expense_repair(conn, e, dry_run=True)
            assert r["action"] in ("will-create", "will-repair")
        # No JEs created/mutated in dry-run.
        assert _expense_entry(conn, eid_create) is None


# ---------------------------------------------------------------------------
# AC3 end-state: validate-accounts expense_payment_account_mismatch passes
# after repair
# ---------------------------------------------------------------------------


def test_after_repair_validator_passes_for_fixed_event():
    """AC3 end-state: after repair, expense_payment_account_mismatch no longer
    flags the previously-stale event."""
    from baker.services.accounting_validation import _check_expense_payment_account_mismatch

    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ validate",
            amount=400000, vendor="Nhà cung cấp Val",
        )
        cash_acc = _account_id(conn, "1100")
        expense_acc = _account_id(conn, "5300")
        _insert_expense_journal_entry(
            conn, event_id=eid,
            debit_account_id=expense_acc, credit_account_id=cash_acc,
            amount=400000,
        )

    # Before repair — the validator should flag this event.
    with get_db() as conn:
        ensure_schema(conn)
        pre = _check_expense_payment_account_mismatch(conn)
        assert pre["status"] == "fail"
        flagged_ids = {f.get("event_id") for f in pre.get("details", [])}
        assert eid in flagged_ids

    # Repair.
    result = _invoke(["repair-debt-expenses", "--event-id", str(eid)])
    assert result.exit_code == 0, result.output
    assert "đã sửa" in result.output

    # After repair — the validator should no longer flag this event.
    with get_db() as conn:
        ensure_schema(conn)
        post = _check_expense_payment_account_mismatch(conn)
        flagged_ids_after = {f.get("event_id") for f in post.get("details", [])}
        assert eid not in flagged_ids_after


# ---------------------------------------------------------------------------
# Review-remediation verification (d-045718, DG-245 review d-b1fbbc)
# CQ-3: unmapped category is skipped (not flagged "will-create")
# CQ-4: --dry-run does not persist vendor sub-accounts
# ---------------------------------------------------------------------------


def test_dry_run_does_not_persist_vendor_sub_account():
    """CQ-4 (Minor): ``--dry-run`` detection must not INSERT vendor sub-accounts
    into ``accounts``. The detection path resolves the vendor → sub-account via
    a read-only lookup; the mutating ``_ensure_ap_vendor_sub_account`` helper is
    only called in apply mode."""
    with get_db() as conn:
        ensure_schema(conn)
        eid = _insert_debt_expense_event(
            conn, summary="Nợ dry persist",
            amount=100000, vendor="Nhà cung cấp NoPersist",
        )
        parent_id = int(conn.execute(
            "SELECT id FROM accounts WHERE code = '2500'"
        ).fetchone()[0])
        before = conn.execute(
            "SELECT COUNT(*) AS c FROM accounts WHERE parent_id = ?",
            (parent_id,),
        ).fetchone()["c"]
        conn.commit()

    result = _invoke(["repair-debt-expenses", "--all", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "sẽ sửa" in result.output

    with get_db() as conn:
        ensure_schema(conn)
        after = conn.execute(
            "SELECT COUNT(*) AS c FROM accounts WHERE parent_id = ?",
            (parent_id,),
        ).fetchone()["c"]
        # No new vendor sub-account was persisted during dry-run detection.
        assert after == before, (
            f"dry-run persisted a vendor sub-account: before={before} after={after}"
        )
        # The vendor sub-account for "Nhà cung cấp NoPersist" does not exist.
        row = conn.execute(
            "SELECT id FROM accounts WHERE parent_id = ? AND name = ?",
            (parent_id, "Nhà cung cấp NoPersist"),
        ).fetchone()
        assert row is None


def test_dry_run_unmapped_category_reports_skipped_not_will_create():
    """CQ-3 (Minor): an unmapped-category debt expense is by-design unjournalled,
    so ``--dry-run`` must not report it as ``will-create``. Detection mirrors the
    ``_build_expense_journal_lines`` category-map skip."""
    with get_db() as conn:
        ensure_schema(conn)
        # Unmapped category — _build_expense_journal_lines returns None.
        data = json.dumps({
            "amount_vnd": 200000,
            "category": "UnmappedCatXYZ",
            "payment_method": EXPENSE_DEBT_PAYMENT_METHOD,
            "payment_source": "",
            "vendor": "Nhà cung cấp Unmapped",
            "note": "",
            "paid_by_name": "",
        })
        cur = conn.execute(
            "INSERT INTO events (type, summary, data) VALUES (?, ?, ?)",
            ("expense", "Nợ unmapped", data),
        )
        eid = int(cur.lastrowid)
        conn.commit()

    result = _invoke(["repair-debt-expenses", "--event-id", str(eid), "--dry-run"])
    assert result.exit_code == 0, result.output
    # The event is skipped (no JE expected) — not reported as a create candidate.
    assert "không có sự kiện chi phí nợ nào cần sửa" in result.output
    assert f"#{eid}" not in result.output