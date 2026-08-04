"""Repair command module: repair_drawer_journal_backfill_cmd (DG-349)."""

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
