"""Repair command module: repair_cancelled_orders_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _cancelled_orders_with_orphaned_entries(conn, order_id=None):
    """Return cancelled orders with non-zero 2100 balance, classified by category.

    Mirrors :func:`_check_deposit_balance_integrity` — calculates
    ``net_2100 = deposits_in - refunds_out - revenue_cleared - shipping_cleared``
    and returns only cancelled orders where ``abs(net_2100) > MISMATCH_TOLERANCE``.

    Each row is annotated with:
    - ``has_cash_issue``: ``deposits_in - refunds_out != 0`` (payment_transaction entries)
    - ``has_non_cash_issue``: ``revenue_cleared + shipping_cleared != 0`` (revenue/COGS/shipping)
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE
    sql = """
        SELECT o.id, o.order_ref,
               COALESCE(pt.dep_credit, 0) AS deposits_in,
               COALESCE(pt.ref_debit, 0) AS refunds_out,
               COALESCE(ord.rev_debit, 0) AS revenue_cleared,
               COALESCE(ship.ship_debit, 0) AS shipping_cleared,
               (COALESCE(pt.dep_credit, 0) - COALESCE(pt.ref_debit, 0)
                - COALESCE(ord.rev_debit, 0) - COALESCE(ship.ship_debit, 0)
               ) AS net_2100
        FROM orders o
        LEFT JOIN (
            SELECT pt2.order_id,
                   SUM(CASE WHEN jl2.credit > 0 THEN jl2.credit ELSE 0 END) AS dep_credit,
                   SUM(CASE WHEN jl2.debit > 0 THEN jl2.debit ELSE 0 END) AS ref_debit
            FROM payment_transactions pt2
            JOIN journal_entries je2
              ON je2.source_type = 'payment_transaction' AND je2.source_id = pt2.id
            JOIN journal_lines jl2 ON jl2.journal_entry_id = je2.id
            JOIN accounts a2 ON a2.id = jl2.account_id AND a2.code = ?
            WHERE (pt2.invalidated_at IS NULL OR pt2.invalidated_at = '')
            GROUP BY pt2.order_id
        ) pt ON pt.order_id = o.id
        LEFT JOIN (
            SELECT je3.source_id AS order_id,
                   SUM(CASE WHEN jl3.debit > 0 THEN jl3.debit ELSE 0 END) AS rev_debit
            FROM journal_entries je3
            JOIN journal_lines jl3 ON jl3.journal_entry_id = je3.id
            JOIN accounts a3 ON a3.id = jl3.account_id AND a3.code = ?
            WHERE je3.source_type = 'order'
              AND je3.description NOT LIKE 'Reversal:%'
            GROUP BY je3.source_id
        ) ord ON ord.order_id = o.id
        LEFT JOIN (
            SELECT je4.source_id AS order_id,
                   SUM(CASE WHEN jl4.debit > 0 THEN jl4.debit ELSE 0 END) AS ship_debit
            FROM journal_entries je4
            JOIN journal_lines jl4 ON jl4.journal_entry_id = je4.id
            JOIN accounts a4 ON a4.id = jl4.account_id AND a4.code = ?
            WHERE je4.source_type = 'order_shipping_hold'
            GROUP BY je4.source_id
        ) ship ON ship.order_id = o.id
        WHERE o.status = 'cancelled'
    """
    params = [deposits_code, deposits_code, deposits_code]
    if order_id is not None:
        sql += " AND o.id = ?"
        params.append(order_id)
    sql += " ORDER BY o.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        net = float(r["net_2100"])
        if abs(net) <= MISMATCH_TOLERANCE:
            continue
        deposits_in = float(r["deposits_in"])
        refunds_out = float(r["refunds_out"])
        revenue_cleared = float(r["revenue_cleared"])
        shipping_cleared = float(r["shipping_cleared"])
        has_cash = abs(deposits_in - refunds_out) > MISMATCH_TOLERANCE
        has_non_cash = abs(revenue_cleared + shipping_cleared) > MISMATCH_TOLERANCE
        r_dict = dict(r)
        r_dict["has_cash_issue"] = has_cash
        r_dict["has_non_cash_issue"] = has_non_cash
        result.append(r_dict)
    return result

def _process_cancelled_order(conn, order_id, order_ref, *, dry_run, has_non_cash_issue):
    """Auto-fix non-cash (revenue/COGS/shipping) entries for one cancelled order.

    Cash entries (payment_transaction deposits) are intentionally skipped —
    they represent real money that requires a human decision (refund vs.
    manual invalidation).
    """
    if dry_run:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "action": "will-repair",
        }
    if not has_non_cash_issue:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "action": "cash-only",
        }

    sync_result = run_journal_sync(
        _sync_cancelled_order_journal,
        conn,
        order_id,
        log_label=f"cancel-journal-{order_id}",
    )
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "action": "repaired" if sync_result == "ok" else "repaired-with-errors",
    }

def _print_cancelled_orders_report(results, *, dry_run):
    """Print the cancelled orders repair report, split by category."""
    auto_fixable = [r for r in results if r.get("has_non_cash_issue")]
    cash_only = [r for r in results if r.get("has_cash_issue") and not r.get("has_non_cash_issue")]
    mixed = [r for r in results if r.get("has_cash_issue") and r.get("has_non_cash_issue")]

    if auto_fixable or mixed:
        click.echo("Bút toán doanh thu / COGS / ship (tự động sửa)")
        click.echo("=" * 52)
        click.echo(f"{'Mã đơn':<20}{'Hành động':<16}")
        click.echo("-" * 36)
        auto_rows = []
        for cat_results in (mixed, auto_fixable):
            for r in cat_results:
                if r not in auto_rows:
                    auto_rows.append(r)
        for r in auto_rows:
            label = _ACTION_LABELS.get(r["action"], r["action"])
            click.echo(f"{r['order_ref'][:19]:<20}{label:<16}")
        click.echo("-" * 36)
        repaired = sum(1 for r in auto_rows if r["action"] in ("repaired", "repaired-with-errors"))
        will_repair = sum(1 for r in auto_rows if r["action"] == "will-repair")
        if dry_run:
            click.echo(f"Tổng: {len(auto_rows)} đơn  |  sẽ sửa: {will_repair}")
        else:
            click.echo(f"Tổng: {len(auto_rows)} đơn  |  đã sửa: {repaired}")
        click.echo("")

    if cash_only or mixed:
        click.echo("Bút toán thanh toán (cần xem xét — không tự động sửa)")
        click.echo("=" * 56)
        click.echo(f"{'Mã đơn':<20}{'Tiền cọc':>12}{'Hoàn lại':>12}")
        click.echo("-" * 44)
        cash_rows = []
        for cat_results in (mixed, cash_only):
            for r in cat_results:
                if r not in cash_rows:
                    cash_rows.append(r)
        for r in cash_rows:
            dep = float(r.get("deposits_in", 0))
            ref = float(r.get("refunds_out", 0))
            click.echo(f"{r['order_ref'][:19]:<20}{dep:>12,.0f}{ref:>12,.0f}")
        click.echo("-" * 44)
        total_dep = sum(float(r.get("deposits_in", 0)) for r in cash_rows)
        total_ref = sum(float(r.get("refunds_out", 0)) for r in cash_rows)
        click.echo(f"Tổng: {len(cash_rows)} đơn  |  cọc: {total_dep:,.0f}  |  hoàn: {total_ref:,.0f}")
        click.echo("")
        click.echo("Các đơn này cần hoàn tiền hoặc huỷ giao dịch thủ công trước.")
        click.echo("Sau đó chạy lại lệnh này để làm sạch bút toán còn lại.")

@click.command("repair-cancelled-orders")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng đã huỷ cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn đã huỷ có bút toán mồ côi.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_cancelled_orders_cmd(order_id, repair_all, dry_run):
    """Xoá/hoàn nhập bút toán doanh thu của đơn hàng đã huỷ.

    Tìm đơn hàng ở trạng thái ``cancelled`` có bút toán mồ côi và tự động
    đảo ngược (locked) hoặc xoá (unlocked) bút toán doanh thu / COGS /
    ship (source_type='order', 'order_cogs', 'order_shipping_release').

    Bút toán thanh toán (payment_transaction) bị bỏ qua — đây là tiền
    thật cần người dùng quyết định (hoàn tiền hoặc huỷ giao dịch thủ công).
    Sau khi xử lý các giao dịch tiền mặt, chạy lại lệnh này để làm sạch
    bút toán còn lại.
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_all:
                orders = _cancelled_orders_with_orphaned_entries(conn)
            else:
                orders = _cancelled_orders_with_orphaned_entries(conn, order_id=order_id)

            results = []
            for o in orders:
                r = _process_cancelled_order(
                    conn,
                    int(o["id"]),
                    o["order_ref"],
                    dry_run=dry_run,
                    has_non_cash_issue=o.get("has_non_cash_issue", False),
                )
                r["deposits_in"] = o.get("deposits_in", 0)
                r["refunds_out"] = o.get("refunds_out", 0)
                r["has_cash_issue"] = o.get("has_cash_issue", False)
                r["has_non_cash_issue"] = o.get("has_non_cash_issue", False)
                results.append(r)
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair cancelled-orders CLI error")
        click.echo(
            "Lỗi khi sửa bút toán đơn đã huỷ. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng đã huỷ nào có bút toán mồ côi)")
        return

    _print_cancelled_orders_report(results, dry_run=dry_run)

