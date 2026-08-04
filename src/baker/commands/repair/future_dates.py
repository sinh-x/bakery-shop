"""Repair command module: repair_future_dates_cmd (extracted from repair.py)."""

from ._common import *  # noqa: F401,F403


def _future_dated_entries(conn):
    """Return journal entries whose ``created_at`` is in the future."""
    rows = conn.execute(
        """
        SELECT je.id          AS entry_id,
               je.description AS description,
               je.source_type AS source_type,
               je.source_id   AS source_id,
               je.created_at  AS created_at,
               je.locked_at   AS locked_at
        FROM journal_entries je
        WHERE je.created_at > ?
        ORDER BY je.id
        """,
        (now_utc(),),
    ).fetchall()
    return [
        {
            "entry_id": int(r["entry_id"]),
            "description": r["description"],
            "source_type": r["source_type"],
            "source_id": int(r["source_id"]) if r["source_id"] is not None else None,
            "created_at": r["created_at"],
            "locked": bool(r["locked_at"]),
        }
        for r in rows
    ]

@click.command("repair-future-dates")
@click.option("--entry-id", "entry_id", type=int, default=None, help="ID bút toán cần sửa ngày.")
@click.option("--all", "repair_all", is_flag=True, default=False, help="Sửa tất cả bút toán có ngày trong tương lai.")
@click.option("--dry-run", is_flag=True, default=False, help="Xem trước thay đổi, không ghi vào CSDL.")
def repair_future_dates_cmd(entry_id, repair_all, dry_run):
    """Sửa bút toán nhật ký có created_at trong tương lai về thời điểm hiện tại.

    Các bút toán có ``created_at > now_utc()`` (thường do lỗi múi giờ khi
    dùng ``strftime`` trong SQLite) sẽ được đặt lại ``created_at`` về thời
    điểm hiện tại. Bút toán đã khoá sẽ bị bỏ qua. Lệnh idempotent: chạy
    lần hai sẽ không tìm thấy bút toán nào cần sửa.
    """
    if entry_id is None and not repair_all:
        click.echo("Cần chỉ định --entry-id <id> hoặc --all.", err=True)
        raise SystemExit(1)
    if entry_id is not None and repair_all:
        click.echo("Không thể dùng --entry-id và --all cùng lúc.", err=True)
        raise SystemExit(1)

    try:
        with get_db() as conn:
            entries = _future_dated_entries(conn)
            if entry_id is not None:
                entries = [e for e in entries if e["entry_id"] == entry_id]
                if not entries:
                    click.echo(f"(không tìm thấy bút toán #{entry_id} hoặc bút toán không có ngày trong tương lai)")
                    return

            results = []
            now = now_utc()
            for e in entries:
                eid = e["entry_id"]
                if e["locked"]:
                    results.append({
                        "entry_id": eid,
                        "description": e["description"],
                        "source_type": e["source_type"],
                        "source_id": e["source_id"],
                        "created_at": e["created_at"],
                        "action": "locked",
                    })
                    continue

                if dry_run:
                    results.append({
                        "entry_id": eid,
                        "description": e["description"],
                        "source_type": e["source_type"],
                        "source_id": e["source_id"],
                        "created_at": e["created_at"],
                        "action": "will-repair",
                    })
                else:
                    conn.execute(
                        "UPDATE journal_entries SET created_at = ? WHERE id = ?",
                        (now, eid),
                    )
                    results.append({
                        "entry_id": eid,
                        "description": e["description"],
                        "source_type": e["source_type"],
                        "source_id": e["source_id"],
                        "created_at": now,
                        "action": "repaired",
                    })

            if not dry_run:
                conn.commit()
    except Exception:
        logger.exception("Repair future-dates CLI error")
        click.echo(
            "Lỗi khi sửa bút toán có ngày trong tương lai. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not results:
        click.echo("(không có bút toán nào cần sửa ngày)")
        return

    click.echo("Sửa bút toán có ngày trong tương lai")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'ID bút toán':<12}{'Mô tả':<30}{'Ngày cũ':<22}{'Hành động':<16}"
    )
    click.echo("-" * 80)
    for r in results:
        desc = (r["description"] or "")[:29]
        old_date = r["created_at"] or ""
        click.echo(
            f"{r['entry_id']:<12}"
            f"{desc:<30}"
            f"{old_date:<22}"
            f"{_ACTION_LABELS.get(r['action'], r['action']):<16}"
        )
    click.echo("-" * 80)

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

