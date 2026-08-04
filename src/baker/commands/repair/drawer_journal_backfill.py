"""Repair command module: repair_drawer_journal_backfill_cmd (DG-349).

Orphaned Entry Gap (Phase 4.2 documentation)
============================================
Journal entries created BETWEEN auto-close of one drawer and the next
drawer's open() have drawer_id=None and cannot be linked by the
time-window matching logic below. The time-window matcher uses
opened_at <= created_at <= closed_at; an entry whose created_at falls
in the gap between closed_at of the previous drawer and opened_at of
the next drawer matches no drawer.

Two categories of unlinked entries exist:
  (a) "outside any drawer window" — created_at falls before the first
      drawer opened_at, after the last drawer closed_at, or between two
      drawer periods (the auto-close → next-open gap). These are the
      orphaned entries. They are correctly left unlinked; the repair
      command cannot retroactively assign them without a business
      decision on which drawer should absorb them.
  (b) "within a drawer window but unlinked" — created_at falls inside
      a drawer's [opened_at, closed_at] window but the entry is not in
      cash_drawer_journal_entries. This is the set the backfill step
      links; after a successful repair, category (b) should be empty.

The unlinked count reported in the summary below includes BOTH
categories. The repair command does not silently drop orphaned entries;
they remain visible in the unlinked count for manual review. A separate
follow-up ticket may decide whether to retroactively assign orphaned
entries to a drawer or to treat them as pre-drawer activity.

See AC6 (drawer-accounting-audit requirements doc) for the orphaned
entry acceptance criterion.
"""

from ._common import *  # noqa: F401,F403


@click.command("repair-drawer-journal-backfill")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_drawer_journal_backfill_cmd(dry_run):
    """Backfill cash_drawer_journal_entries và sửa closing_balance (DG-349).

    DG-347 Phase 1 (v95) tạo bảng cash_drawer_journal_entries nhưng chưa
    backfill dữ liệu — 0 dòng. Tất cả 108 bút toán 1101 đều chưa được liên
    kết với drawer, khiến expected_balance() trả về 0.

    Lệnh này:
    1. Liên kết các bút toán 1101 với drawer dựa trên created_at (không dùng
       transaction_date để tránh các bút toán backdate bị gán sai drawer).
    2. Tính lại closing_balance cho các drawer đã đóng từ các dòng đã liên kết.
    3. Các bút toán backdate (tạo sau khi tất cả drawer đã đóng) được giữ
       nguyên không liên kết — đúng vì chúng thuộc về giai đoạn trước drawer.

    Idempotent: INSERT OR IGNORE đảm bảo không trùng lặp.

    Orphaned entries: bút toán tạo giữa auto-close và lần mở tiếp theo
    có drawer_id=None và không khớp time-window nào — xem module docstring
    để biết chi tiết. Chúng vẫn được đếm trong unlinked count.
    """
    try:
        with get_db() as conn:
            drawers = conn.execute(
                "SELECT * FROM cash_drawer ORDER BY id"
            ).fetchall()

            if not drawers:
                click.echo("Không có cash drawer nào trong CSDL.")
                return

            total_linked = 0
            total_unlinked = 0
            closing_updates = []

            for drawer in drawers:
                drawer_id = drawer["id"]
                opened = drawer["opened_at"]
                closed = drawer["closed_at"]
                status = drawer["status"]

                # Find 1101 entries created during this drawer's open period
                if closed:
                    entries = conn.execute(
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
                        (opened, closed, drawer_id),
                    ).fetchall()
                else:
                    entries = conn.execute(
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
                        (opened, drawer_id),
                    ).fetchall()

                if not entries:
                    continue

                net = sum(r["debit"] - r["credit"] for r in entries)

                click.echo(
                    f"Drawer #{drawer_id} ({status}): "
                    f"{opened} → {closed or 'đang mở'}"
                )
                click.echo(f"  {len(entries)} bút toán 1101 cần liên kết")
                click.echo(f"  Tổng net: {net:+,.0f}")

                if not dry_run:
                    for entry in entries:
                        conn.execute(
                            "INSERT OR IGNORE INTO cash_drawer_journal_entries "
                            "(cash_drawer_id, journal_entry_id) VALUES (?, ?)",
                            (drawer_id, entry["id"]),
                        )
                    total_linked += len(entries)

                    if status == "closed":
                        new_closing = drawer["opening_balance"] + net
                        old_closing = drawer["closing_balance"]
                        if new_closing != old_closing:
                            conn.execute(
                                "UPDATE cash_drawer SET closing_balance = ? "
                                "WHERE id = ?",
                                (new_closing, drawer_id),
                            )
                            closing_updates.append({
                                "drawer_id": drawer_id,
                                "old": old_closing,
                                "new": new_closing,
                            })
                            click.echo(
                                f"  closing_balance: {old_closing:,.0f} → "
                                f"{new_closing:,.0f}"
                            )
                else:
                    total_linked += len(entries)
                    if status == "closed":
                        new_closing = drawer["opening_balance"] + net
                        old_closing = drawer["closing_balance"]
                        if new_closing != old_closing:
                            closing_updates.append({
                                "drawer_id": drawer_id,
                                "old": old_closing,
                                "new": new_closing,
                            })
                            click.echo(
                                f"  [DRY RUN] closing_balance: "
                                f"{old_closing:,.0f} → {new_closing:,.0f}"
                            )

                click.echo()

            # Unlinked count broken down by category:
            #   (a) outside any drawer window — orphaned entries (gap
            #       between auto-close and next open, or pre-drawer /
            #       post-last-drawer activity). These cannot be linked
            #       by time-window matching and are left for manual
            #       review.
            #   (b) within a drawer window but not yet linked — these
            #       are the entries the backfill step above should have
            #       linked; after a successful repair this category is
            #       expected to be empty.
            unlinked_outside = conn.execute(
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

            # Count remaining unlinked entries
            unlinked = conn.execute(
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

            unlinked_within = unlinked - unlinked_outside

            if dry_run:
                click.echo(
                    f"[DRY RUN] Sẽ liên kết {total_linked} bút toán, "
                    f"{unlinked} bút toán sẽ không liên kết "
                    f"(ngoài thời gian mở drawer)."
                )
                if closing_updates:
                    click.echo(
                        f"[DRY RUN] Sẽ cập nhật closing_balance cho "
                        f"{len(closing_updates)} drawer."
                    )
            else:
                conn.commit()
                click.echo(
                    f"Đã liên kết {total_linked} bút toán. "
                    f"{unlinked} bút toán không liên kết "
                    f"(ngoài thời gian mở drawer)."
                )
                if closing_updates:
                    click.echo(
                        f"Đã cập nhật closing_balance cho "
                        f"{len(closing_updates)} drawer:"
                    )
                    for u in closing_updates:
                        click.echo(
                            f"  Drawer #{u['drawer_id']}: "
                            f"{u['old']:,.0f} → {u['new']:,.0f}"
                        )

            # Breakdown of unlinked entries by category (Phase 4.2):
            #   (a) outside any drawer window — orphaned entries (gap
            #       between auto-close and next open, pre-drawer, or
            #       post-last-drawer). Cannot be linked by time-window
            #       matching; left for manual review.
            #   (b) within a drawer window but not yet linked — should
            #       be empty after a successful repair.
            click.echo(
                f"  Trong đó: {unlinked_outside} ngoài mọi drawer window "
                f"(orphaned — không gán được), "
                f"{unlinked_within} trong drawer window nhưng chưa liên kết."
            )

    except SystemExit:
        raise
    except Exception:
        logger.exception("Repair drawer journal backfill CLI error")
        click.echo(
            "Lỗi khi backfill cash_drawer_journal_entries. "
            "Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)
