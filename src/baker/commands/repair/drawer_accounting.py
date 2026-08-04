"""Repair command module: repair_drawer_accounting_cmd (DG-348 + DG-349)."""

from ._common import *  # noqa: F401,F403

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
       cả 62 bút toán backdate (tạo 2026-08-03 23:57 với transaction_date
       tháng 6-7/2026) không được tính trong lần transfer đầu tiên.

    2. Backfill cash_drawer_journal_entries: liên kết các bút toán 1101
       với drawer dựa trên created_at (không dùng transaction_date để
       tránh các bút toán backdate bị gán sai drawer).

    3. Tính lại closing_balance cho các drawer đã đóng từ các dòng đã
       liên kết.

    Idempotent: chạy lại không gây thay đổi nếu dữ liệu đã đúng.
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

            drawers = conn.execute(
                "SELECT * FROM cash_drawer ORDER BY id"
            ).fetchall()

            if not drawers:
                click.echo("Không có cash drawer nào trong CSDL.")
                return

            total_linked = 0
            closing_updates = []

            for drawer in drawers:
                drawer_id = drawer["id"]
                opened = drawer["opened_at"]
                closed = drawer["closed_at"]
                status = drawer["status"]

                if closed:
                    entries = conn.execute(
                        """
                        SELECT je.id, jl.debit, jl.credit
                        FROM journal_lines jl
                        JOIN journal_entries je
                             ON je.id = jl.journal_entry_id
                        JOIN accounts a ON a.id = jl.account_id
                        WHERE a.code = '1101'
                          AND je.transaction_date >= ?
                          AND je.transaction_date <= ?
                          AND je.source_type NOT IN (
                              'migration_balance_transfer',
                              'cash_drawer_auto_transfer'
                          )
                          AND je.id NOT IN (
                              SELECT journal_entry_id
                              FROM cash_drawer_journal_entries
                              WHERE cash_drawer_id = ?
                          )
                        ORDER BY je.transaction_date
                        """,
                        (opened, closed, drawer_id),
                    ).fetchall()
                else:
                    entries = conn.execute(
                        """
                        SELECT je.id, jl.debit, jl.credit
                        FROM journal_lines jl
                        JOIN journal_entries je
                             ON je.id = jl.journal_entry_id
                        JOIN accounts a ON a.id = jl.account_id
                        WHERE a.code = '1101'
                          AND je.transaction_date >= ?
                          AND je.source_type NOT IN (
                              'migration_balance_transfer',
                              'cash_drawer_auto_transfer'
                          )
                          AND je.id NOT IN (
                              SELECT journal_entry_id
                              FROM cash_drawer_journal_entries
                              WHERE cash_drawer_id = ?
                          )
                        ORDER BY je.transaction_date
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
                    for e in entries:
                        conn.execute(
                            "INSERT OR IGNORE INTO "
                            "cash_drawer_journal_entries "
                            "(cash_drawer_id, journal_entry_id) "
                            "VALUES (?, ?)",
                            (drawer_id, e["id"]),
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

            unlinked = conn.execute(
                """
                SELECT COUNT(*) as cnt
                FROM journal_lines jl
                JOIN journal_entries je ON je.id = jl.journal_entry_id
                JOIN accounts a ON a.id = jl.account_id
                WHERE a.code = '1101'
                  AND je.id NOT IN (
                      SELECT journal_entry_id
                      FROM cash_drawer_journal_entries
                  )
                """
            ).fetchone()["cnt"]

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
