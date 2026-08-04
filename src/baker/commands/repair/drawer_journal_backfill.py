"""Repair command module: repair_drawer_journal_backfill_cmd (DG-349).

Thin wrapper around the shared backfill helpers in ``_backfill`` (DG-351
Phase 4.4). The backfill step, closing_balance recompute, and unlinked-entry
breakdown are shared with ``repair-drawer-accounting``; this command omits the
JE#5975 correction (Step 1) and only runs the backfill + summary.

Orphaned Entry Gap (Phase 4.2 documentation)
===========================================
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
from . import _backfill


@click.command("repair-drawer-journal-backfill")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_drawer_journal_backfill_cmd(dry_run):
    """Backfill cash_drawer_journal_entries và sửa closing_balance (DG-349).

    DG-347 Phase 1 (v95) tạo bảng cash_drawer_journal_entries nhưng chưa
    backfill dữ liệu — 0 dòng. Tất cả 108 bút toán 1101 đều chưa được liên
    kết với drawer, khiến expected_balance() trả về 0.

    Lệnh này:
    1. Liên kết các bút toán 1101 với drawer dựa trên ``created_at`` — xem
       ``_backfill`` cho chi tiết về time-window matching.
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
            total_linked, closing_updates = _backfill.run_drawer_backfill(
                conn, dry_run=dry_run
            )
            outside, within, unlinked = _backfill.unlinked_breakdown(conn)

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

            _backfill.print_unlinked_breakdown(outside, within)

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