"""Repair command module: repair_tien_rut_gap_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _tien_rut_orders_needing_backfill(conn):
    """Return order ids with a deposit-revenue gap caused by pre-fix tien_rut.

    An order is affected when it has at least one valid ``tien_rut`` payment
    transaction whose journal entry does NOT credit account 2400 (Tien Rut
    Held). Before the DG-198 reversal, ``tien_rut`` was treated as an outflow
    and debited 2100 (Customer Deposits) directly, overdrawing 2100 and
    skipping revenue recognition. The current correct routing is DR Asset /
    CR 2400 (a deposit inflow).

    The detection is idempotent: once the backfill re-syncs a tien_rut payment
    journal entry to credit 2400, the order drops out of this list, so a
    second run is a no-op (NFR3).
    """
    from baker.models.payment_transaction import _invalidation_filter

    tien_rut_acc_id_row = conn.execute(
        "SELECT id FROM accounts WHERE code = ?", (TIEN_RUT_HELD_CODE,)
    ).fetchone()
    if not tien_rut_acc_id_row:
        return []
    tien_rut_acc_id = int(tien_rut_acc_id_row["id"])
    invalidation = _invalidation_filter(conn)

    # payment_transactions with type='tien_rut' whose journal entry has no 2400
    # credit line. An invalidated tien_rut has no journal entry (it was
    # reversed/deleted), so it is naturally excluded.
    rows = conn.execute(
        f"""
        SELECT DISTINCT pt.order_id
        FROM payment_transactions pt
        JOIN journal_entries je
          ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
        WHERE pt.type = 'tien_rut'
          {invalidation}
          AND NOT EXISTS (
              SELECT 1 FROM journal_lines jl
              WHERE jl.journal_entry_id = je.id
                AND jl.account_id = ?
                AND jl.credit > 0
          )
        ORDER BY pt.order_id ASC
        """,
        (tien_rut_acc_id,),
    ).fetchall()
    return [int(r["order_id"]) for r in rows]

def _process_tien_rut_gap_order(conn, order_id: int, *, dry_run: bool) -> dict:
    """Backfill one order's tien_rut deposit-revenue gap (FR4).

    Steps for the live run:
      1. Re-sync each ``tien_rut`` payment journal entry so it credits 2400
         (DR Asset / CR 2400 — the DG-198 reversal inflow routing) instead of
         debiting 2100. Idempotent: re-syncing an entry already on 2400 is a
         no-op.
      2. Reconcile the order's journal entries so deposits→revenue (DR 2100 /
         CR 4100) and tien_rut→return (DR 2400 / CR Asset) are created
         separately via ``_reconcile_order_revenue_entry``. Idempotent within
         ``REVENUE_UPDATE_TOLERANCE``.

    Dry-run reports the gap and the planned actions without mutating.
    """
    from baker.models.payment_transaction import _invalidation_filter

    order_ref = _order_ref(conn, order_id)
    invalidation = _invalidation_filter(conn)
    tien_rut_total = float(
        conn.execute(
            f"""
            SELECT COALESCE(SUM(amount), 0) AS total
            FROM payment_transactions
            WHERE order_id = ? AND type = 'tien_rut'
              {invalidation}
            """,
            (order_id,),
        ).fetchone()["total"]
    )
    net_deposits = PaymentTransaction.total_paid_net(conn, order_id)

    result = {
        "order_id": order_id,
        "order_ref": order_ref,
        "tien_rut_total": tien_rut_total,
        "net_deposits": net_deposits,
        "action": "will-backfill" if dry_run else "backfilled",
    }
    if dry_run:
        return result

    # (1) Re-sync each tien_rut payment journal entry → route to 2400.
    tien_rut_txns = conn.execute(
        f"""
        SELECT id, amount, method
        FROM payment_transactions
        WHERE order_id = ? AND type = 'tien_rut'
          {invalidation}
        ORDER BY id ASC
        """,
        (order_id,),
    ).fetchall()
    for t in tien_rut_txns:
        _sync_payment_journal(
            conn,
            int(t["id"]),
            float(t["amount"]),
            "tien_rut",
            t["method"] or "cash",
            order_id=order_id,
        )

    # (2) Reconcile the revenue entry so it clears 2400 and balances 2100/4100.
    _reconcile_order_revenue_entry(
        conn, order_id, order_ref, respect_locks=True
    )
    return result

@click.command("repair-tien-rut-gap")
@click.option("--order-id", "order_id", type=int, default=None, help="ID đơn hàng cần sửa.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả đơn có khoảng trống tiền rút.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_tien_rut_gap_cmd(order_id, repair_all, dry_run):
    """Sửa khoảng trống kế toán tiền rút (chuyển tien_rut sang 2400, cân đối lại doanh thu)."""
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            if repair_all:
                order_ids = _tien_rut_orders_needing_backfill(conn)
            else:
                # Single order: only include it if it actually has the gap.
                affected = set(_tien_rut_orders_needing_backfill(conn))
                order_ids = [order_id] if order_id in affected else []

            results = []
            for oid in order_ids:
                results.append(
                    _process_tien_rut_gap_order(conn, oid, dry_run=dry_run)
                )
            if not dry_run:
                conn.commit()
    except Exception as exc:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair tien-rut-gap CLI error")
        click.echo(
            "Lỗi khi sửa khoảng trống tiền rút. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có đơn hàng nào cần sửa khoảng trống tiền rút)")
        return

    click.echo("Sửa khoảng trống kế toán tiền rút")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Tiền rút':>16}{'Cọc ròng':>16}{'Hành động':<16}"
    )
    click.echo("-" * 68)
    for r in results:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{_vn_amount(r['tien_rut_total']):>16}"
            f"{_vn_amount(r['net_deposits']):>16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 68)
    click.echo(f"Tổng: {len(results)} đơn cần sửa khoảng trống tiền rút")

