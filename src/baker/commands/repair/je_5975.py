"""Repair command module: repair_je_5975_cmd (DG-348)."""

from ._common import *  # noqa: F401,F403

TARGET_AMOUNT = 330501500
JE_ID = 5975


@click.command("repair-je-5975")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_je_5975_cmd(dry_run):
    """Sửa bút toán chuyển tiền thừa lần mở quầy đầu tiên (JE#5975).

    DG-348 — one-time repair: 62 bút toán bị backdate (tạo 2026-08-03 23:57
    với transaction_date từ tháng 6-7/2026) không được tính trong lần
    auto-transfer đầu tiên. Lệnh này cập nhật số tiền chuyển từ 313,405,500
    thành 330,501,500 để khớp với số dư thực tế trước khi mở quầy, đảm bảo
    opening balance của drawer #1 là 1,172,000.

    Idempotent: nếu số tiền đã đúng thì bỏ qua.
    """
    try:
        with get_db() as conn:
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
                    f"\nBút toán #{JE_ID} đã có số tiền đúng "
                    f"({TARGET_AMOUNT:,.0f}). Không cần sửa."
                )
                return

            click.echo(f"  Số tiền cần sửa:   {TARGET_AMOUNT:,.0f}")
            click.echo(f"  Chênh lệch:        {TARGET_AMOUNT - current_amount:+,.0f}")

            if dry_run:
                click.echo(
                    f"\n[DRY RUN] Sẽ cập nhật bút toán #{JE_ID} "
                    f"từ {current_amount:,.0f} thành {TARGET_AMOUNT:,.0f}."
                )
                return

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
                "UPDATE journal_entries SET description = ? WHERE id = ?",
                (
                    f"Chuyển tiền thừa từ quầy sang tiền mặt chủ sở hữu: "
                    f"{TARGET_AMOUNT} (DG-348: corrected for backdated entries)",
                    JE_ID,
                ),
            )
            conn.commit()

            click.echo(
                f"\nĐã sửa bút toán #{JE_ID}: "
                f"{current_amount:,.0f} → {TARGET_AMOUNT:,.0f}."
            )

            new_balance = conn.execute(
                "SELECT COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0) "
                "FROM journal_lines jl "
                "JOIN accounts a ON a.id = jl.account_id "
                "WHERE a.code = '1101'"
            ).fetchone()[0]
            click.echo(f"Số dư 1101 sau khi sửa: {new_balance:,.0f}")

    except SystemExit:
        raise
    except Exception:
        logger.exception("Repair JE#5975 CLI error")
        click.echo(
            "Lỗi khi sửa bút toán #5975. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)
