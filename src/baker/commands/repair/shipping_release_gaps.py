"""Repair command module: check_shipping_release_gaps_cmd (DG-366 Phase 5).

Read-only detection query (FR5 / AC6) that identifies delivered/completed
bus orders with shipping held in account 2200 (Bus Shipping Held) but no
matching ``order_shipping_release`` journal entry. Such orders have money
stuck in 2200 because the release entry (DR 2200 / CR 1101 or 1102) was
never created — the exact gap DG-366 repairs.

Mirrors :func:`check_revenue_gaps_cmd` (read-only, no mutation, VN labels).
The held-shipping total is computed via :func:`_held_shipping_for_order` so
the detection matches the canonical held calculation used by the sync and
repair paths. Only orders with ``held_in_2200 > 0`` AND no
``order_shipping_release`` entry are reported (the AC6 definition of the
gap). Bus orders with ``shipping_fee > 0`` but no held shipping (no payment
yet) and no release are not reported here — Phase 1 ensures the release is
always created at completion for the full ``shipping_fee``, so the absence
of a release on an unpaid completed order is a different (already-fixed)
pathway; the repair command's ``--all`` scan covers that case.
"""

from ._common import *  # noqa: F401,F403


@click.command("check-shipping-release-gaps")
def check_shipping_release_gaps_cmd():
    """Kiểm tra đơn ship bus giữ 2200 thiếu bút toán trả ship (chỉ đọc)."""
    try:
        with get_db() as conn:
            # Candidate bus orders in delivered/completed status with a
            # shipping fee and no order_shipping_release entry.
            candidates = conn.execute(
                f"""
                SELECT o.id, o.order_ref, o.due_date, o.status, o.shipping_fee
                FROM orders o
                WHERE o.status IN ({",".join("?" * len(DELIVERED_STATUSES))})
                  AND o.delivery_type = 'bus'
                  AND COALESCE(o.shipping_fee, 0) > 0
                  AND NOT EXISTS (
                      SELECT 1 FROM journal_entries je
                      WHERE je.source_type = 'order_shipping_release'
                        AND je.source_id = o.id
                  )
                ORDER BY o.id ASC
                """,  # nosec B608
                list(DELIVERED_STATUSES),
            ).fetchall()
            # Filter to orders with held shipping in 2200 > 0 (AC6 gap
            # definition). The canonical held calculation is used so the
            # detection matches the sync/repair paths exactly.
            rows = []
            for r in candidates:
                held = _held_shipping_for_order(conn, int(r["id"]))
                if held > 0:
                    rows.append(
                        {
                            "id": int(r["id"]),
                            "order_ref": r["order_ref"],
                            "due_date": r["due_date"],
                            "status": r["status"],
                            "shipping_fee": float(r["shipping_fee"] or 0),
                            "held_in_2200": held,
                        }
                    )
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Check shipping-release gaps CLI error")
        click.echo(
            "Lỗi khi kiểm tra khoảng trống trả ship. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not rows:
        click.echo("(không có đơn ship bus nào thiếu bút toán trả ship)")
        return

    click.echo("Kiểm tra khoảng trống trả ship bus")
    click.echo("=" * 40)
    click.echo("")
    click.echo(
        f"{'Mã đơn':<20}{'Ngày giao':>12}{'Phí ship':>14}{'Giữ 2200':>14}{'Trạng thái':<14}"
    )
    click.echo("-" * 74)
    for r in rows:
        click.echo(
            f"{r['order_ref'][:19]:<20}"
            f"{r['due_date'] or '':>12}"
            f"{_vn_amount(r['shipping_fee']):>14}"
            f"{_vn_amount(r['held_in_2200']):>14}"
            f"{r['status']:<14}"
        )
    click.echo("-" * 74)
    click.echo(f"Tổng: {len(rows)} đơn ship bus thiếu bút toán trả ship")