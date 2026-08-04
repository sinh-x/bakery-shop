"""Shared backfill helpers for the drawer repair commands (DG-351 Phase 4.4).

Both ``repair-drawer-accounting`` and ``repair-drawer-journal-backfill`` run the
same backfill step (link 1101 journal entries to the drawer whose
``[opened_at, closed_at]`` window contains ``created_at``), recompute
``closing_balance`` for closed drawers, and report an unlinked-entry breakdown
split into "outside any drawer window" (orphaned) and "within a drawer window
but not yet linked". Before this module the two commands duplicated that logic
(~80% overlap); it now lives here.

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
      (the auto-close → next-open gap). These are the orphaned entries. They are
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
    Excludes ``migration_balance_transfer`` and ``cash_drawer_auto_transfer``
    source_types (FR5) and entries already linked to this drawer.
    """
    return conn.execute(
        """
        SELECT je.id, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.created_at >= ?
          AND je.created_at <= ?
          AND je.source_type NOT IN (
              'migration_balance_transfer',
              'cash_drawer_auto_transfer'
          )
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
              WHERE cash_drawer_id = ?
          )
        ORDER BY je.created_at
        """,
        (opened_at, closed_at, drawer_id),
    ).fetchall()


def _select_unlinked_1101_entries_open(conn, drawer_id: int, opened_at):
    """Return 1101 journal entries in an open drawer's window not yet linked.

    Open-drawer variant: only an ``opened_at`` lower bound (no ``closed_at``).
    Same source_type exclusions and already-linked exclusion as the closed
    variant.
    """
    return conn.execute(
        """
        SELECT je.id, jl.debit, jl.credit
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.created_at >= ?
          AND je.source_type NOT IN (
              'migration_balance_transfer',
              'cash_drawer_auto_transfer'
          )
          AND je.id NOT IN (
              SELECT journal_entry_id
              FROM cash_drawer_journal_entries
              WHERE cash_drawer_id = ?
          )
        ORDER BY je.created_at
        """,
        (opened_at, drawer_id),
    ).fetchall()


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

    Iterates every drawer in id order, links 1101 journal entries whose
    ``created_at`` falls in the drawer's window (excluding
    ``migration_balance_transfer`` and ``cash_drawer_auto_transfer``), and
    recomputes ``closing_balance`` for closed drawers from the linked net.

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

    return total_linked, closing_updates


def count_unlinked_outside_any_drawer(conn) -> int:
    """Count 1101 entries unlinked and outside every drawer window (orphaned).

    Category (a) in the orphaned-entry breakdown: entries not in
    cash_drawer_journal_entries whose ``created_at`` does not fall in any
    drawer's ``[opened_at, closed_at]`` window. Excludes the
    ``migration_balance_transfer`` / ``cash_drawer_auto_transfer`` source_types
    so the breakdown reflects the entries the backfill step could plausibly
    link.
    """
    return conn.execute(
        """
        SELECT COUNT(*) as cnt
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.source_type NOT IN (
              'migration_balance_transfer',
              'cash_drawer_auto_transfer'
          )
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
        """
    ).fetchone()["cnt"]


def count_unlinked_total(conn) -> int:
    """Count all 1101 entries not present in cash_drawer_journal_entries.

    This is the total unlinked count (categories (a) + (b)); the breakdown's
    "within a drawer window but unlinked" figure is ``total - outside``.
    """
    return conn.execute(
        """
        SELECT COUNT(*) as cnt
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.code = '1101'
          AND je.id NOT IN (
              SELECT journal_entry_id FROM cash_drawer_journal_entries
          )
        """
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