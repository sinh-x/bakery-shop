"""``baker address`` CLI command group (DG-387 Phase 4).

Read-only address utilities. The ``missing-links`` subcommand lists unique
``(delivery_address, order_count)`` pairs for door-to-door delivery orders
that have no Google Maps link, so staff can see which addresses still need
a link filled in (FR4, NFR3, AC5).
"""

import logging

import click

from baker.db.connection import get_db

logger = logging.getLogger(__name__)

# Door-to-door delivery types (matches v102 backfill + Phase 3 sync).
_DOOR_DELIVERY_TYPES = ("door", "delivery")


@click.group("address")
def address_cmd():
    """Tiện ích địa chỉ giao hàng (chỉ đọc)."""


@address_cmd.command("missing-links")
def missing_links_cmd():
    """Liệt kê địa chỉ giao tận nơi chưa có liên kết Google Maps (chỉ đọc).

    Truy vấn tất cả đơn hàng ``delivery_type IN ('door','delivery')`` có
    ``delivery_address`` không rỗng nhưng ``google_maps_url`` rỗng/NULL,
    nhóm theo ``delivery_address`` và đếm số đơn. Kết quả in ra stdout.
    Lệnh chỉ đọc — không ghi vào CSDL (NFR3).
    """
    placeholders = ",".join("?" for _ in _DOOR_DELIVERY_TYPES)
    try:
        with get_db() as conn:
            rows = conn.execute(
                f"""
                SELECT delivery_address AS delivery_address,
                       COUNT(*) AS order_count
                FROM orders
                WHERE delivery_type IN ({placeholders})
                  AND delivery_address IS NOT NULL
                  AND delivery_address != ''
                  AND (google_maps_url IS NULL OR google_maps_url = '')
                GROUP BY delivery_address
                ORDER BY order_count DESC, delivery_address ASC
                """,
                list(_DOOR_DELIVERY_TYPES),
            ).fetchall()
    except Exception:  # noqa: BLE001 — top-level CLI guard
        logger.exception("Address missing-links CLI error")
        click.echo(
            "Lỗi khi liệt kê địa chỉ thiếu liên kết. Xem log máy chủ để biết chi tiết.",
            err=True,
        )
        raise SystemExit(1)

    if not rows:
        click.echo("(không có địa chỉ giao tận nơi nào thiếu liên kết Google Maps)")
        return

    click.echo("Địa chỉ giao tận nơi thiếu liên kết Google Maps")
    click.echo("=" * 50)
    click.echo("")
    click.echo(f"{'Địa chỉ giao':<40}{'Số đơn':>10}")
    click.echo("-" * 50)
    for r in rows:
        address = (r["delivery_address"] or "")[:39]
        click.echo(f"{address:<40}{int(r['order_count']):>10}")
    click.echo("-" * 50)
    total_orders = sum(int(r["order_count"]) for r in rows)
    click.echo(
        f"Tổng: {len(rows)} địa chỉ  |  {total_orders} đơn cần bổ sung liên kết"
    )