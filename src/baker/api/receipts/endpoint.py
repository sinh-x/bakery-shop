"""Receipt API endpoint (router + get_receipt) — separated from renderers."""

import io
from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentTransaction
from baker.usb_printer import get_paper_mode


from ._drawing import *  # noqa: F401,F403
from ._helpers import *  # noqa: F401,F403
from ._helpers import _get_photo  # noqa: F401
from .renderers import (
    _render_work_ticket,  # noqa: F401
    _render_bus_label,  # noqa: F401
    _render_items_table,  # noqa: F401
    _render_financial_summary,  # noqa: F401
    _render_shop_receipt,  # noqa: F401
    _render_delivery_receipt,  # noqa: F401
    _render_customer_receipt,  # noqa: F401
)

router = APIRouter(prefix="/api/orders", tags=["receipts"])

def _order_detail(conn, row) -> dict:
    """Build full order detail dict from DB row."""
    from baker.models.order import Order
    from baker.models.work_item import WorkItem

    order = Order.from_row(row, conn)
    result = order.to_api_dict()

    item_rows = conn.execute(
        "SELECT * FROM order_items WHERE order_id = ? ORDER BY position, id",
        (row["id"],),
    ).fetchall()
    items = [WorkItem.from_row(r) for r in item_rows]
    # Attach blanks lists via the order_item_blanks junction (DG-294)
    from baker.api.work_items import _attach_blanks
    _attach_blanks(conn, items)
    result["workItems"] = [it.to_api_dict() for it in items]
    result["id"] = row["id"]  # keep as int for PaymentTransaction lookup

    return result

@router.get("/{ref}/receipt")
def get_receipt(
    ref: str,
    type: str = Query(..., description="Receipt type: work_ticket or customer"),
    item_id: Optional[int] = Query(None, description="Work item ID (required for work_ticket)"),
    photos: bool = Query(True, description="Include photos (set false for print version)"),
):
    """Generate receipt image as PNG.

    - type=work_ticket: internal receipt (Phiếu Nội Bộ), single item, requires item_id
    - type=customer: clean customer-facing receipt (BIÊN NHẬN)
    - type=bus_label: bus shipping label — phone, address, notes, rotated landscape
    - type=shop: shop receipt (Phiếu giao hàng) for pickup orders
    - type=delivery: delivery receipt (Phiếu giao tận nơi) for door-to-door orders
    """
    if type == "order":
        raise HTTPException(status_code=400, detail="type=order is no longer supported")

    if type == "work_ticket" and item_id is None:
        raise HTTPException(status_code=400, detail="item_id is required for work_ticket")

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        detail = _order_detail(conn, row)
        cfg = _shop_config(conn)
        paper_mode = get_paper_mode(conn)

        if type == "work_ticket":
            # Single-item work ticket (Phiếu Nội Bộ)
            work_item = None
            for wi in detail.get("workItems", []):
                if str(wi.get("id")) == str(item_id):
                    work_item = wi
                    break
            if not work_item:
                raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
            # Only fetch photo for cake-category products
            photo = None
            pid = work_item.get("productId", "") or work_item.get("product_id", "")
            if pid:
                cat_row = conn.execute(
                    "SELECT category FROM products WHERE id = ? OR product_code = ?",
                    (pid, pid),
                ).fetchone()
                if cat_row and cat_row["category"] in ("cake", "banh_kem"):
                    photo = _get_photo(conn, row["id"], item_id)
            # DG-228 Phase 3 / FR-3: merge sub-item index for multi-item orders.
            item_index, item_total = _main_item_index_total(detail, work_item)
            img = _render_work_ticket(detail, work_item, cfg, photo, conn, paper_mode=paper_mode,
                                      item_index=item_index, item_total=item_total)
        elif type == "customer":
            img = _render_customer_receipt(detail, cfg, conn, show_photos=photos, paper_mode=paper_mode)
        elif type == "bus_label":
            img = _render_bus_label(detail, cfg, paper_mode=paper_mode)
        elif type == "shop":
            img = _render_shop_receipt(detail, cfg, conn, paper_mode=paper_mode)
        elif type == "delivery":
            img = _render_delivery_receipt(detail, cfg, conn, paper_mode=paper_mode)
        else:
            raise HTTPException(status_code=400, detail="Invalid type: work_ticket, customer, bus_label, shop, or delivery")

        # DG-228 Phase 3 / FR-2: split into pages when content exceeds the cap.
        # The GET receipt endpoint returns the first page as a single PNG for
        # backward compatibility with the Flutter preview (multi-page print flow
        # is handled by printing.py in Phase 4).
        # CQ-2: only split work_ticket receipts on label paper — roll mode and
        # shop/delivery/bus_label types keep the single-image path so long roll
        # receipts print continuously and shop/delivery previews are not
        # truncated to page 1.
        # DG-271 Phase 1 / FR-1: customer receipts are no longer split on the
        # GET path — the full continuous image is returned so the Flutter screen
        # and share flow receive one complete receipt. Thermal print output is
        # unaffected (printing.py performs its own _split_pages independently).
        if type == "work_ticket" and paper_mode == "label":
            pages = _split_pages(img)
        else:
            pages = [img]
        first_page = pages[0]

        buf = io.BytesIO()
        first_page.save(buf, format="PNG", quality=95)
        buf.seek(0)

        return StreamingResponse(
            iter([buf.getvalue()]),
            media_type="image/png",
            headers={"Content-Disposition": f"inline; filename=receipt-{ref}-{type}.png"},
        )
