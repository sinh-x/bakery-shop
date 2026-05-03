"""Server-side thermal printing API for Y41BT USB printer.

POST /api/orders/{ref}/print triggers server-side thermal printing:
- Renders receipt PNG using existing receipt renderer
- Converts PNG to TSPL BITMAP commands
- Sends to Y41BT via USB (usblp at /dev/usb/lp0)
"""

import io
import os
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from PIL import Image

from baker.api.receipts import (
    _order_detail,
    _render_bus_label,
    _render_customer_receipt,
    _render_delivery_receipt,
    _render_shop_receipt,
    _render_work_ticket,
    _shop_config,
)
from baker.db.connection import get_db
from baker import usb_printer

router = APIRouter(prefix="/api/orders", tags=["printing"])

# USB printer device path from env (default: /dev/usb/lp0)
USB_PRINTER_DEVICE = os.environ.get("USB_PRINTER_DEVICE", "/dev/usb/lp0")


def _render_to_png(img: Image.Image) -> bytes:
    """Render a Pillow Image to PNG bytes."""
    buf = io.BytesIO()
    img.save(buf, format="PNG", quality=95)
    buf.seek(0)
    return buf.getvalue()


@router.post("/{ref}/print")
def print_receipt(
    ref: str,
    type: str = Query(..., description="Receipt type: work_ticket or customer"),
    item_id: Optional[int] = Query(None, description="Work item ID (required for work_ticket)"),
    printed_by: Optional[str] = Query(None, description="Tên nhân viên in phiếu"),
):
    """Print a receipt to the Y41BT thermal printer via USB.

    - type=work_ticket: internal work ticket (Phiếu Nội Bộ), single item, requires item_id
    - type=customer: customer receipt (BIÊN NHẬN)
    - type=bus_label: bus shipping label
    - type=shop: shop receipt (Phiếu giao hàng)
    - type=delivery: delivery receipt (Phiếu giao tận nơi)
    """
    if type not in ("work_ticket", "customer", "bus_label", "shop", "delivery"):
        raise HTTPException(
            status_code=400,
            detail="Invalid type: must be 'work_ticket', 'customer', 'bus_label', 'shop', or 'delivery'",
        )

    if type == "work_ticket" and item_id is None:
        raise HTTPException(
            status_code=400,
            detail="item_id is required for work_ticket type",
        )

    normalized_printed_by = printed_by or ""
    order_id: Optional[int] = None

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
        order_id = int(row["id"])

        detail = _order_detail(conn, row)
        cfg = _shop_config(conn)

        if type == "work_ticket":
            # Single-item work ticket (Phiếu Nội Bộ) — no photo for thermal print
            work_item = None
            for wi in detail.get("workItems", []):
                if str(wi.get("id")) == str(item_id):
                    work_item = wi
                    break
            if not work_item:
                raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

            img = _render_work_ticket(detail, work_item, cfg, None, conn)

        elif type == "customer":
            img = _render_customer_receipt(detail, cfg, conn, show_photos=False)
        elif type == "bus_label":
            img = _render_bus_label(detail, cfg)
        elif type == "shop":
            img = _render_shop_receipt(detail, cfg, conn)
        elif type == "delivery":
            img = _render_delivery_receipt(detail, cfg, conn)
        else:
            raise HTTPException(
                status_code=400,
                detail="Invalid type: must be 'work_ticket', 'customer', 'bus_label', 'shop', or 'delivery'",
            )

        png_bytes = _render_to_png(img)

    # Send to USB printer
    try:
        usb_printer.print_receipt(
            device_path=USB_PRINTER_DEVICE,
            png_bytes=png_bytes,
        )
    except FileNotFoundError:
        raise HTTPException(
            status_code=503,
            detail=f"Printer not found at {USB_PRINTER_DEVICE}. Is the USB cable connected?",
        )
    except PermissionError:
        raise HTTPException(
            status_code=503,
            detail=f"Permission denied accessing {USB_PRINTER_DEVICE}. "
            "Check printer permissions or add user to 'lp' group.",
        )
    except OSError as e:
        raise HTTPException(
            status_code=500,
            detail=f"Print failed: {e}",
        )

    printed_at: Optional[str] = None
    if type == "work_ticket" and order_id is not None:
        with get_db() as conn:
            conn.execute(
                """INSERT INTO print_log (order_id, item_id, receipt_type, printed_by)
                   VALUES (?, ?, ?, ?)""",
                (order_id, item_id, type, normalized_printed_by),
            )
            inserted = conn.execute(
                "SELECT printed_at FROM print_log WHERE id = last_insert_rowid()"
            ).fetchone()
            if inserted is not None:
                printed_at = inserted["printed_at"]

            conn.execute(
                """UPDATE orders
                   SET work_ticket_printed_at = COALESCE(work_ticket_printed_at, strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')),
                       work_ticket_printed_by = CASE
                           WHEN work_ticket_printed_at IS NULL THEN ?
                           ELSE work_ticket_printed_by
                       END
                   WHERE id = ?""",
                (normalized_printed_by, order_id),
            )

    return {
        "status": "ok",
        "printedAt": printed_at,
        "printedBy": normalized_printed_by,
    }


@router.get("/{ref}/print-log")
def get_print_log(ref: str):
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        logs = conn.execute(
            """SELECT id, item_id, receipt_type, printed_by, printed_at
               FROM print_log
               WHERE order_id = ?
               ORDER BY printed_at ASC, id ASC""",
            (row["id"],),
        ).fetchall()

    return [
        {
            "id": entry["id"],
            "itemId": entry["item_id"],
            "receiptType": entry["receipt_type"],
            "printedBy": entry["printed_by"],
            "printedAt": entry["printed_at"],
        }
        for entry in logs
    ]


@router.get("/print/status")
def print_status():
    """Check if the USB printer is accessible."""
    available = usb_printer.check_printer_status(USB_PRINTER_DEVICE)
    if available:
        return {"status": "ok", "printer": "available", "device": USB_PRINTER_DEVICE}
    else:
        return {
            "status": "error",
            "printer": "unavailable",
            "device": USB_PRINTER_DEVICE,
            "detail": "Printer device not found or not accessible",
        }
