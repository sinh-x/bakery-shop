"""Tests for ``baker repair-drawer-accounting`` CLI command — DG-351 Phase 4.3.

Covers the drawer accounting repair command (DG-348 + DG-349 unified) end to
end:

- FR1/FR3/AC3: repair closing_balance formula (opening_balance + net) matches
  what ``CashDrawer.close()`` persists (expected_balance from 1101 lines).
- FR4/AC4: backdated entries (transaction_date in the past, created_at now)
  are linked to the drawer whose period contains ``created_at`` — NOT
  ``transaction_date``.
- FR5: ``cash_drawer_auto_transfer`` and ``migration_balance_transfer``
  source_types are excluded from backfill.
- NFR1/AC8: repair is idempotent — a second run reports zero changes.
- NFR2/AC7: ``--dry-run`` previews all changes (JE#5975 update, backfill count,
  closing_balance updates) without modifying the database.
- NFR3: all journal entries remain balanced (SUM(debit) = SUM(credit)) after
  repair.
- NFR4: closing_balance is accurate to within 1 VND (INTEGER storage).
"""

import click
import click.testing

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.cash_drawer import CashDrawer


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

CASH_CODE = "1101"
EQUITY_CODE = "3100"
OWNER_CASH_CODE = "1102"
TARGET_AMOUNT = 330501500
JE_ID = 5975


def _account_id(conn, code: str) -> int:
    return int(
        conn.execute("SELECT id FROM accounts WHERE code = ?", (code,)).fetchone()[0]
    )


def _insert_drawer(
    conn,
    *,
    opened_at: str,
    opening_balance: int,
    status: str = "open",
    closed_at: str | None = None,
    closing_balance: int | None = "unset",
) -> int:
    """Insert a cash_drawer row directly (bypassing the API) and return its id.

    For closed drawers ``closing_balance`` defaults to ``opening_balance``,
    simulating the realistic pre-DG-347 state where a drawer was closed with
    no linked 1101 entries (so ``expected_balance`` was 0 and
    ``closing_balance`` was persisted as ``opening_balance``). Pass an int to
    override, or ``None`` to leave the column NULL.
    """
    if closing_balance == "unset":
        closing_balance = opening_balance if status == "closed" else None
    cur = conn.execute(
        "INSERT INTO cash_drawer "
        "(opened_at, opening_balance, status, closed_at, closing_balance) "
        "VALUES (?, ?, ?, ?, ?)",
        (opened_at, int(opening_balance), status, closed_at, closing_balance),
    )
    return int(cur.lastrowid)


def _insert_1101_entry(
    conn,
    *,
    amount: int,
    source_type: str,
    source_id: int | None = None,
    created_at: str,
    transaction_date: str | None = None,
    drawer_id: int | None = None,
    description: str = "test 1101 entry",
) -> int:
    """Insert a balanced 1101/3100 journal entry with explicit timestamps.

    ``amount > 0`` debits 1101 (cash in); ``amount < 0`` credits 1101 (cash out).
    ``created_at`` is the audit timestamp used for drawer-window matching.
    ``transaction_date`` is the business event date (defaults to created_at).
    ``drawer_id`` (optional) pre-links the entry to a drawer via the join table.
    """
    cash_acct = _account_id(conn, CASH_CODE)
    equity_acct = _account_id(conn, EQUITY_CODE)
    if transaction_date is None:
        transaction_date = created_at
    cur = conn.execute(
        "INSERT INTO journal_entries "
        "(description, source_type, source_id, transaction_date, created_at) "
        "VALUES (?, ?, ?, ?, ?)",
        (description, source_type, source_id, transaction_date, created_at),
    )
    entry_id = int(cur.lastrowid)
    if amount >= 0:
        debit_cash, credit_cash = float(amount), 0.0
        debit_eq, credit_eq = 0.0, float(amount)
    else:
        debit_cash, credit_cash = 0.0, float(-amount)
        debit_eq, credit_eq = float(-amount), 0.0
    conn.execute(
        "INSERT INTO journal_lines "
        "(journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, cash_acct, debit_cash, credit_cash, "cash leg"),
    )
    conn.execute(
        "INSERT INTO journal_lines "
        "(journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, ?, ?)",
        (entry_id, equity_acct, debit_eq, credit_eq, "equity leg"),
    )
    if drawer_id is not None:
        conn.execute(
            "INSERT OR IGNORE INTO cash_drawer_journal_entries "
            "(cash_drawer_id, journal_entry_id) VALUES (?, ?)",
            (int(drawer_id), entry_id),
        )
    return entry_id


def _seed_je5975(
    conn,
    *,
    amount: int = TARGET_AMOUNT,
    created_at: str = "2026-01-01T00:00:00Z",
    drawer_id: int | None = None,
) -> int:
    """Insert the JE#5975 auto-transfer entry the repair command updates.

    Lines: DR 1102 (owner cash), CR 1101 (drawer cash) — mirrors the production
    "transfer surplus from drawer to owner" entry. ``created_at`` defaults to
    a pre-drawer timestamp so the backfill step never touches it. When
    ``drawer_id`` is given the entry is pre-linked so it does not appear in the
    unlinked count.
    """
    owner_acct = _account_id(conn, OWNER_CASH_CODE)
    cash_acct = _account_id(conn, CASH_CODE)
    cur = conn.execute(
        "INSERT INTO journal_entries "
        "(id, description, source_type, source_id, transaction_date, created_at) "
        "VALUES (?, ?, 'cash_drawer_auto_transfer', NULL, ?, ?)",
        (JE_ID, "Chuyển tiền thừa từ quầy sang tiền mặt chủ sở hữu",
         created_at, created_at),
    )
    assert int(cur.lastrowid) == JE_ID
    conn.execute(
        "INSERT INTO journal_lines "
        "(journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, ?, 0.0, 'owner cash')",
        (JE_ID, owner_acct, float(amount)),
    )
    conn.execute(
        "INSERT INTO journal_lines "
        "(journal_entry_id, account_id, debit, credit, description) "
        "VALUES (?, ?, 0.0, ?, 'drawer cash')",
        (JE_ID, cash_acct, float(amount)),
    )
    if drawer_id is not None:
        conn.execute(
            "INSERT OR IGNORE INTO cash_drawer_journal_entries "
            "(cash_drawer_id, journal_entry_id) VALUES (?, ?)",
            (int(drawer_id), JE_ID),
        )
    return JE_ID


def _invoke(args):
    runner = click.testing.CliRunner()
    return runner.invoke(app, args)


def _drawer_closing_balance(conn, drawer_id: int) -> int | None:
    row = conn.execute(
        "SELECT closing_balance FROM cash_drawer WHERE id = ?", (drawer_id,)
    ).fetchone()
    return int(row["closing_balance"]) if row["closing_balance"] is not None else None


def _linked_entry_ids(conn, drawer_id: int) -> set[int]:
    rows = conn.execute(
        "SELECT journal_entry_id FROM cash_drawer_journal_entries "
        "WHERE cash_drawer_id = ?",
        (drawer_id,),
    ).fetchall()
    return {int(r["journal_entry_id"]) for r in rows}


def _je5975_amount(conn) -> int:
    row = conn.execute(
        "SELECT MAX(debit) AS d, MAX(credit) AS c FROM journal_lines "
        "WHERE journal_entry_id = ?",
        (JE_ID,),
    ).fetchone()
    return int(row["d"] or row["c"] or 0)


# ---------------------------------------------------------------------------
# Registration / help
# ---------------------------------------------------------------------------


def test_repair_drawer_accounting_registered():
    result = _invoke(["repair-drawer-accounting", "--help"])
    assert result.exit_code == 0, result.output
    assert "--dry-run" in result.output


# ---------------------------------------------------------------------------
# NFR2 / AC7 — dry-run previews all changes without mutating
# ---------------------------------------------------------------------------


def test_dry_run_previews_je5975_backfill_and_closing_balance_without_mutating(
    use_memory_db,
):
    """AC7: ``--dry-run`` previews the JE#5975 update, the backfill count, and
    the closing_balance updates without writing to the database."""
    with get_db() as conn:
        ensure_schema(conn)
        # JE#5975 with a WRONG amount so Step 1 has work to preview.
        _seed_je5975(conn, amount=313405500)
        # A closed drawer with an unlinked 1101 entry in its window. The drawer
        # was closed with closing_balance = opening_balance (the pre-DG-347
        # state — no linked entries, so expected_balance was 0 at close time).
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        entry_id = _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting", "--dry-run"])
    assert result.exit_code == 0, result.output
    assert "[DRY RUN]" in result.output
    # JE#5975 update is previewed.
    assert "330.501.500" in result.output or "330,501,500" in result.output
    # Backfill count is previewed.
    assert "1 bút toán 1101 cần liên kết" in result.output
    # Closing balance update is previewed.
    assert "closing_balance" in result.output

    # Database unchanged: JE#5975 amount still the wrong amount.
    with get_db() as conn:
        assert _je5975_amount(conn) == 313405500
        # Entry still unlinked.
        assert _linked_entry_ids(conn, drawer_id) == set()
        assert entry_id not in _linked_entry_ids(conn, drawer_id)
        # closing_balance still the pre-DG-347 value (opening_balance).
        assert _drawer_closing_balance(conn, drawer_id) == 1_000_000


# ---------------------------------------------------------------------------
# FR1 / FR3 / AC3 — repair formula matches live close()
# ---------------------------------------------------------------------------


def test_repair_closing_balance_matches_live_close(use_memory_db):
    """AC3: for the same opening_balance and net 1101 activity, the repair
    command's ``new_closing = opening_balance + net`` equals the
    ``closing_balance`` that ``CashDrawer.close()`` persists (which is
    ``expected_balance`` derived from linked 1101 lines)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn)  # no-op for Step 1; out of all drawer windows

        # Drawer A: live close path. Link an opening 1101 entry for
        # opening_balance (mirrors the API's cash_drawer_open journal entry)
        # plus a +500,000 adjustment, then call CashDrawer.close() —
        # closing_balance = expected_balance = 1,000,000 + 500,000.
        drawer_a = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            opening_balance=1_000_000,
        )
        _insert_1101_entry(
            conn,
            amount=1_000_000,
            source_type="cash_drawer_open",
            created_at="2026-07-01T08:00:00Z",
            drawer_id=drawer_a,
        )
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
            drawer_id=drawer_a,
        )
        a = CashDrawer.get_by_id(conn, drawer_a)
        a.close(conn, counted_amount=1_500_000)
        live_closing = _drawer_closing_balance(conn, drawer_a)
        assert live_closing == 1_500_000

        # Drawer B: repair path. Same opening_balance and net, but the 1101
        # entry is UNLINKED and closing_balance is the pre-DG-347 value
        # (opening_balance, since expected_balance was 0 at close time). The
        # repair command must compute the same closing_balance as drawer A.
        drawer_b = _insert_drawer(
            conn,
            opened_at="2026-07-02T08:00:00Z",
            closed_at="2026-07-02T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-02T12:00:00Z",
            # deliberately NOT linked
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        repaired_closing = _drawer_closing_balance(conn, drawer_b)
        # FR3: new_closing = opening_balance + net = 1,000,000 + 500,000.
        assert repaired_closing == 1_500_000
        # AC3: repair closing_balance matches the live close() closing_balance.
        assert repaired_closing == live_closing


# ---------------------------------------------------------------------------
# NFR1 / AC8 — idempotency
# ---------------------------------------------------------------------------


def test_repair_is_idempotent_second_run_no_changes(use_memory_db):
    """AC8: running the repair command twice leaves the database unchanged on
    the second run (no new links, no closing_balance updates)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn)
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
        )
        conn.commit()

    r1 = _invoke(["repair-drawer-accounting"])
    assert r1.exit_code == 0, r1.output
    assert "1 bút toán 1101 cần liên kết" in r1.output

    with get_db() as conn:
        linked_after_first = _linked_entry_ids(conn, drawer_id)
        closing_after_first = _drawer_closing_balance(conn, drawer_id)
        assert len(linked_after_first) == 1
        assert closing_after_first == 1_500_000
        conn.commit()

    r2 = _invoke(["repair-drawer-accounting"])
    assert r2.exit_code == 0, r2.output
    # Second run: no 1101 entries need linking (backfill query excludes already
    # linked entries via ``je.id NOT IN (SELECT ... FROM cdje)``).
    assert "1 bút toán 1101 cần liên kết" not in r2.output

    with get_db() as conn:
        assert _linked_entry_ids(conn, drawer_id) == linked_after_first
        assert _drawer_closing_balance(conn, drawer_id) == closing_after_first


# ---------------------------------------------------------------------------
# FR4 / AC4 — backdated entry assignment by created_at (not transaction_date)
# ---------------------------------------------------------------------------


def test_backdated_entry_linked_by_created_at_not_transaction_date(use_memory_db):
    """AC4: an entry with ``transaction_date`` in drawer A's window but
    ``created_at`` in drawer B's window is linked to drawer B (created_at
    governs windowing), not drawer A."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn)
        # Drawer A: July 1.
        drawer_a = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T23:59:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        # Drawer B: July 2.
        drawer_b = _insert_drawer(
            conn,
            opened_at="2026-07-02T08:00:00Z",
            closed_at="2026-07-02T23:59:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        # Backdated entry: transaction_date = July 1 (drawer A's window), but
        # created_at = July 2 12:00 (drawer B's window). Must link to drawer B.
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-02T12:00:00Z",
            transaction_date="2026-07-01T12:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        # Entry linked to drawer B (created_at window), NOT drawer A.
        b_links = _linked_entry_ids(conn, drawer_b)
        a_links = _linked_entry_ids(conn, drawer_a)
        assert len(b_links) == 1
        assert len(a_links) == 0
        # Drawer B closing_balance = opening + net = 1,000,000 + 500,000.
        assert _drawer_closing_balance(conn, drawer_b) == 1_500_000
        # Drawer A had no linked 1101 activity: closing_balance stays at its
        # pre-repair value (opening_balance), since new_closing == old_closing
        # and the repair command skips the write.
        assert _drawer_closing_balance(conn, drawer_a) == 1_000_000


# ---------------------------------------------------------------------------
# FR5 — source_type exclusions
# ---------------------------------------------------------------------------


def test_repair_excludes_cash_drawer_auto_transfer(use_memory_db):
    """FR5: entries with ``source_type = 'cash_drawer_auto_transfer'`` are
    excluded from backfill (they are already linked at creation time)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn)
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        auto_entry = _insert_1101_entry(
            conn,
            amount=300_000,
            source_type="cash_drawer_auto_transfer",
            created_at="2026-07-01T12:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        # The auto_transfer entry was NOT backfilled.
        assert auto_entry not in _linked_entry_ids(conn, drawer_id)
        # closing_balance = opening_balance + 0 (net from backfill is 0).
        assert _drawer_closing_balance(conn, drawer_id) == 1_000_000


def test_repair_excludes_migration_balance_transfer(use_memory_db):
    """FR5: entries with ``source_type = 'migration_balance_transfer'`` are
    excluded from backfill."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn)
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        mig_entry = _insert_1101_entry(
            conn,
            amount=400_000,
            source_type="migration_balance_transfer",
            created_at="2026-07-01T12:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        assert mig_entry not in _linked_entry_ids(conn, drawer_id)
        assert _drawer_closing_balance(conn, drawer_id) == 1_000_000


# ---------------------------------------------------------------------------
# NFR3 — double-entry integrity after repair
# ---------------------------------------------------------------------------


def test_repair_preserves_double_entry_integrity(use_memory_db):
    """NFR3: after the repair command runs, every journal entry remains
    balanced (SUM(debit) = SUM(credit))."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn, amount=313405500)  # Step 1 will rewrite the amount
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
        )
        _insert_1101_entry(
            conn,
            amount=-200_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T13:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        rows = conn.execute(
            "SELECT je.id, SUM(jl.debit) AS td, SUM(jl.credit) AS tc "
            "FROM journal_entries je "
            "JOIN journal_lines jl ON jl.journal_entry_id = je.id "
            "GROUP BY je.id"
        ).fetchall()
        assert len(rows) > 0
        for row in rows:
            assert abs(float(row["td"]) - float(row["tc"])) < 0.005, (
                f"Entry {row['id']}: debit {row['td']} != credit {row['tc']}"
            )
        # closing_balance = opening + net = 1,000,000 + 500,000 - 200,000.
        assert _drawer_closing_balance(conn, drawer_id) == 1_300_000


# ---------------------------------------------------------------------------
# NFR4 — closing_balance accurate to within 1 VND (INTEGER storage)
# ---------------------------------------------------------------------------


def test_repair_closing_balance_is_integer_and_accurate(use_memory_db):
    """NFR4: the persisted closing_balance is an INTEGER and equals
    opening_balance + net exactly (no floating-point drift)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn)
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        # Net = +500,000 - 1 = +499,999 (odd amount to catch float drift).
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
        )
        _insert_1101_entry(
            conn,
            amount=-1,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T13:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        row = conn.execute(
            "SELECT closing_balance, typeof(closing_balance) AS t "
            "FROM cash_drawer WHERE id = ?",
            (drawer_id,),
        ).fetchone()
        assert row["t"] == "integer"
        assert int(row["closing_balance"]) == 1_000_000 + 500_000 - 1


# ---------------------------------------------------------------------------
# Step 1 — JE#5975 amount correction
# ---------------------------------------------------------------------------


def test_repair_updates_je5975_amount(use_memory_db):
    """Step 1: the JE#5975 auto-transfer entry amount is corrected to
    TARGET_AMOUNT (330,501,500) and remains balanced after the update."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn, amount=313405500)
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        assert _je5975_amount(conn) == TARGET_AMOUNT
        # The updated entry remains balanced.
        row = conn.execute(
            "SELECT SUM(jl.debit) AS td, SUM(jl.credit) AS tc "
            "FROM journal_lines jl WHERE jl.journal_entry_id = ?",
            (JE_ID,),
        ).fetchone()
        assert abs(float(row["td"]) - float(row["tc"])) < 0.005


def test_repair_skips_je5975_when_already_correct(use_memory_db):
    """Step 1 is a no-op when JE#5975 already has the target amount (the
    command reports 'đã có số tiền đúng' / 'Bỏ qua')."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn, amount=TARGET_AMOUNT)
        conn.commit()

    result = _invoke(["repair-drawer-accounting"])
    assert result.exit_code == 0, result.output
    assert "Bỏ qua" in result.output

    with get_db() as conn:
        assert _je5975_amount(conn) == TARGET_AMOUNT


# ---------------------------------------------------------------------------
# repair-drawer-journal-backfill (DG-351 Phase 4.4 / CQ-3)
#
# The journal-backfill command shares the backfill + closing_balance + unlinked
# breakdown logic with repair-drawer-accounting but omits the JE#5975 Step 1.
# These tests cover registration and the source_type exclusion filter.
# ---------------------------------------------------------------------------


def test_repair_drawer_journal_backfill_registered():
    """Smoke test: the ``repair-drawer-journal-backfill`` command is registered
    and responds to ``--help`` with the ``--dry-run`` option."""
    result = _invoke(["repair-drawer-journal-backfill", "--help"])
    assert result.exit_code == 0, result.output
    assert "--dry-run" in result.output


def test_journal_backfill_links_entries_and_excludes_source_types(use_memory_db):
    """CQ-3: the backfill step links 1101 entries in a drawer's window and
    recomputes closing_balance, while excluding ``migration_balance_transfer``
    and ``cash_drawer_auto_transfer`` source_types from both the backfill and
    the unlinked-breakdown counts. The unlinked breakdown is printed."""
    with get_db() as conn:
        ensure_schema(conn)
        # No JE#5975 here — this command does not touch it. Seed one anyway to
        # confirm the journal-backfill command leaves it alone (it has no
        # Step 1) and that its source_type is excluded from the breakdown.
        _seed_je5975(conn, amount=313405500)

        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        # A normal 1101 entry in the drawer window — must be linked.
        linkable = _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
        )
        # Excluded source_type 1: cash_drawer_auto_transfer — must NOT be
        # linked and must NOT appear in the unlinked-breakdown counts.
        auto_entry = _insert_1101_entry(
            conn,
            amount=300_000,
            source_type="cash_drawer_auto_transfer",
            created_at="2026-07-01T13:00:00Z",
        )
        # Excluded source_type 2: migration_balance_transfer — same.
        mig_entry = _insert_1101_entry(
            conn,
            amount=400_000,
            source_type="migration_balance_transfer",
            created_at="2026-07-01T14:00:00Z",
        )
        conn.commit()

    result = _invoke(["repair-drawer-journal-backfill"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        linked = _linked_entry_ids(conn, drawer_id)
        assert linkable in linked
        assert auto_entry not in linked
        assert mig_entry not in linked
        # closing_balance = opening + net of linked = 1,000,000 + 500,000.
        assert _drawer_closing_balance(conn, drawer_id) == 1_500_000

    # The breakdown line is printed and reports zero unlinked-within (category
    # b) entries: every linkable entry was linked, and the excluded
    # source_types are filtered out of the breakdown counts too.
    assert "ngoài mọi drawer window" in result.output
    assert "trong drawer window nhưng chưa liên kết" in result.output


def test_journal_backfill_does_not_touch_je5975(use_memory_db):
    """The journal-backfill command has no Step 1 — JE#5975 is left untouched
    (unlike repair-drawer-accounting, which rewrites its amount)."""
    with get_db() as conn:
        ensure_schema(conn)
        _seed_je5975(conn, amount=313405500)
        _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        conn.commit()

    result = _invoke(["repair-drawer-journal-backfill"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        # JE#5975 amount unchanged — the backfill command does not repair it.
        assert _je5975_amount(conn) == 313405500


# ---------------------------------------------------------------------------
# CQ-1 (DG-351 review remediation) — unlinked-breakdown invariant
#
# count_unlinked_total() must apply the same _EXCLUDED_SOURCE_TYPES filter as
# count_unlinked_outside_any_drawer(); otherwise the breakdown invariant
# ``total = outside + within`` is violated and ``within`` (category b) is
# inflated by the count of excluded-source_type entries, masking a fully
# successful backfill as "still has unlinked-within entries".
# ---------------------------------------------------------------------------


def test_unlinked_breakdown_invariant_with_excluded_source_types(use_memory_db):
    """CQ-1: ``unlinked_breakdown()`` honours ``total = outside + within`` even
    when ``migration_balance_transfer`` / ``cash_drawer_auto_transfer`` entries
    are present. Before the fix, ``count_unlinked_total`` omitted the
    ``source_type NOT IN (...)`` filter that ``count_unlinked_outside_any_drawer``
    applied, so ``total`` counted the excluded entries while ``outside`` did
    not — yielding ``within > 0`` even after a fully successful backfill.
    """
    from baker.commands.repair import _backfill

    with get_db() as conn:
        ensure_schema(conn)
        # A closed drawer window.
        drawer_id = _insert_drawer(
            conn,
            opened_at="2026-07-01T08:00:00Z",
            closed_at="2026-07-01T20:00:00Z",
            opening_balance=1_000_000,
            status="closed",
        )
        # A normal linkable 1101 entry inside the drawer window.
        _insert_1101_entry(
            conn,
            amount=500_000,
            source_type="cash_drawer_test_adjust",
            created_at="2026-07-01T12:00:00Z",
        )
        # An excluded cash_drawer_auto_transfer entry inside the drawer
        # window — must not be linked and must not be counted in the
        # breakdown.
        _insert_1101_entry(
            conn,
            amount=300_000,
            source_type="cash_drawer_auto_transfer",
            created_at="2026-07-01T13:00:00Z",
        )
        # An excluded migration_balance_transfer entry OUTSIDE the drawer
        # window (orphaned) — must not be counted in the breakdown either.
        _insert_1101_entry(
            conn,
            amount=400_000,
            source_type="migration_balance_transfer",
            created_at="2026-06-15T12:00:00Z",
        )
        conn.commit()

    # Run the backfill so the normal linkable entry is linked; the two
    # excluded entries remain unlinked but must NOT inflate the breakdown.
    result = _invoke(["repair-drawer-journal-backfill"])
    assert result.exit_code == 0, result.output

    with get_db() as conn:
        outside, within, total = _backfill.unlinked_breakdown(conn)
        # The invariant must hold.
        assert total == outside + within, (
            f"breakdown invariant violated: total={total}, "
            f"outside={outside}, within={within}"
        )
        # After a successful backfill there are no unlinked-within entries.
        assert within == 0, (
            f"expected within == 0 after successful backfill, got {within}; "
            "excluded source_types likely leaked into count_unlinked_total()"
        )
        # ``outside`` may be 0 here too (the orphaned migration entry is
        # excluded), so ``total`` must also be 0.
        assert total == 0