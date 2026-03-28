"""Receipt image generation API for thermal printer.

Generates two receipt types as PNG images sized for 80mm thermal paper:
- Work ticket (Phiếu Nội Bộ): internal single-item receipt with photo thumbnails
- Customer receipt ("BIÊN NHẬN"): clean, customer-facing, matching paper bill style
"""

import io
from pathlib import Path
from typing import Optional

import baker.config
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from PIL import Image, ImageDraw, ImageFont

from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentTransaction

router = APIRouter(prefix="/api/orders", tags=["receipts"])

# --- Constants ---

RECEIPT_WIDTH = 576  # 80mm at 203 DPI
MARGIN = 20
CONTENT_WIDTH = RECEIPT_WIDTH - 2 * MARGIN
THUMBNAIL_SIZE = 128
LINE_GAP = 6

# Font sizes (optimized for 203 DPI thermal print)
_SZ_TITLE = 32
_SZ_SUBTITLE = 24
_SZ_BODY = 20
_SZ_SMALL = 16

# Shop defaults (matching the physical biên nhận form, without ĐC 2)
_SHOP_DEFAULTS = {
    "receipt_shop_name": "TIỆM BÁNH ĐOÀN GIA",
    "receipt_shop_specialty": "BÁNH KEM SINH NHẬT - RAU CÂU FLAN - BÔNG LAN TRỨNG MUỐI",
    "receipt_shop_address": "Hòn Khói, Ninh Diêm, Ninh Hòa, Khánh Hòa",
    "receipt_shop_phone": "0972 283 134 - 0968 187 434 - 0981 960 535",
}


# --- Helpers ---

def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    import baker as _pkg
    d = Path(_pkg.__file__).parent / "assets" / "fonts"
    return ImageFont.truetype(str(d / ("NotoSans-Bold.ttf" if bold else "NotoSans-Regular.ttf")), size)


def _format_vnd(amount) -> str:
    """Format Vietnamese currency: 275000 → '275' (shortened, divide by 1000, no suffix)."""
    n = int(float(amount) / 1000)
    return str(n)


def _th(text: str, font) -> int:
    """Text height in pixels."""
    bb = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=font)
    return bb[3] - bb[1]


def _tw(text: str, font) -> int:
    """Text width in pixels."""
    bb = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=font)
    return bb[2] - bb[0]


def _center(draw, y, text, font, color=(0, 0, 0)):
    """Draw centered text. Return y after."""
    w, h = _tw(text, font), _th(text, font)
    draw.text(((RECEIPT_WIDTH - w) // 2, y), text, font=font, fill=color)
    return y + h + LINE_GAP


def _left(draw, y, text, font, color=(0, 0, 0), x=None):
    """Draw left-aligned text at x (default MARGIN). Return y after."""
    draw.text((x if x is not None else MARGIN, y), text, font=font, fill=color)
    return y + _th(text, font) + LINE_GAP


def _right_at(draw, y, text, font, color=(0, 0, 0)):
    """Draw right-aligned text at y. Return y after."""
    w = _tw(text, font)
    draw.text((RECEIPT_WIDTH - MARGIN - w, y), text, font=font, fill=color)
    return y + _th(text, font) + LINE_GAP


def _row(draw, y, label, value, font_l, font_v=None, color_v=(0, 0, 0)):
    """Draw label left + value right on same line. Return y after."""
    if font_v is None:
        font_v = font_l
    draw.text((MARGIN, y), label, font=font_l, fill=(0, 0, 0))
    w = _tw(value, font_v)
    draw.text((RECEIPT_WIDTH - MARGIN - w, y), value, font=font_v, fill=color_v)
    h = max(_th(label, font_l), _th(value, font_v))
    return y + h + LINE_GAP


def _sep(draw, y):
    """Thin separator line."""
    draw.line([(MARGIN, y + 2), (RECEIPT_WIDTH - MARGIN, y + 2)], fill=(160, 160, 160), width=1)
    return y + LINE_GAP + 6


def _double(draw, y):
    """Double separator line."""
    draw.line([(MARGIN, y), (RECEIPT_WIDTH - MARGIN, y)], fill=(0, 0, 0), width=1)
    draw.line([(MARGIN, y + 4), (RECEIPT_WIDTH - MARGIN, y + 4)], fill=(0, 0, 0), width=1)
    return y + 12


def _wrap(text, font, max_w):
    """Word-wrap text to fit max_w. Return list of lines."""
    if not text:
        return []
    words = text.split()
    lines, cur = [], ""
    for word in words:
        test = cur + (" " if cur else "") + word
        if _tw(test, font) <= max_w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


# --- Config ---

def _shop_config(conn) -> dict:
    cfg = dict(_SHOP_DEFAULTS)
    rows = conn.execute(
        "SELECT config_key, config_value FROM app_config WHERE config_key LIKE 'receipt_%'"
    ).fetchall()
    for r in rows:
        if r["config_key"] in cfg:
            cfg[r["config_key"]] = r["config_value"]
    return cfg


# --- Header (matching physical biên nhận) ---

def _header(draw, y, cfg):
    """Draw shop header: name, specialty, address, phone, then double line."""
    # Shop name — large bold
    y = _center(draw, y, cfg["receipt_shop_name"], _font(_SZ_TITLE, True))
    # Specialty
    spec = cfg.get("receipt_shop_specialty", "")
    if spec:
        y = _center(draw, y, spec, _font(_SZ_SMALL, True), (60, 60, 60))
    # Address
    addr = cfg.get("receipt_shop_address", "")
    if addr:
        y = _center(draw, y, addr, _font(_SZ_SMALL), (80, 80, 80))
    # Phone — use ☎ if NotoSans supports it, otherwise fallback to SĐT:
    phone = cfg.get("receipt_shop_phone", "")
    if phone:
        y = _center(draw, y, f"SĐT: {phone}", _font(_SZ_SMALL), (80, 80, 80))
    y = _double(draw, y)
    return y


# --- Receipt renderers ---

def _render_work_ticket(order, work_item, cfg, photo_bytes, conn) -> Image.Image:
    """Internal receipt (Phiếu Nội Bộ) for production staff — single item per receipt.

    Shows: product name (large), qty, notes/remarks, photo, due date, birthday, delivery info.
    NO shop header.
    """
    img = Image.new("RGB", (RECEIPT_WIDTH, 2000), "white")
    draw = ImageDraw.Draw(img)

    fb = _font(_SZ_BODY)
    fbb = _font(_SZ_BODY, True)
    fs = _font(_SZ_SMALL)
    ft = _font(_SZ_TITLE, True)   # large title font for product name
    fs_title = _font(_SZ_SUBTITLE, True)

    y = MARGIN

    # Title — "PHIẾU NỘI BỘ" (no shop header)
    y = _center(draw, y, "PHIẾU NỘI BỘ", fs_title)
    y = _sep(draw, y)

    # Order ref
    ref = order.get("orderRef", "") or order.get("order_ref", "")
    y = _center(draw, y, f"Mã đơn: {ref}", fs_title)

    # Customer
    name = order.get("customerName", "") or order.get("customer_name", "")
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    if name:
        cust_line = f"Khách hàng: {name}"
        if phone:
            cust_line += f" - SĐT: {phone}"
        y = _left(draw, y, cust_line, fb)
    y = _sep(draw, y)

    # Product name — LARGE
    product = work_item.get("productName", "") or work_item.get("product_name", "")
    y = _left(draw, y, product, ft)
    y += 4

    # Birthday
    if work_item.get("isBirthday") or work_item.get("is_birthday"):
        age = work_item.get("age")
        age_text = f"* SINH NHẬT *{(' - ' + str(age) + ' tuổi') if age else ''}"
        y = _left(draw, y, age_text, fbb, (180, 0, 0))

    # Qty (prominent)
    qty = work_item.get("quantity", 1)
    y = _left(draw, y, f"SỐ LƯỢNG: {qty}", fbb)

    # Photo thumbnail
    if photo_bytes:
        try:
            photo = Image.open(io.BytesIO(photo_bytes)).convert("RGB")
            photo.thumbnail((THUMBNAIL_SIZE, THUMBNAIL_SIZE), Image.LANCZOS)
            x_photo = RECEIPT_WIDTH - MARGIN - THUMBNAIL_SIZE
            bg = Image.new("RGB", (THUMBNAIL_SIZE, THUMBNAIL_SIZE), "white")
            bg.paste(photo, ((THUMBNAIL_SIZE - photo.width) // 2, (THUMBNAIL_SIZE - photo.height) // 2))
            img.paste(bg, (x_photo, y))
            draw.rectangle([x_photo, y, x_photo + THUMBNAIL_SIZE, y + THUMBNAIL_SIZE], outline=(200, 200, 200))
            y += THUMBNAIL_SIZE + LINE_GAP
        except Exception:
            pass

    # Notes/remarks
    notes = work_item.get("notes", "") or ""
    if notes:
        y = _left(draw, y, "Ghi chú:", fbb)
        for ln in _wrap(notes, fs, CONTENT_WIDTH):
            y = _left(draw, y, ln, fs, (80, 80, 80))

    y = _sep(draw, y)

    # Due date (prominent)
    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    if due:
        due_str = f"NGÀY GIAO: {due}"
        if due_time:
            due_str += f" {due_time}"
        y = _center(draw, y, due_str, fs_title)

    # Delivery type + address
    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    dtype_vn = "Nhận tại tiệm" if dtype == "pickup" else "Giao hàng"
    y = _left(draw, y, f"Hình thức: {dtype_vn}", fb)

    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    if dtype != "pickup" and daddr:
        for ln in _wrap(daddr, fs, CONTENT_WIDTH - 20):
            y = _left(draw, y, f"  {ln}", fs)

    # Footer
    y += 4
    y = _double(draw, y)
    y = _center(draw, y, "--- Phiếu nội bộ ---", fs, (120, 120, 120))

    return img.crop((0, 0, RECEIPT_WIDTH, y + MARGIN))


def _render_customer_receipt(order, cfg, conn) -> Image.Image:
    """Customer receipt ('BIÊN NHẬN') matching the physical paper bill style."""
    work_items = order.get("workItems", [])

    img = Image.new("RGB", (RECEIPT_WIDTH, 2000), "white")
    draw = ImageDraw.Draw(img)

    fb = _font(_SZ_BODY)
    fbb = _font(_SZ_BODY, True)
    fs = _font(_SZ_SMALL)

    y = MARGIN
    y = _header(draw, y, cfg)

    # Title — matching the paper form
    y = _center(draw, y, "BIÊN NHẬN", _font(_SZ_SUBTITLE, True))
    y = _sep(draw, y)

    # Order ref
    ref = order.get("orderRef", "") or order.get("order_ref", "")
    y = _center(draw, y, f"Mã đơn: {ref}", _font(_SZ_SUBTITLE, True))

    # Date
    created = order.get("createdAt", "") or order.get("created_at", "")
    if created:
        y = _left(draw, y, f"Ngày: {created[:10]}", fb)

    # Customer info — single line like the paper form: "Tên KH: ___  ĐT: ___"
    name = order.get("customerName", "") or order.get("customer_name", "")
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    cust_line = f"Tên khách hàng: {name}"
    if phone:
        cust_line += f"    ĐT: {phone}"
    y = _left(draw, y, cust_line, fb)
    y = _sep(draw, y)

    # Items — simpler table (no unit price, matching paper "Nội dung" section)
    y = _left(draw, y, "Nội dung:", fbb)
    for item in work_items:
        item_name = item.get("productName", "") or item.get("product_name", "")
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        total = qty * unit_price

        line = f"  - {item_name}  x{qty}"
        draw.text((MARGIN, y), line, font=fb, fill=(0, 0, 0))
        total_str = _format_vnd(total)
        w = _tw(total_str, fb)
        draw.text((RECEIPT_WIDTH - MARGIN - w, y), total_str, font=fb, fill=(0, 0, 0))
        y += _th(line, fb) + LINE_GAP

    y = _sep(draw, y)

    # Totals — matching paper: Tiền / Đưa trước / Còn lại
    total_price = float(order.get("totalPrice", 0) or order.get("total_price", 0))
    y = _row(draw, y, "Tiền:", _format_vnd(total_price), fbb)

    order_id = order.get("id")
    total_paid = PaymentTransaction.total_for_order(conn, order_id) if order_id else 0.0
    remaining = total_price - total_paid

    y = _row(draw, y, "Đưa trước:", _format_vnd(total_paid), fb, color_v=(0, 100, 0))
    if remaining > 0:
        y = _row(draw, y, "Còn lại:", _format_vnd(remaining), fb, color_v=(180, 0, 0))
    y = _sep(draw, y)

    # Due date + delivery
    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    if due:
        due_str = f"Ngày nhận: {due}"
        if due_time:
            due_str += f" {due_time}"
        y = _left(draw, y, due_str, fb)

    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    dtype_vn = "Nhận tại tiệm" if dtype == "pickup" else "Giao hàng"
    y = _left(draw, y, f"Hình thức: {dtype_vn}", fb)

    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    if dtype != "pickup" and daddr:
        for ln in _wrap(daddr, fs, CONTENT_WIDTH - 20):
            y = _left(draw, y, f"  {ln}", fs)

    # Footer
    y += 4
    y = _double(draw, y)
    y = _center(draw, y, "Cảm ơn quý khách!", fb, (100, 100, 100))

    return img.crop((0, 0, RECEIPT_WIDTH, y + MARGIN))


# --- Order detail builder ---

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
    result["workItems"] = [WorkItem.from_row(r).to_api_dict() for r in item_rows]
    result["id"] = row["id"]  # keep as int for PaymentTransaction lookup

    return result


def _get_photo(conn, order_id: int, work_item_id: int) -> Optional[bytes]:
    """Get first photo bytes for a work item."""
    for query, params in [
        ("SELECT hash FROM photos p JOIN order_photos op ON p.id = op.photo_id WHERE op.order_id = ? AND op.work_item_id = ? LIMIT 1", (order_id, work_item_id)),
        ("SELECT hash FROM photos p JOIN order_photos op ON p.id = op.photo_id WHERE op.order_id = ? LIMIT 1", (order_id,)),
    ]:
        row = conn.execute(query, params).fetchone()
        if row:
            photo_path = baker.config.PHOTOS_DIR / f"{row['hash']}.jpg"
            if photo_path.exists():
                return photo_path.read_bytes()
    return None


# --- API endpoint ---

@router.get("/{ref}/receipt")
def get_receipt(
    ref: str,
    type: str = Query(..., description="Receipt type: work_ticket or customer"),
    item_id: Optional[int] = Query(None, description="Work item ID (required for work_ticket)"),
):
    """Generate receipt image as PNG.

    - type=work_ticket: internal receipt (Phiếu Nội Bộ), single item, requires item_id
    - type=customer: clean customer-facing receipt (BIÊN NHẬN)
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

        if type == "work_ticket":
            # Single-item work ticket (Phiếu Nội Bộ)
            work_item = None
            for wi in detail.get("workItems", []):
                if str(wi.get("id")) == str(item_id):
                    work_item = wi
                    break
            if not work_item:
                raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
            photo = _get_photo(conn, row["id"], item_id)
            img = _render_work_ticket(detail, work_item, cfg, photo, conn)
        elif type == "customer":
            img = _render_customer_receipt(detail, cfg, conn)
        else:
            raise HTTPException(status_code=400, detail="Invalid type: work_ticket or customer")

        buf = io.BytesIO()
        img.save(buf, format="PNG", quality=95)
        buf.seek(0)

        return StreamingResponse(
            iter([buf.getvalue()]),
            media_type="image/png",
            headers={"Content-Disposition": f"inline; filename=receipt-{ref}-{type}.png"},
        )
