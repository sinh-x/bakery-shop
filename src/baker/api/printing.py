"""Server-side thermal printing API for Y41BT USB printer.

POST /api/orders/{ref}/print triggers server-side thermal printing:
- Renders receipt PNG using existing receipt renderer
- Converts PNG to TSPL BITMAP commands
- Sends to Y41BT via USB (usblp at /dev/usb/lp0)
"""

import io
import os
import socket
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
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
from baker.config import PRINT_IPP_URL
from baker.db.connection import get_db
from baker import ipp_client, usb_printer

router = APIRouter(prefix="/api/orders", tags=["printing"])

# USB printer device path from env (default: /dev/usb/lp0)
USB_PRINTER_DEVICE = os.environ.get("USB_PRINTER_DEVICE", "/dev/usb/lp0")


class PaperModeIn(BaseModel):
    paperMode: str


@router.get("/print/paper-mode")
def get_paper_mode():
    """Return the effective printer paper mode.

    DB override (app_config.paper_mode) takes precedence over the PAPER_MODE
    env var default. Returns "label" or "roll".
    """
    with get_db() as conn:
        mode = usb_printer.get_paper_mode(conn)
        trail_mm = usb_printer.get_trail_mm(conn)
    return {
        "paperMode": mode,
        "default": usb_printer.PAPER_MODE_DEFAULT,
        "trailMm": trail_mm,
    }


@router.put("/print/paper-mode")
def set_paper_mode(body: PaperModeIn):
    """Set the printer paper mode runtime override (persists to app_config).

    Selection takes effect on the next print/status call (no restart required).
    """
    value = body.paperMode.strip()
    if value not in usb_printer.PAPER_MODES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid paperMode: must be one of {list(usb_printer.PAPER_MODES)}",
        )
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id FROM app_config WHERE config_key = ?",
            (usb_printer.PAPER_MODE_CONFIG_KEY,),
        ).fetchone()
        if existing is not None:
            conn.execute(
                "UPDATE app_config SET config_value = ?, active = 1 WHERE config_key = ?",
                (value, usb_printer.PAPER_MODE_CONFIG_KEY),
            )
        else:
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active)"
                " VALUES (?, ?, 0, 1)",
                (usb_printer.PAPER_MODE_CONFIG_KEY, value),
            )
    return {"paperMode": value}


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

        # Resolve paper mode and trail BEFORE renderers so the tear
        # indicator visual appears in the USB print path (CQ-1).
        paper_mode = usb_printer.get_paper_mode(conn)
        trail_mm = usb_printer.get_trail_mm(conn)

        if type == "work_ticket":
            # Single-item work ticket (Phiếu Nội Bộ) — no photo for thermal print
            work_item = None
            for wi in detail.get("workItems", []):
                if str(wi.get("id")) == str(item_id):
                    work_item = wi
                    break
            if not work_item:
                raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

            img = _render_work_ticket(detail, work_item, cfg, None, conn,
                                      paper_mode=paper_mode)

        elif type == "customer":
            img = _render_customer_receipt(detail, cfg, conn,
                                           show_photos=False,
                                           paper_mode=paper_mode)
        elif type == "bus_label":
            img = _render_bus_label(detail, cfg, paper_mode=paper_mode)
        elif type == "shop":
            img = _render_shop_receipt(detail, cfg, conn, paper_mode=paper_mode)
        elif type == "delivery":
            img = _render_delivery_receipt(detail, cfg, conn, paper_mode=paper_mode)
        else:
            raise HTTPException(
                status_code=400,
                detail="Invalid type: must be 'work_ticket', 'customer', 'bus_label', 'shop', or 'delivery'",
            )

        png_bytes = _render_to_png(img)

    # Convert PNG to TSPL once — shared by both transport paths
    tspl_data = usb_printer.png_to_tspl(png_bytes, paper_mode=paper_mode, trail_mm=trail_mm)

    if PRINT_IPP_URL:
        # IPP transport: send pre-rendered TSPL to CUPS endpoint
        try:
            with usb_printer.print_lock:
                ipp_client.send_tspl_to_ipp(tspl_data, PRINT_IPP_URL)
        except ipp_client.IppConnectionError as e:
            raise HTTPException(
                status_code=503,
                detail=f"Cannot connect to IPP printer: {e}",
            )
        except ipp_client.IppHttpError as e:
            raise HTTPException(
                status_code=503,
                detail=f"IPP printer HTTP error {e.http_status}",
            )
        except ipp_client.IppError as e:
            raise HTTPException(
                status_code=500,
                detail=f"IPP printer error: {e}",
            )
    else:
        # USB transport: write TSPL directly to /dev/usb/lp0 (backward compatible)
        try:
            with usb_printer.print_lock:
                fd = None
                try:
                    fd = usb_printer.open_printer(USB_PRINTER_DEVICE)
                    os.write(fd, tspl_data)
                finally:
                    if fd is not None:
                        os.close(fd)
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
                   SET work_ticket_printed_at = CASE
                           WHEN work_ticket_printed_at IS NULL THEN strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')
                           ELSE work_ticket_printed_at
                       END,
                       work_ticket_printed_by = CASE
                           WHEN work_ticket_printed_at IS NULL THEN ?
                           WHEN COALESCE(work_ticket_printed_by, '') = '' AND ? <> '' THEN ?
                           ELSE work_ticket_printed_by
                       END
                   WHERE id = ?""",
                (
                    normalized_printed_by,
                    normalized_printed_by,
                    normalized_printed_by,
                    order_id,
                ),
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
    """Check if the USB printer is accessible and return effective paper mode.

    When PRINT_IPP_URL is configured, also probes the IPP endpoint via
    TCP connectivity check.
    """
    available = usb_printer.check_printer_status(USB_PRINTER_DEVICE)
    with get_db() as conn:
        paper_mode = usb_printer.get_paper_mode(conn)
    base = {
        "printer": "available" if available else "unavailable",
        "device": USB_PRINTER_DEVICE,
        "paperMode": paper_mode,
    }
    if PRINT_IPP_URL:
        ipp_available = False
        ipp_host = None
        ipp_port = None
        try:
            parsed = ipp_client._parse_url(PRINT_IPP_URL)
            ipp_host, ipp_port = parsed[0], parsed[1]
            sock = socket.create_connection((ipp_host, ipp_port), timeout=3.0)
            sock.close()
            ipp_available = True
        except (ValueError, OSError):
            pass
        base["ippPrinter"] = "available" if ipp_available else "unavailable"
        if ipp_host:
            base["ippUrl"] = PRINT_IPP_URL
    if available or (PRINT_IPP_URL and base.get("ippPrinter") == "available"):
        return {"status": "ok", **base}
    else:
        detail = "Printer device not found or not accessible"
        if PRINT_IPP_URL and base.get("ippPrinter") == "unavailable":
            detail += f"; IPP endpoint unreachable at {PRINT_IPP_URL}"
        return {
            "status": "error",
            **base,
            "detail": detail,
        }
