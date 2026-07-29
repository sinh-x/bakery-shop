"""Repair command module: repair_deposit_balance_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _orders_with_deposit_balance_issue(conn, order_id=None):
    """Return orders flagged by the deposit_balance_integrity check.

    Mirrors :func:`_check_deposit_balance_integrity` — returns rows with
    ``net_2100 != 0`` for terminal/overdue orders. Excludes active orders
    that haven't passed their due date.
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE
    sql = f"""
        SELECT o.id, o.order_ref, o.status, o.due_date,
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
        WHERE COALESCE(pt.dep_credit, 0) > 0
           OR COALESCE(ord.rev_debit, 0) > 0
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
        status = r["status"]
        due_date = r["due_date"]
        if status not in ("delivered", "completed", "cancelled"):
            if not due_date:
                continue
            today = conn.execute(
                "SELECT strftime('%Y-%m-%d', 'now', 'localtime')"
            ).fetchone()[0]
            if due_date >= today:
                continue
        result.append(r)
    return result

def _process_deposit_balance_order(conn, order_id, *, dry_run):
    """Repair one order's deposit balance integrity (FR6).

    - Cancelled orders: reverse the payment transaction journal entries
      (the deposits were taken but never returned).
    - Delivered/completed/overdue orders: reconcile the revenue entry
      via :func:`_reconcile_order_revenue_entry`.

    Returns a result dict with keys: order_id, order_ref, status,
    deposits_in, revenue_cleared, shipping_cleared, net_2100, action.
    """
    deposits_code = CUSTOMER_DEPOSITS_CODE
    row = conn.execute(
        """
        SELECT o.id, o.order_ref, o.status, o.due_date,
               COALESCE((
                   SELECT SUM(jl.credit)
                   FROM payment_transactions pt
                   JOIN journal_entries je ON je.source_type = 'payment_transaction'
                     AND je.source_id = pt.id
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE pt.order_id = o.id
                     AND (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
                     AND jl.credit > 0
               ), 0) AS deposits_in,
               COALESCE((
                   SELECT SUM(jl.debit)
                   FROM journal_entries je
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE je.source_type = 'order' AND je.source_id = o.id
                     AND je.description NOT LIKE 'Reversal:%'
                     AND jl.debit > 0
               ), 0) AS revenue_cleared,
               COALESCE((
                   SELECT SUM(jl.debit)
                   FROM journal_entries je
                   JOIN journal_lines jl ON jl.journal_entry_id = je.id
                   JOIN accounts a ON a.id = jl.account_id AND a.code = ?
                   WHERE je.source_type = 'order_shipping_hold'
                     AND je.source_id = o.id
                     AND jl.debit > 0
               ), 0) AS shipping_cleared
        FROM orders o
        WHERE o.id = ?
        """,
        (deposits_code, deposits_code, deposits_code, order_id),
    ).fetchone()
    if row is None:
        return {
            "order_id": order_id,
            "order_ref": f"#{order_id}",
            "status": "unknown",
            "deposits_in": 0.0,
            "revenue_cleared": 0.0,
            "shipping_cleared": 0.0,
            "net_2100": 0.0,
            "action": "not-applicable",
        }

    order_ref = row["order_ref"]
    status = row["status"]
    deposits_in = float(row["deposits_in"])
    revenue_cleared = float(row["revenue_cleared"])
    shipping_cleared = float(row["shipping_cleared"])
    net_2100 = deposits_in - revenue_cleared - shipping_cleared

    if status == "cancelled":
        if deposits_in <= 0:
            action = "not-applicable"
        elif dry_run:
            action = "will-repair"
        else:
            txn_ids = conn.execute(
                """
                SELECT pt.id
                FROM payment_transactions pt
                JOIN journal_entries je
                  ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
                WHERE pt.order_id = ?
                  AND (pt.invalidated_at IS NULL OR pt.invalidated_at = '')
                """,
                (order_id,),
            ).fetchall()
            for t in txn_ids:
                entry_id_row = conn.execute(
                    "SELECT id FROM journal_entries "
                    "WHERE source_type = 'payment_transaction' AND source_id = ?",
                    (int(t["id"]),),
                ).fetchone()
                if entry_id_row:
                    eid = int(entry_id_row["id"])
                    if _is_locked(conn, eid):
                        _reverse_journal_entry(conn, eid)
                    else:
                        _delete_journal_entry_cascade(conn, eid)
            action = "repaired"
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "status": status,
            "deposits_in": deposits_in,
            "revenue_cleared": revenue_cleared,
            "shipping_cleared": shipping_cleared,
            "net_2100": net_2100,
            "action": action,
        }

    # DG-249 Phase 2 cross-guard: skip orders that already have an
    # AR-style revenue JE (source_type='order' with a debit line on
    # account ``ACCOUNTS_RECEIVABLE_CODE``). Such orders have already
    # been recognised via AR (DR 1500 / CR 4100); reconciling again
    # would create a duplicate deposit-style revenue JE. The guard is
    # evaluated before the dry-run branch so preview and apply agree
    # (both return "skipped" for guarded orders). Detection uses the
    # account-code lookup pattern (FR5) with an O(1)
    # ``SELECT 1 ... LIMIT 1`` query (NFR1).
    ar_exists = conn.execute(
        """
        SELECT 1
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = 'order' AND je.source_id = ?
          AND a.code = ? AND jl.debit > 0
        LIMIT 1
        """,
        (order_id, ACCOUNTS_RECEIVABLE_CODE),
    ).fetchone()
    if ar_exists is not None:
        return {
            "order_id": order_id,
            "order_ref": order_ref,
            "status": status,
            "deposits_in": deposits_in,
            "revenue_cleared": revenue_cleared,
            "shipping_cleared": shipping_cleared,
            "net_2100": net_2100,
            "action": "skipped",
        }
    if dry_run:
        action = "will-repair"
    else:
        _reconcile_order_revenue_entry(conn, order_id, order_ref, respect_locks=True)
        action = "repaired"
    return {
        "order_id": order_id,
        "order_ref": order_ref,
        "status": status,
        "deposits_in": deposits_in,
        "revenue_cleared": revenue_cleared,
        "shipping_cleared": shipping_cleared,
        "net_2100": net_2100,
        "action": action,
    }

def _print_deposit_balance_report(results, *, dry_run):
    """Print the deposit balance repair report table and summary."""
    click.echo("Sửa số dư cọc khách hàng (2100)")
    click.echo("=" * 60)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Trạng thái':<14}{'Cọc vào':>14}{'Đã ghi nhận':>14}"
        f"{'VC giữ':>12}{'Còn lại':>14}{'Hành động':<14}"
    )
    click.echo("-" * 102)
    for r in results:
        action_label = _ACTION_LABELS.get(r["action"], r["action"])
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{r['status']:<14}"
            f"{_vn_amount(r['deposits_in']):>14}"
            f"{_vn_amount(r['revenue_cleared']):>14}"
            f"{_vn_amount(r['shipping_cleared']):>12}"
            f"{_vn_amount(r['net_2100']):>14}"
            f"{action_label:<14}"
        )
    click.echo("-" * 102)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")
    not_applicable = sum(1 for r in results if r["action"] == "not-applicable")
    skipped = sum(1 for r in results if r["action"] == "skipped")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        parts.append(f"đã sửa: {repaired}")
    if not_applicable:
        parts.append(f"không áp dụng: {not_applicable}")
    if skipped:
        parts.append(f"bỏ qua: {skipped}")
    click.echo(f"Tổng: {len(results)} đơn  |  " + ", ".join(parts))

@click.command("repair-deposit-balance")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn có số dư cọc bất thường.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_deposit_balance_cmd(order_id, repair_all, dry_run):
    """Sửa số dư cọc khách hàng (2100) bị lệch.

    Xử lý các vấn đề về tính toàn vẹn số dư cọc:
    - Đơn hàng đã hủy có cọc chưa hoàn trả → xoá/hoàn nhập bút toán cọc
    - Đơn hàng đã giao/hoàn thành có số dư 2100 âm hoặc dương
      bất thường → tạo lại bút toán doanh thu

    Lệnh idempotent: chạy lần hai sẽ không tìm thấy đơn hàng nào cần sửa.
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
                orders = _orders_with_deposit_balance_issue(conn)
            else:
                orders = _orders_with_deposit_balance_issue(conn, order_id=order_id)

            results = []
            for o in orders:
                results.append(
                    _process_deposit_balance_order(
                        conn, int(o["id"]), dry_run=dry_run
                    )
                )
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair deposit-balance CLI error")
        click.echo(
            "Lỗi khi sửa số dư cọc. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần sửa số dư cọc)")
        return

    _print_deposit_balance_report(results, dry_run=dry_run)

