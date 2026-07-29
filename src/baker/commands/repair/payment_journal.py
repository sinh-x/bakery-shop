"""Repair command module: repair_payment_journal_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _payment_transactions_needing_backfill(conn, order_id=None):
    """Payment transactions without journal entries (non-invalidated).

    Returns rows from payment_transactions that have no matching journal entry
    with source_type = 'payment_transaction'. Invalidated transactions are
    excluded (their journal entry is intentionally reversed/removed).
    """
    sql = """
        SELECT pt.id, pt.amount, pt.type, pt.method, pt.order_id
        FROM payment_transactions pt
        WHERE (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'payment_transaction' AND je.source_id = pt.id
          )
    """
    params = []
    if order_id is not None:
        sql += " AND pt.order_id = ?"
        params.append(order_id)
    sql += " ORDER BY pt.id ASC"
    return conn.execute(sql, params).fetchall()

@click.command("repair-payment-journal")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần bổ sung bút toán thanh toán.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Bổ sung bút toán cho tất cả giao dịch thanh toán còn thiếu.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_payment_journal_cmd(order_id, repair_all, dry_run):
    """Bổ sung bút toán nhật ký cho các giao dịch thanh toán còn thiếu.

    Tìm tất cả payment_transactions chưa có bút toán nhật ký tương ứng
    (source_type = 'payment_transaction') và gọi ``_sync_payment_journal``
    để tạo bút toán. Lệnh idempotent: chạy lần hai sẽ không tìm thấy giao
    dịch nào cần bổ sung.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            txns = _payment_transactions_needing_backfill(
                conn, order_id=order_id
            )

            results = []
            for t in txns:
                txn_id = int(t["id"])
                amount = float(t["amount"] or 0)
                ptype = t["type"]
                method = t["method"] or "cash"
                txn_order_id = int(t["order_id"]) if t["order_id"] is not None else None
                order_ref = _order_ref(conn, txn_order_id) if txn_order_id else "-"

                if dry_run:
                    results.append({
                        "txn_id": txn_id,
                        "amount": amount,
                        "type": ptype,
                        "order_ref": order_ref,
                        "action": "will-backfill",
                    })
                else:
                    _sync_payment_journal(
                        conn, txn_id, amount, ptype, method,
                        order_id=txn_order_id,
                    )
                    results.append({
                        "txn_id": txn_id,
                        "amount": amount,
                        "type": ptype,
                        "order_ref": order_ref,
                        "action": "backfilled",
                    })

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair payment-journal CLI error")
        click.echo(
            "Lỗi khi bổ sung bút toán thanh toán. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có giao dịch thanh toán nào cần bổ sung bút toán)")
        return

    click.echo("Bổ sung bút toán nhật ký thanh toán")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã GD':<10}{'Số tiền':>16}{'Loại':<14}{'Đơn hàng':<12}{'Hành động':<16}"
    )
    click.echo("-" * 68)
    for r in results:
        order_ref = r.get("order_ref", "-")
        click.echo(
            f"#{r['txn_id']:<9}"
            f"{_vn_amount(r['amount']):>16}"
            f"{r['type']:<14}"
            f"{order_ref[:11]:<12}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 68)

    backfilled = sum(1 for r in results if r["action"] == "backfilled")
    will_backfill = sum(1 for r in results if r["action"] == "will-backfill")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_backfill}")
    else:
        parts.append(f"đã sửa: {backfilled}")
    click.echo(f"Tổng: {len(results)} giao dịch  |  " + ", ".join(parts))

