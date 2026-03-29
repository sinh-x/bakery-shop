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
    _render_customer_receipt,
    _render_work_ticket,
    _shop_config,
    _get_photo,
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
):
    """Print a receipt to the Y41BT thermal printer via USB.

    - type=work_ticket: internal work ticket (Phiếu Nội Bộ), single item, requires item_id
    - type=customer: customer receipt (BIÊN NHẬN)
    """
    if type not in ("work_ticket", "customer"):
        raise HTTPException(
            status_code=400,
            detail="Invalid type: must be 'work_ticket' or 'customer'",
        )

    if type == "work_ticket" and item_id is None:
        raise HTTPException(
            status_code=400,
            detail="item_id is required for work_ticket type",
        )

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        detail = _order_detail(conn, row)
        cfg = _shop_config(conn)

        if type == "work_ticket":
            # Single-item work ticket (Phiếu Nội Bộ)
            work_item = None
            for wi in detail.get("workItems", []):
                if str(wi.get("id")) == str(item_id):
                    work_item = wi
                    break
            if not work_item:
                raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

            # Fetch photo for cake-category products
            photo = None
            pid = work_item.get("productId", "") or work_item.get("product_id", "")
            if pid:
                cat_row = conn.execute(
                    "SELECT category FROM products WHERE id = ? OR product_code = ?",
                    (pid, pid),
                ).fetchone()
                if cat_row and cat_row["category"] in ("cake", "banh_kem"):
                    photo = _get_photo(conn, row["id"], item_id)

            img = _render_work_ticket(detail, work_item, cfg, photo, conn)

        elif type == "customer":
            img = _render_customer_receipt(detail, cfg, conn, show_photos=False)
        else:
            raise HTTPException(
                status_code=400,
                detail="Invalid type: must be 'work_ticket' or 'customer'",
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

    return {"status": "ok"}


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
