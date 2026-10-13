"""Repair command: re-sync orders with journal_sync_failure_log entries (DG-380)."""

from ._common import *  # noqa: F401,F403
from baker.services.journal_sync import (
    _sync_completed_order_journal,
    _sync_delivered_order_journal,
)


def _orders_with_fk_failures(conn, order_id=None):
    """Find delivered/completed orders with FK failures in journal_sync_failure_log."""
    sql = f"""
        SELECT DISTINCT o.id, o.order_ref, o.status
        FROM orders o
        JOIN journal_sync_failure_log jsfl
          ON jsfl.source_type = 'order' AND jsfl.source_id = o.id
        WHERE jsfl.error_message LIKE '%FOREIGN KEY%'
          AND o.status IN ({','.join('?' * len(DELIVERED_STATUSES))})
    """  # nosec B608
    params = [*DELIVERED_STATUSES]
    if order_id is not None:
        sql += " AND o.id = ?"
        params.append(order_id)
    sql += " ORDER BY o.id ASC"
    return conn.execute(sql, params).fetchall()


@click.command("repair-journal-sync-fk")
@click.option("--order-id", "order_id", type=int, default=None,
              help="ID đơn hàng cần đồng bộ lại bút toán.")
@click.option("--all", "repair_all", is_flag=True, default=False,
              help="Đồng bộ lại bút toán cho tất cả đơn hàng có lỗi FK trong journal_sync_failure_log.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_journal_sync_fk_cmd(order_id, repair_all, dry_run):
    """Đồng bộ lại bút toán kế toán cho đơn hàng bị lỗi FOREIGN KEY constraint.

    Tìm các đơn hàng đã giao/hoàn thành có lỗi FK trong
    journal_sync_failure_log và gọi lại _sync_delivered_order_journal
    hoặc _sync_completed_order_journal tuỳ theo trạng thái.

    Lệnh idempotent: chạy lần hai sẽ không tìm thấy đơn hàng nào cần sửa
    (sau khi đã xoá failure log).
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            orders = _orders_with_fk_failures(conn, order_id=order_id)

            results = []
            for o in orders:
                oid = int(o["id"])
                order_ref = o["order_ref"]
                status = o["status"]

                if dry_run:
                    results.append({
                        "order_id": oid,
                        "order_ref": order_ref,
                        "status": status,
                        "action": "will-repair",
                    })
                else:
                    try:
                        if status == "completed":
                            _sync_completed_order_journal(conn, oid, order_ref)
                        else:
                            _sync_delivered_order_journal(conn, oid, order_ref)
                        try:
                            conn.execute(
                                """
                                DELETE FROM journal_sync_failure_log
                                WHERE source_type = 'order'
                                  AND source_id = ?
                                  AND error_message LIKE '%FOREIGN KEY%'
                                """,
                                (oid,),
                            )
                        except Exception:  # noqa: BLE001 — cleanup must not stop repairs
                            logger.warning(
                                "Failed to delete FK failure logs for order %d (%s)",
                                oid,
                                order_ref,
                                exc_info=True,
                            )
                        results.append({
                            "order_id": oid,
                            "order_ref": order_ref,
                            "status": status,
                            "action": "repaired",
                        })
                    except Exception:
                        logger.exception(
                            "Sync failed for order %d (%s)", oid, order_ref
                        )
                        results.append({
                            "order_id": oid,
                            "order_ref": order_ref,
                            "status": status,
                            "action": "failed",
                        })

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair journal-sync-fk CLI error")
        click.echo(
            "Lỗi khi đồng bộ lại bút toán. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần đồng bộ lại)")
        return

    click.echo("Đồng bộ lại bút toán đơn hàng lỗi FK")
    click.echo("=" * 52)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Trạng thái':<16}{'Hành động':<16}"
    )
    click.echo("-" * 52)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{r['status']:<16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 52)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    failed = sum(1 for r in results if r["action"] == "failed")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        if repaired:
            parts.append(f"đã sửa: {repaired}")
        if failed:
            parts.append(f"lỗi: {failed}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))
