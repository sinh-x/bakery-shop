"""Repair command module: repair_unallocated_transfers_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403

_LEGACY_TRANSFER_ASSET_CODE = "1200"

def _transfer_txns_with_legacy_asset_line(conn, order_id=None):
    """Return non-invalidated transfer payment transactions whose journal
    entry asset line still points to the legacy default account (1200).

    Scope (FR5 backfill aspect + NFR3):
      - ``payment_transactions.method == 'transfer'`` (only transfers were
        routed to 1200 by ``PAYMENT_METHOD_TO_ASSET_CODE``; cash/card always
        used 1100 and are NOT in scope).
      - ``payment_source`` empty/NULL — transactions with an explicit
        payment_source (1210/1220) are already on the correct sub-account and
        MUST NOT be touched (NFR3).
      - Journal entry's asset (debit) line references account 1200. After
        Phase 4 re-routes the entry to 1290, this condition is false and the
        row drops out — idempotent.

    Invalidated transactions are excluded (their journal entry is reversed or
    absent). Orders with no journal entry are excluded — they have no asset
    line to reassign (handled separately by ``repair-payment-journal``).
    """
    from baker.models.payment_transaction import _invalidation_filter

    invalidation = _invalidation_filter(conn)
    sql = f"""
        SELECT DISTINCT pt.id AS txn_id, pt.amount, pt.type, pt.order_id,
               je.id AS entry_id
        FROM payment_transactions pt
        JOIN journal_entries je
          ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
        JOIN journal_lines jl
          ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE pt.method = 'transfer'
          AND (pt.payment_source IS NULL OR pt.payment_source = '')
          {invalidation}
          AND a.code = ?
          AND jl.debit > 0
          AND je.description NOT LIKE 'Reversal:%'
    """  # nosec B608
    params = [_LEGACY_TRANSFER_ASSET_CODE]
    if order_id is not None:
        sql += " AND pt.order_id = ?"
        params.append(order_id)
    sql += " ORDER BY pt.id ASC"
    rows = conn.execute(sql, params).fetchall()
    return [
        {
            "txn_id": int(r["txn_id"]),
            "amount": float(r["amount"] or 0),
            "type": r["type"] or "deposit",
            "order_id": int(r["order_id"]) if r["order_id"] is not None else None,
            "entry_id": int(r["entry_id"]),
        }
        for r in rows
    ]

def _process_unallocated_transfer(conn, txn, *, dry_run: bool) -> dict:
    """Re-point one transaction's asset line from 1200 to 1290 (FR5 backfill).

    Re-runs :func:`_sync_payment_journal` for the transaction so the entry is
    rebuilt via :func:`_build_payment_journal_lines` (the single source of
    truth for line construction). Because the persisted ``payment_source`` is
    empty and ``method == 'transfer'``, :func:`_resolve_transaction_asset_code`
    routes the asset side to ``UNALLOCATED_BANK_CODE`` (1290). The credit side
    (2100 / 2200 / 2400 split) is rebuilt identically — no double-entry, no
    duplicate journal entries, the existing entry is updated in place when
    unlocked, or reversed + recreated when locked.

    Idempotent (NFR1): once the asset line is on 1290, the transaction drops
    out of :func:`_transfer_txns_with_legacy_asset_line` so a second run is a
    no-op. Expense journals are never touched (NFR1) — only the
    ``payment_transaction`` source-type entry is re-synced.
    """
    txn_id = txn["txn_id"]
    order_ref = _order_ref(conn, txn["order_id"]) if txn["order_id"] else "-"
    if dry_run:
        return {
            "txn_id": txn_id,
            "amount": txn["amount"],
            "order_ref": order_ref,
            "from_code": _LEGACY_TRANSFER_ASSET_CODE,
            "to_code": UNALLOCATED_BANK_CODE,
            "action": "will-backfill",
        }
    _sync_payment_journal(
        conn,
        txn_id,
        txn["amount"],
        txn["type"],
        "transfer",
        order_id=txn["order_id"],
        payment_source="",
    )
    return {
        "txn_id": txn_id,
        "amount": txn["amount"],
        "order_ref": order_ref,
        "from_code": _LEGACY_TRANSFER_ASSET_CODE,
        "to_code": UNALLOCATED_BANK_CODE,
        "action": "backfilled",
    }

def _print_unallocated_transfers_report(results, *, dry_run):
    """Print the unallocated-transfer backfill report table and summary."""
    click.echo("Chuyển bút toán chuyển khoản cũ sang TK chưa phân bổ (1290)")
    click.echo("=" * 66)
    click.echo("")
    click.echo(
        f"{'Mã GD':<10}{'Số tiền':>16}{'Đơn hàng':<16}{'Hành động':<16}"
    )
    click.echo("-" * 58)
    for r in results:
        click.echo(
            f"#{r['txn_id']:<9}"
            f"{_vn_amount(r['amount']):>16}"
            f"{r['order_ref'][:15]:<16}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 58)

    backfilled = sum(1 for r in results if r["action"] == "backfilled")
    will_backfill = sum(1 for r in results if r["action"] == "will-backfill")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_backfill}")
    else:
        parts.append(f"đã sửa: {backfilled}")
    click.echo(f"Tổng: {len(results)} giao dịch  |  " + ", ".join(parts))

@click.command("repair-unallocated-transfers")
@click.option("--order-id", "order_id", type=int, default=None,
              help="ID đơn hàng cần chuyển bút toán chuyển khoản.")
@click.option("--all", "repair_all", is_flag=True, default=False,
              help="Chuyển tất cả giao dịch chuyển khoản cũ sang TK 1290.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_unallocated_transfers_cmd(order_id, repair_all, dry_run):
    """Chuyển bút toán chuyển khoản cũ (1200) sang TK chưa phân bổ (1290).

    DG-244 Phase 5 — historical backfill (FR5 backfill aspect, AC6):

      Tìm các giao dịch thanh toán (``payment_transactions``) có
      ``method = 'transfer'`` và ``payment_source`` rỗng, mà bút toán nhật ký
      hiện tại ghi Nợ tài khoản 1200 (default cũ trước Phase 4). Lệnh tạo lại
      bút toán qua ``_sync_payment_journal`` để tài sản (Nợ) chuyển sang TK
      1290 (Un-allocated Bank). Bên Có (2100/2200/2400) giữ nguyên — không tạo
      double-entry.

      * Giao dịch có ``payment_source`` (1210/1220) KHÔNG bị ảnh hưởng (NFR3).
      * Bút toán chi phí KHÔNG bị ảnh hưởng (NFR1).
      * Giao dịch tiền mặt/thẻ KHÔNG bị ảnh hưởng (chỉ ``method='transfer'`` mới
        từng được route tới 1200).
      * Lệnh idempotent: chạy lần hai sẽ không tìm thấy giao dịch nào cần sửa.

    Scope: backend only. Mọi chạy trên production database là bước UAT/ops
    dành cho Sinh — lệnh này chỉ triển khai và kiểm thử.

    Rollback stance: lệnh chỉ cập nhật tài khoản Nợ của bút toán
    payment_transaction. Để rollback, chạy lại ``_sync_payment_journal`` thủ
    công với asset code 1200 (không tự động rollback — mục đích là migration
    một chiều sang 1290 theo FR5).
    """
    if order_id is None and not repair_all:
        click.echo("Cần chỉ định --order-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if order_id is not None and repair_all:
        click.echo("Không thể dùng --order-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            txns = _transfer_txns_with_legacy_asset_line(
                conn, order_id=order_id
            )
            results = [
                _process_unallocated_transfer(conn, t, dry_run=dry_run)
                for t in txns
            ]
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair unallocated-transfers CLI error")
        click.echo(
            "Lỗi khi chuyển bút toán chuyển khoản. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo(
            "(không có giao dịch chuyển khoản nào cần chuyển sang TK 1290)"
        )
        return

    _print_unallocated_transfers_report(results, dry_run=dry_run)

