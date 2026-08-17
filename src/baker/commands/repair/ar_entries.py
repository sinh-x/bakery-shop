"""Repair command module: repair_ar_entries_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _orders_needing_ar_entry(conn, order_id=None):
    """Find delivered/completed orders needing AR entries.

    Returns orders with total_price > 0, status in DELIVERED_STATUSES,
    no existing ``source_type='order'`` journal entry, and
    ``deposits_in - tien_rut_total <= 0`` (zero net deposits after
    excluding tien_rut — truly unpaid orders that need AR recognition).

    The generic ``source_type='order'`` JE guard covers deposit-style
    revenue JEs (DG-249 Phase 1 cross-guard) implicitly: any order with
    a deposit-style revenue JE already has a ``source_type='order'`` JE
    and is therefore excluded — no separate deposit-style subquery is
    needed.
    """
    sql = f"""
        SELECT o.id, o.order_ref, o.total_price
        FROM orders o
        WHERE o.status IN ({','.join('?' * len(DELIVERED_STATUSES))})
          AND o.total_price > 0
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'order' AND je.source_id = o.id
          )
    """  # nosec B608
    params = [*DELIVERED_STATUSES]
    if order_id is not None:
        sql += " AND o.id = ?"
        params.append(order_id)
    sql += " ORDER BY o.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        oid = int(r["id"])
        deposits_in = PaymentTransaction.total_paid_excl_outflows(conn, oid)
        tien_rut_total = PaymentTransaction.total_tien_rut(conn, oid)
        if deposits_in - tien_rut_total <= 0:
            result.append(r)

    return result

@click.command("repair-ar-entries")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần bổ sung bút toán công nợ.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Bổ sung bút toán công nợ cho tất cả đơn hàng còn thiếu.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_ar_entries_cmd(order_id, repair_all, dry_run):
    """Bổ sung bút toán công nợ phải thu (AR) cho đơn hàng đã giao không có cọc.

    Tìm các đơn hàng đã giao/hoàn thành với total_price > 0, không có
    bút toán doanh thu (source_type = 'order'), và không có cọc thực tế
    (deposits_in - tien_rut_total <= 0). Tạo bút toán công nợ DR 1500 /
    CR 4100 qua ``_reconcile_order_revenue_entry``. Lệnh idempotent: chạy
    lần hai sẽ không tìm thấy đơn hàng nào cần bổ sung.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            orders = _orders_needing_ar_entry(conn, order_id=order_id)

            results = []
            for o in orders:
                oid = int(o["id"])
                order_ref = o["order_ref"]
                total_price = float(o["total_price"] or 0)

                if dry_run:
                    results.append({
                        "order_id": oid,
                        "order_ref": order_ref,
                        "total_price": total_price,
                        "action": "will-create",
                    })
                else:
                    _reconcile_order_revenue_entry(
                        conn, oid, order_ref, total_price=total_price,
                    )
                    results.append({
                        "order_id": oid,
                        "order_ref": order_ref,
                        "total_price": total_price,
                        "action": "created",
                    })

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair AR entries CLI error")
        click.echo(
            "Lỗi khi bổ sung bút toán công nợ. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần bổ sung bút toán công nợ)")
        return

    click.echo("Bổ sung bút toán công nợ phải thu (AR)")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Tổng tiền':>16}{'Hành động':<16}"
    )
    click.echo("-" * 52)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['total_price']):>16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 52)

    created = sum(1 for r in results if r["action"] == "created")
    will_create = sum(1 for r in results if r["action"] == "will-create")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_create}")
    else:
        parts.append(f"đã sửa: {created}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))

