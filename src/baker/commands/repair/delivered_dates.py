"""Repair command module: repair_delivered_dates_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403

_SOURCE_TYPE_LABELS = {
    "order": "Doanh thu",
    "order_cogs": "Giá vốn (COGS)",
    "order_shipping_release": "Giải phóng ship",
}

def _entries_needing_date_repair(conn):
    """Return entries whose transaction_date differs from delivered timestamp.

    Scans ``source_type IN ('order', 'order_cogs', 'order_shipping_release')``
    and compares each entry's ``transaction_date`` against the order's
    delivered-event timestamp (via :func:`_resolve_delivered_timestamp`).
    Entries whose transaction_date already matches are excluded (idempotent).
    Entries for orders without a delivered event are skipped.
    """
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.source_type AS source_type,
               je.source_id   AS source_id,
               je.transaction_date AS transaction_date,
               je.locked_at   AS locked_at
        FROM journal_entries je
        WHERE je.source_type IN ('order', 'order_cogs', 'order_shipping_release')
          AND je.description NOT LIKE 'Reversal:%'
        ORDER BY je.id
        """
    ).fetchall()

    results = []
    seen_order_refs = {}
    for r in rows:
        entry_id = int(r["entry_id"])
        source_type = r["source_type"]
        source_id = int(r["source_id"])
        current_td = r["transaction_date"]
        locked = bool(r["locked_at"])

        if source_id not in seen_order_refs:
            seen_order_refs[source_id] = _order_ref(conn, source_id)
        order_ref = seen_order_refs[source_id]

        delivered_ts = _resolve_delivered_timestamp(conn, source_id, order_ref)
        if delivered_ts is None:
            continue

        if current_td == delivered_ts:
            continue

        results.append({
            "entry_id": entry_id,
            "source_type": source_type,
            "source_id": source_id,
            "order_ref": order_ref,
            "current_transaction_date": current_td,
            "expected_transaction_date": delivered_ts,
            "locked": locked,
        })
    return results

def _process_date_repair_entry(conn, entry, *, dry_run):
    """Repair one entry's transaction_date.

    Locked entries are reported as ``locked`` and skipped.
    Dry-run returns ``will-repair`` without mutating.
    """
    if entry["locked"]:
        return {
            "entry_id": entry["entry_id"],
            "source_type": entry["source_type"],
            "source_id": entry["source_id"],
            "order_ref": entry["order_ref"],
            "current_transaction_date": entry["current_transaction_date"],
            "expected_transaction_date": entry["expected_transaction_date"],
            "action": "locked",
        }

    if dry_run:
        return {
            "entry_id": entry["entry_id"],
            "source_type": entry["source_type"],
            "source_id": entry["source_id"],
            "order_ref": entry["order_ref"],
            "current_transaction_date": entry["current_transaction_date"],
            "expected_transaction_date": entry["expected_transaction_date"],
            "action": "will-repair",
        }

    conn.execute(
        "UPDATE journal_entries SET transaction_date = ? WHERE id = ?",
        (entry["expected_transaction_date"], entry["entry_id"]),
    )
    return {
        "entry_id": entry["entry_id"],
        "source_type": entry["source_type"],
        "source_id": entry["source_id"],
        "order_ref": entry["order_ref"],
        "current_transaction_date": entry["current_transaction_date"],
        "expected_transaction_date": entry["expected_transaction_date"],
        "action": "repaired",
    }

def _print_date_repair_report(results, *, dry_run):
    """Print the date repair report table and per-type summary."""
    click.echo("Sửa ngày giao dịch (transaction_date) bút toán đơn hàng")
    click.echo("=" * 50)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<16}{'Loại':<24}{'Ngày cũ':<22}{'Ngày mới':<22}{'Hành động':<16}"
    )
    click.echo("-" * 100)
    for r in results:
        st_label = _SOURCE_TYPE_LABELS.get(r["source_type"], r["source_type"])
        click.echo(
            f"{r['order_ref'][:15]:<16}"
            f"{st_label:<24}"
            f"{(r['current_transaction_date'] or ''):<22}"
            f"{r['expected_transaction_date']:<22}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 100)

    repaired = sum(1 for r in results if r["action"] == "repaired")
    locked = sum(1 for r in results if r["action"] == "locked")
    will_repair = sum(1 for r in results if r["action"] == "will-repair")

    parts = []
    if dry_run:
        parts.append(f"sẽ sửa: {will_repair}")
    else:
        if repaired:
            parts.append(f"đã sửa: {repaired}")
        if locked:
            parts.append(f"khoá: {locked}")
    click.echo(f"Tổng: {len(results)} bút toán  |  " + ", ".join(parts))

@click.command("repair-delivered-dates")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_delivered_dates_cmd(dry_run):
    """Sửa ngày giao dịch (transaction_date) của bút toán đơn hàng.

    Tìm các bút toán ``source_type`` là ``order``, ``order_cogs``,
    ``order_shipping_release`` có ``transaction_date`` khác với thời điểm
    giao hàng (delivered event timestamp). Đặt lại ``transaction_date``
    về thời điểm giao hàng thực tế. Bút toán đã khoá được bỏ qua.

    Lệnh idempotent: chạy lần hai sẽ không tìm thấy bút toán nào cần sửa.
    """
    try:
        with get_db() as conn:
            entries = _entries_needing_date_repair(conn)
            results = [
                _process_date_repair_entry(conn, e, dry_run=dry_run)
                for e in entries
            ]
            if not dry_run:
                conn.commit()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Repair delivered-dates CLI error")
        click.echo(
            "Lỗi khi sửa ngày giao dịch. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có bút toán nào cần sửa ngày giao dịch)")
        return

    _print_date_repair_report(results, dry_run=dry_run)

