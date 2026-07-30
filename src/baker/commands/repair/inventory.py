"""Repair command module: repair_inventory_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _expense_events_needing_inventory_backfill(conn, event_id=None):
    """Find expense events with inventory purchase categories missing journal entries.

    Inventory purchase categories (``Nguyên liệu``, ``Bao bì``) debit Account 1300
    (Inventory) instead of an expense account. Missing journal entries for these
    events mean the purchase debit to 1300 was never recorded, which can cause a
    negative inventory balance.

    DG-302 Phase 6: expenses that carry a mappable ``subcategory`` debit the
    subcategory account (e.g. 5110), not Inventory, so they are excluded —
    ``repair-inventory`` is only for events that should debit 1300.
    """
    import json

    sql = """
        SELECT e.id, e.summary, e.data
        FROM events e
        WHERE e.type = 'expense'
          AND (e.deleted_at IS NULL OR e.deleted_at = '')
          AND NOT EXISTS (
              SELECT 1 FROM journal_entries je
              WHERE je.source_type = 'expense' AND je.source_id = e.id
          )
    """
    params = []
    if event_id is not None:
        sql += " AND e.id = ?"
        params.append(event_id)
    sql += " ORDER BY e.id ASC"

    rows = conn.execute(sql, params).fetchall()

    result = []
    for r in rows:
        data = json.loads(r["data"] or "{}")
        category = data.get("category")
        if category not in INVENTORY_PURCHASE_CATEGORIES:
            continue
        # Phase 6: a mappable subcategory debits its own account, not Inventory.
        subcategory = data.get("subcategory")
        if (
            isinstance(subcategory, str)
            and subcategory
            and EXPENSE_CATEGORY_TO_ACCOUNT_CODE.get(subcategory)
        ):
            continue
        result.append({
            "id": int(r["id"]),
            "summary": r["summary"],
            "data": data,
        })
    return result

def _process_inventory_backfill(conn, expense_event, *, dry_run):
    """Process one inventory expense event backfill.

    Calls :func:`_sync_expense_journal` to create the missing journal entry.
    Idempotent: resyncing an already-correct entry is a no-op.
    """
    event_id = expense_event["id"]
    summary = expense_event["summary"]
    data = expense_event["data"]
    category = data.get("category", "")
    amount = data.get("amount_vnd", 0)

    if dry_run:
        return {
            "event_id": event_id,
            "summary": summary,
            "category": category,
            "amount": float(amount) if amount else 0.0,
            "action": "will-backfill",
        }

    _sync_expense_journal(conn, event_id, data, summary)
    return {
        "event_id": event_id,
        "summary": summary,
        "category": category,
        "amount": float(amount) if amount else 0.0,
        "action": "backfilled",
    }

@click.command("repair-inventory")
@click.option("--event-id", "event_id", type=int, default=None, help="ID sự kiện chi phí cần bổ sung bút toán nhập kho.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Bổ sung bút toán cho tất cả sự kiện nhập kho còn thiếu.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_inventory_cmd(event_id, repair_all, dry_run):
    """Sửa số dư âm của tài khoản Hàng tồn kho (1300).

    Tìm các sự kiện chi phí thuộc danh mục nhập kho (``Nguyên liệu``,
    ``Bao bì``) chưa có bút toán nhật ký tương ứng và tạo bút toán
    Nợ 1300 / Có tài khoản thanh toán. Lệnh idempotent: chạy lần hai
    sẽ không tìm thấy sự kiện nào cần bổ sung.
    """
    if event_id is None and not repair_all:
        click.echo("Cần chỉ định --event-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if event_id is not None and repair_all:
        click.echo("Không thể dùng --event-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            events = _expense_events_needing_inventory_backfill(
                conn, event_id=event_id
            )

            results = []
            for e in events:
                results.append(
                    _process_inventory_backfill(conn, e, dry_run=dry_run)
                )

            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair inventory CLI error")
        click.echo(
            "Lỗi khi sửa bút toán nhập kho. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có sự kiện nhập kho nào cần bổ sung bút toán)")
        return

    click.echo("Sửa bút toán nhập kho (Hàng tồn kho 1300)")
    click.echo("=" * 50)
    click.echo("")
    click.echo(
        f"{'Mã SK':<10}{'Danh mục':<16}{'Số tiền':>16}{'Hành động':<16}"
    )
    click.echo("-" * 58)
    for r in results:
        click.echo(
            f"#{r['event_id']:<9}"
            f"{r['category'][:15]:<16}"
            f"{_vn_amount(r['amount']):>16}"
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
    click.echo(f"Tổng: {len(results)} sự kiện  |  " + ", ".join(parts))

