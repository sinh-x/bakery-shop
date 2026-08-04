"""Shared backfill helpers for the drawer repair commands (DG-351 Phase 4.4).

Both ``repair-drawer-accounting`` and ``repair-drawer-journal-backfill`` run the
same backfill step (link 1101 journal entries to the drawer whose
``[opened_at, closed_at]`` window contains ``created_at``), recompute
``closing_balance`` for closed drawers, and report an unlinked-entry breakdown
split into "outside any drawer window" (orphaned) and "within a drawer window
but not yet linked". Before this module the two commands duplicated that logic
(~80% overlap); it now lives here.

Two-pass matching
=================
The backfill runs in two passes:

1. **Primary pass** — match on ``created_at`` window. This is the normal case:
   entries created while a drawer was open.

2. **Fallback pass** — match remaining unlinked entries on ``transaction_date``
   window. This handles entries whose ``created_at`` is outside all drawer
   windows (e.g. bulk re-created by a journal re-sync after the last drawer
   closed) but whose ``transaction_date`` reflects the actual business time
   within a drawer period.

Orphaned Entry Gap (Phase 4.2 documentation)
============================================
Journal entries created BETWEEN auto-close of one drawer and the next drawer's
open() have drawer_id=None and cannot be linked by the time-window matching
logic below. The time-window matcher uses opened_at <= created_at <= closed_at;
an entry whose created_at falls in the gap between closed_at of the previous
drawer and opened_at of the next drawer matches no drawer.

Two categories of unlinked entries exist:
  (a) "outside any drawer window" — created_at falls before the first drawer
      opened_at, after the last drawer closed_at, or between two drawer periods
      (the auto-close → next-open gap). These are the orphaned entries. After
      the transaction_date fallback pass, only entries with neither created_at
      nor transaction_date in a drawer window remain orphaned. They are
      correctly left unlinked; the repair command cannot retroactively assign
      them without a business decision on which drawer should absorb them.
  (b) "within a drawer window but unlinked" — created_at falls inside a
      drawer's [opened_at, closed_at] window but the entry is not in
      cash_drawer_journal_entries. This is the set the backfill step links;
      after a successful repair, category (b) should be empty.

The unlinked count reported in the summary below includes BOTH categories. The
repair command does not silently drop orphaned entries; they remain visible in
the unlinked count for manual review. A separate follow-up ticket may decide
whether to retroactively assign orphaned entries to a drawer or to treat them
as pre-drawer activity.

See AC6 (drawer-accounting-audit requirements doc) for the orphaned entry
acceptance criterion.
"""

from __future__ import annotations

import click

# source_types excluded from backfill: these are already linked at creation
# time (auto-transfer) or represent pre-drawer migration balances.
_EXCLUDED_SOURCE_TYPES = (
    "migration_balance_transfer",
    "cash_drawer_auto_transfer",
)


def _select_unlinked_1101_entries(conn, drawer_id: int, opened_at, closed_at):
    """Return 1101 journal entries in a drawer's window not yet linked to it.

    Mirrors the closed-drawer variant: ``opened_at <= created_at <= closed_at``.
    Excludes ``_EXCLUDED_SOURCE_TYPES`` source_types (FR5) and entries already
    linked to this drawer.
    """
    placeholders = ", ".join("?" for _ in _EXCLUDED_SOURCE_TYPES)
    return conn.execute(
        f"""
        SELECT je.id, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.created_at >= ?
          AND je.created_at <= ?
          AND je.source_type NOT IN ({placeholders})
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
              WHERE cash_drawer_id = ?
          )
        ORDER BY je.created_at
        """,
        (opened_at, closed_at, *_EXCLUDED_SOURCE_TYPES, drawer_id),
    ).fetchall()


def _select_unlinked_1101_entries_open(conn, drawer_id: int, opened_at):
    """Return 1101 journal entries in an open drawer's window not yet linked.

    Open-drawer variant: only an ``opened_at`` lower bound (no ``closed_at``).
    Same source_type exclusions and already-linked exclusion as the closed
    variant.
    """
    placeholders = ", ".join("?" for _ in _EXCLUDED_SOURCE_TYPES)
    return conn.execute(
        f"""
        SELECT je.id, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.created_at >= ?
          AND je.source_type NOT IN ({placeholders})
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
              WHERE cash_drawer_id = ?
          )
        ORDER BY je.created_at
        """,
        (opened_at, *_EXCLUDED_SOURCE_TYPES, drawer_id),
    ).fetchall()


def _select_unlinked_1101_by_txn_date(conn, drawer_id: int, opened_at, closed_at):
    """Return unlinked 1101 entries matching by transaction_date window.

    Fallback pass: for entries whose ``created_at`` falls outside all drawer
    windows, try matching ``transaction_date`` to the drawer period instead.
    Only considers entries still unlinked (not linked to ANY drawer) after
    the primary pass.
    """
    placeholders = ", ".join("?" for _ in _EXCLUDED_SOURCE_TYPES)
    return conn.execute(
        f"""
        SELECT je.id, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.transaction_date >= ?
          AND je.transaction_date <= ?
          AND je.source_type NOT IN ({placeholders})
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
          )
        ORDER BY je.transaction_date
        """,
        (opened_at, closed_at, *_EXCLUDED_SOURCE_TYPES),
    ).fetchall()


def _select_unlinked_1101_by_txn_date_open(
    conn, drawer_id: int, opened_at
):
    """Open-drawer variant of _select_unlinked_1101_by_txn_date."""
    placeholders = ", ".join("?" for _ in _EXCLUDED_SOURCE_TYPES)
    return conn.execute(
        f"""
        SELECT je.id, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.transaction_date >= ?
          AND je.source_type NOT IN ({placeholders})
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
          )
        ORDER BY je.transaction_date
        """,
        (opened_at, *_EXCLUDED_SOURCE_TYPES),
    ).fetchall()


def _run_txn_date_fallback(
    conn,
    *,
    dry_run: bool,
    closing_updates: list,
    primary_entry_ids: set[int],
) -> int:
    """Fallback pass: link remaining unlinked entries by transaction_date.

    After the primary ``created_at`` pass, leftover unlinked entries may
    have a ``transaction_date`` within a drawer window even though their
    ``created_at`` is outside (e.g. bulk journal re-sync after drawer close).
    This pass matches those entries to the appropriate drawer and links them.

    Merges fallback closing_balance changes into the ``closing_updates`` list
    from the primary pass so the final totals are correct.

    ``primary_entry_ids`` is the set of entry IDs already handled by the
    primary pass — they are excluded here to prevent double-counting on
    dry runs (where the primary pass did not write to the DB).
    """
    drawers = conn.execute(
        "SELECT * FROM cash_drawer ORDER BY id"
    ).fetchall()
    if not drawers:
        return 0

    # Build a lookup of primary-pass new closing_balance values
    primary_update_by_drawer: dict = {
        u["drawer_id"]: u["new"] for u in closing_updates
    }

    total_linked = 0
    for drawer in drawers:
        drawer_id = drawer["id"]
        opened = drawer["opened_at"]
        closed = drawer["closed_at"]

        if closed:
            entries = _select_unlinked_1101_by_txn_date(
                conn, drawer_id, opened, closed
            )
        else:
            entries = _select_unlinked_1101_by_txn_date_open(
                conn, drawer_id, opened
            )

        entries = [e for e in entries if e["id"] not in primary_entry_ids]

        if not entries:
            continue

        net = sum(r["debit"] - r["credit"] for r in entries)
        total_linked += len(entries)

        click.echo(
            f"  Drawer #{drawer_id} (fallback — transaction_date): "
            f"{len(entries)} bút toán bổ sung"
        )
        click.echo(f"    Tổng net bổ sung: {net:+,.0f}")

        if not dry_run:
            _link_entries(conn, drawer_id, entries)

        if drawer["status"] == "closed":
            base = primary_update_by_drawer.get(
                drawer_id, drawer["closing_balance"]
            )
            new_closing = base + net
            prefix = "[DRY RUN] " if dry_run else ""
            click.echo(
                f"    {prefix}closing_balance: "
                f"{base:,.0f} → {new_closing:,.0f}"
            )
            if not dry_run:
                conn.execute(
                    "UPDATE cash_drawer SET closing_balance = ? WHERE id = ?",
                    (new_closing, drawer_id),
                )
            # Update the primary updates list for final summary
            existing = next(
                (u for u in closing_updates if u["drawer_id"] == drawer_id),
                None,
            )
            if existing:
                existing["new"] = new_closing
            else:
                closing_updates.append({
                    "drawer_id": drawer_id,
                    "old": drawer["closing_balance"],
                    "new": new_closing,
                })

    return total_linked


def _link_entries(conn, drawer_id: int, entries) -> None:
    """INSERT OR IGNORE each entry into cash_drawer_journal_entries (idempotent)."""
    for entry in entries:
        conn.execute(
            "INSERT OR IGNORE INTO cash_drawer_journal_entries "
            "(cash_drawer_id, journal_entry_id) VALUES (?, ?)",
            (drawer_id, entry["id"]),
        )


def _maybe_update_closing_balance(
    conn, drawer, net: int, dry_run: bool, closing_updates: list
) -> None:
    """Recompute closing_balance for a closed drawer if it would change.

    ``new_closing = opening_balance + net`` (FR1/FR3/AC3). On a dry run the
    update is recorded in ``closing_updates`` but not persisted. On a real run
    the row is updated and the change is recorded. Only closed drawers are
    eligible; open drawers skip this step.
    """
    if drawer["status"] != "closed":
        return
    new_closing = drawer["opening_balance"] + net
    old_closing = drawer["closing_balance"]
    if new_closing == old_closing:
        return
    if not dry_run:
        conn.execute(
            "UPDATE cash_drawer SET closing_balance = ? WHERE id = ?",
            (new_closing, drawer["id"]),
        )
    closing_updates.append({
        "drawer_id": drawer["id"],
        "old": old_closing,
        "new": new_closing,
    })
    prefix = "[DRY RUN] " if dry_run else ""
    click.echo(
        f"  {prefix}closing_balance: {old_closing:,.0f} → {new_closing:,.0f}"
    )


def run_drawer_backfill(conn, *, dry_run: bool):
    """Backfill cash_drawer_journal_entries and recompute closing_balances.

    Two-pass matching:

    1. Primary pass: links 1101 journal entries whose ``created_at`` falls
       in the drawer's window (excluding ``migration_balance_transfer`` and
       ``cash_drawer_auto_transfer``).
    2. Fallback pass: links remaining unlinked entries whose
       ``transaction_date`` falls in the drawer's window (handles entries
       bulk re-created after drawer close, e.g. journal re-sync).

    Recomputes ``closing_balance`` for closed drawers from the linked net.

    Returns a tuple ``(total_linked, closing_updates)``:
      - ``total_linked``: count of entries linked this run (or that would be on
        a dry run).
      - ``closing_updates``: list of ``{"drawer_id","old","new"}`` dicts for
        drawers whose closing_balance changed.
    """
    drawers = conn.execute(
        "SELECT * FROM cash_drawer ORDER BY id"
    ).fetchall()
    if not drawers:
        click.echo("Không có cash drawer nào trong CSDL.")
        return 0, []

    total_linked = 0
    closing_updates: list = []
    primary_entry_ids: set[int] = set()

    # ── Primary pass: created_at matching ──
    for drawer in drawers:
        drawer_id = drawer["id"]
        opened = drawer["opened_at"]
        closed = drawer["closed_at"]
        status = drawer["status"]

        if closed:
            entries = _select_unlinked_1101_entries(conn, drawer_id, opened, closed)
        else:
            entries = _select_unlinked_1101_entries_open(conn, drawer_id, opened)

        if not entries:
            continue

        primary_entry_ids.update(r["id"] for r in entries)

        net = sum(r["debit"] - r["credit"] for r in entries)

        click.echo(
            f"Drawer #{drawer_id} ({status}): "
            f"{opened} → {closed or 'đang mở'}"
        )
        click.echo(f"  {len(entries)} bút toán 1101 cần liên kết")
        click.echo(f"  Tổng net: {net:+,.0f}")

        total_linked += len(entries)
        if not dry_run:
            _link_entries(conn, drawer_id, entries)
        _maybe_update_closing_balance(conn, drawer, net, dry_run, closing_updates)
        click.echo()

    # ── Fallback pass: transaction_date matching ──
    fallback_linked = _run_txn_date_fallback(
        conn,
        dry_run=dry_run,
        closing_updates=closing_updates,
        primary_entry_ids=primary_entry_ids,
    )
    total_linked += fallback_linked

    return total_linked, closing_updates


def count_unlinked_outside_any_drawer(conn) -> int:
    """Count 1101 entries unlinked and outside every drawer window (orphaned).

    Category (a) in the orphaned-entry breakdown: entries not in
    cash_drawer_journal_entries where NEITHER ``created_at`` NOR
    ``transaction_date`` falls in any drawer's ``[opened_at, closed_at]``
    window. Excludes ``_EXCLUDED_SOURCE_TYPES`` so the breakdown reflects
    the entries the backfill step could plausibly link.

    After the transaction_date fallback pass, only entries with both
    timestamps outside all windows remain truly orphaned.
    """
    placeholders = ", ".join("?" for _ in _EXCLUDED_SOURCE_TYPES)
    return conn.execute(
        f"""
        SELECT COUNT(*) as cnt
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.source_type NOT IN ({placeholders})
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
          )
          AND NOT EXISTS (
              SELECT 1 FROM cash_drawer d
              WHERE d.opened_at IS NOT NULL
                AND je.created_at >= d.opened_at
                AND (d.closed_at IS NULL
                     OR je.created_at <= d.closed_at)
          )
          AND NOT EXISTS (
              SELECT 1 FROM cash_drawer d
              WHERE d.opened_at IS NOT NULL
                AND je.transaction_date >= d.opened_at
                AND (d.closed_at IS NULL
                     OR je.transaction_date <= d.closed_at)
          )
        """,
        tuple(_EXCLUDED_SOURCE_TYPES),
    ).fetchone()["cnt"]


def count_unlinked_total(conn) -> int:
    """Count all 1101 entries not present in cash_drawer_journal_entries.

    This is the total unlinked count (categories (a) + (b)); the breakdown's
    "within a drawer window but unlinked" figure is ``total - outside``.

    Applies the same ``_EXCLUDED_SOURCE_TYPES`` filter as
    ``count_unlinked_outside_any_drawer`` so the breakdown invariant
    ``total = outside + within`` holds. Without this filter, ``total`` would
    include ``migration_balance_transfer`` / ``cash_drawer_auto_transfer``
    entries that ``outside`` excludes, skewing ``within = total - outside``
    and producing a non-zero "within" count even after a fully successful
    backfill.
    """
    placeholders = ", ".join("?" for _ in _EXCLUDED_SOURCE_TYPES)
    return conn.execute(
        f"""
        SELECT COUNT(*) as cnt
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.source_type NOT IN ({placeholders})
          AND je.id NOT IN (
              SELECT journal_entry_id FROM cash_drawer_journal_entries
          )
        """,
        tuple(_EXCLUDED_SOURCE_TYPES),
    ).fetchone()["cnt"]


def unlinked_breakdown(conn) -> tuple[int, int, int]:
    """Return ``(outside, within, total)`` unlinked-entry counts.

    - ``outside``: orphaned entries (category a) — not in any drawer window.
    - ``within``: in a drawer window but still unlinked (category b) — should
      be 0 after a successful repair.
    - ``total``: outside + within.
    """
    outside = count_unlinked_outside_any_drawer(conn)
    total = count_unlinked_total(conn)
    within = total - outside
    return outside, within, total


def print_unlinked_breakdown(outside: int, within: int) -> None:
    """Print the unlinked-entry breakdown line.

    Both repair commands emit the same breakdown line; centralizing it here
    keeps the wording consistent. Pass the values from ``unlinked_breakdown``
    to avoid recomputing.
    """
    click.echo(
        f"  Trong đó: {outside} ngoài mọi drawer window "
        f"(orphaned — không gán được), "
        f"{within} trong drawer window nhưng chưa liên kết."
    )