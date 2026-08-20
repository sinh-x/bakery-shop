"""Repair command module: check_revenue_gaps_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


@click.command("check-revenue-gaps")
def check_revenue_gaps_cmd():
    """Kiểm tra đơn hàng đã giao/hoàn thành thiếu bút toán doanh thu (chỉ đọc)."""
    try:
        with get_db() as conn:
            rows = conn.execute(
                f"""
                SELECT o.id, o.order_ref, o.due_date, o.status, o.total_price
                FROM orders o
                WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
                  AND NOT EXISTS (
                      SELECT 1 FROM journal_entries je
                      WHERE je.source_type = 'order' AND je.source_id = o.id
                  )
                ORDER BY o.id ASC
                """,  # nosec B608
                list(DELIVERED_STATUSES),
            ).fetchall()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Check revenue gaps CLI error")
        click.echo(
            "Lỗi khi kiểm tra khoảng trống doanh thu. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not rows:
        click.echo("(không có đơn hàng nào thiếu bút toán doanh thu)")
        return

    click.echo("Kiểm tra khoảng trống doanh thu đơn hàng")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Ngày giao':>12}{'Tổng tiền':>14}{'Trạng thái':<14}"
    )
    click.echo("-" * 60)
    for r in rows:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{r['due_date'] or '':>12}"
            f"{_vn_amount(r['total_price']):>14}"
            f"{r['status']:<14}"
        )
    click.echo("-" * 60)
    click.echo(f"Tổng: {len(rows)} đơn thiếu bút toán doanh thu")

