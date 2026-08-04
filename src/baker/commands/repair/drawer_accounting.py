"""Repair command module: repair_drawer_accounting_cmd (DG-348 + DG-349).

The backfill step (Step 2) and the unlinked-entry breakdown are shared with
``repair-drawer-journal-backfill`` via ``_backfill`` (DG-351 Phase 4.4). This
module keeps only the JE#5975 correction (Step 1) and the final summary, which
are specific to the unified ``repair-drawer-accounting`` command.

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

TARGET_AMOUNT = 330501500
JE_ID = 5975


@click.command("repair-drawer-accounting")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_drawer_accounting_cmd(dry_run):
    """Sửa kế toán cash drawer sau DG-347 (JE#5975 + backfill + closing_balance).

    Thực hiện 3 bước theo thứ tự:

    1. Sửa bút toán JE#5975 (auto-transfer lần mở quầy đầu tiên):
       cập nhật số tiền chuyển từ 313,405,500 thành 330,501,500 để tính
       cả 62 bút toán backdate (tạo 2026-08-03 23:57 với
       ``transaction_date`` tháng 6-7/2026) không được tính trong lần
       transfer đầu tiên.

    2. Backfill cash_drawer_journal_entries: liên kết các bút toán 1101
       với drawer dựa trên ``created_at`` — xem ``_backfill`` cho chi tiết
       về time-window matching.

    3. Tính lại closing_balance cho các drawer đã đóng từ các dòng đã
       liên kết.

    Idempotent: chạy lại không gây thay đổi nếu dữ liệu đã đúng.

    Orphaned entries: bút toán tạo giữa auto-close và lần mở tiếp theo
    có drawer_id=None và không khớp time-window nào — xem module docstring
    để biết chi tiết. Chúng vẫn được đếm trong unlinked count.
    """
    try:
        with get_db() as conn:
            # ── Step 1: Fix JE#5975 ──
            click.echo("=" * 60)
            click.echo("Bước 1: Sửa bút toán JE#5975")
            click.echo("=" * 60)

            entry = conn.execute(
                "SELECT * FROM journal_entries WHERE id = ?", (JE_ID,)
            ).fetchone()
            if entry is None:
                click.echo(f"Không tìm thấy bút toán #{JE_ID}.", err=True)
                raise SystemExit(1)

            lines = conn.execute(
                "SELECT jl.*, a.code, a.name FROM journal_lines jl "
                "JOIN accounts a ON a.id = jl.account_id "
                "WHERE jl.journal_entry_id = ? ORDER BY jl.id",
                (JE_ID,),
            ).fetchall()

            current_amount = int(lines[0]["debit"] or lines[0]["credit"])

            click.echo(f"Bút toán #{JE_ID}: {entry['description']}")
            click.echo(f"  source_type: {entry['source_type']}")
            click.echo(f"  transaction_date: {entry['transaction_date']}")
            click.echo(f"  created_at: {entry['created_at']}")
            click.echo("  Dòng:")
            for line in lines:
                click.echo(
                    f"    {line['code']} ({line['name']}): "
                    f"Nợ {line['debit']:,.0f} / Có {line['credit']:,.0f}"
                )
            click.echo(f"  Số tiền hiện tại: {current_amount:,.0f}")

            if current_amount == TARGET_AMOUNT:
                click.echo(
                    f"  Bút toán #{JE_ID} đã có số tiền đúng "
                    f"({TARGET_AMOUNT:,.0f}). Bỏ qua."
                )
            else:
                click.echo(f"  Số tiền cần sửa:   {TARGET_AMOUNT:,.0f}")
                click.echo(
                    f"  Chênh lệch:        "
                    f"{TARGET_AMOUNT - current_amount:+,.0f}"
                )

                if dry_run:
                    click.echo(
                        f"  [DRY RUN] Sẽ cập nhật từ "
                        f"{current_amount:,.0f} thành {TARGET_AMOUNT:,.0f}."
                    )
                else:
                    conn.execute(
                        "UPDATE journal_lines SET debit = ?, credit = 0 "
                        "WHERE journal_entry_id = ? AND debit > 0",
                        (TARGET_AMOUNT, JE_ID),
                    )
                    conn.execute(
                        "UPDATE journal_lines SET credit = ?, debit = 0 "
                        "WHERE journal_entry_id = ? AND credit > 0",
                        (TARGET_AMOUNT, JE_ID),
                    )
                    conn.execute(
                        "UPDATE journal_entries SET description = ? "
                        "WHERE id = ?",
                        (
                            f"Chuyển tiền thừa từ quầy sang tiền mặt "
                            f"chủ sở hữu: {TARGET_AMOUNT} "
                            f"(DG-348: corrected for backdated entries)",
                            JE_ID,
                        ),
                    )
                    click.echo(
                        f"  Đã sửa: {current_amount:,.0f} → "
                        f"{TARGET_AMOUNT:,.0f}."
                    )

            # ── Step 2: Backfill cash_drawer_journal_entries ──
            click.echo()
            click.echo("=" * 60)
            click.echo("Bước 2: Backfill cash_drawer_journal_entries")
            click.echo("=" * 60)

            total_linked, closing_updates = _backfill.run_drawer_backfill(
                conn, dry_run=dry_run
            )
            outside, within, unlinked = _backfill.unlinked_breakdown(conn)

            # ── Step 3: Summary ──
            click.echo("=" * 60)
            click.echo("Bước 3: Tổng kết")
            click.echo("=" * 60)

            if dry_run:
                click.echo(
                    f"[DRY RUN] Sẽ liên kết {total_linked} bút toán, "
                    f"{unlinked} bút toán không liên kết "
                    f"(ngoài thời gian mở drawer)."
                )
                if closing_updates:
                    click.echo(
                        f"[DRY RUN] Sẽ cập nhật closing_balance cho "
                        f"{len(closing_updates)} drawer:"
                    )
                    for u in closing_updates:
                        click.echo(
                            f"  Drawer #{u['drawer_id']}: "
                            f"{u['old']:,.0f} → {u['new']:,.0f}"
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

                new_balance = conn.execute(
                    "SELECT COALESCE(SUM(jl.debit), 0) - "
                    "COALESCE(SUM(jl.credit), 0) "
                    "FROM journal_lines jl "
                    "JOIN accounts a ON a.id = jl.account_id "
                    "WHERE a.code = '1101'"
                ).fetchone()[0]
                click.echo(f"Số dư 1101 sau khi sửa: {new_balance:,.0f}")

            _backfill.print_unlinked_breakdown(outside, within)

    except SystemExit:
        raise
    except Exception:
        logger.exception("Repair drawer accounting CLI error")
        click.echo(
            "Lỗi khi sửa kế toán cash drawer. "
            "Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)