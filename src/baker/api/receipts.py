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
    "receipt_shop_address": "61 Hòn Khói, Ninh Diêm, Ninh Hòa, Khánh Hòa",
    "receipt_shop_phone": "0972 283 134 - 0968 187 434 - 0981 960 535",
}


# --- Helpers ---

def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    import baker as _pkg
    d = Path(_pkg.__file__).parent / "assets" / "fonts"
    return ImageFont.truetype(str(d / ("NotoSans-Bold.ttf" if bold else "NotoSans-Regular.ttf")), size)


def _emoji_font(size: int) -> ImageFont.FreeTypeFont:
    import baker as _pkg
    d = Path(_pkg.__file__).parent / "assets" / "fonts"
    return ImageFont.truetype(str(d / "NotoEmoji-Variable.ttf"), size)


def _format_vnd(amount) -> str:
    """Format Vietnamese currency: 275000 → '275' (shortened, divide by 1000, no suffix)."""
    n = int(float(amount) / 1000)
    return str(n)


def _format_vnd_full(amount) -> str:
    """Full Vietnamese currency: 275000 → '275.000đ' (for financial summaries)."""
    n = int(float(amount))
    return f"{n:,}đ".replace(",", ".")


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


def _dots(draw, y, x_start, x_end, font, color=(180, 180, 180)):
    """Draw dotted leader line from x_start to x_end at baseline of text."""
    dot_w = _tw(".", font)
    spacing = dot_w + 2
    mid_y = y + _th("A", font) // 2
    x = x_start + 4
    while x + dot_w < x_end - 4:
        draw.text((x, y), ".", font=font, fill=color)
        x += spacing


def _icon_text(draw, y, icon, text, text_font, color=(0, 0, 0), x=None, icon_size=None):
    """Draw an emoji icon followed by text. Return y after."""
    x = x if x is not None else MARGIN
    sz = icon_size or text_font.size
    ef = _emoji_font(sz)
    draw.text((x, y), icon, font=ef, fill=color)
    icon_w = _tw(icon, ef)
    draw.text((x + icon_w + 3, y), text, font=text_font, fill=color)
    h = max(_th(icon, ef), _th(text, text_font))
    return y + h + LINE_GAP


def _icon_text_centered(draw, y, icon, text, text_font, color=(0, 0, 0), icon_size=None):
    """Draw centered emoji icon + text. Return y after."""
    sz = icon_size or text_font.size
    ef = _emoji_font(sz)
    icon_w = _tw(icon, ef)
    text_w = _tw(text, text_font)
    total_w = icon_w + 3 + text_w
    x = (RECEIPT_WIDTH - total_w) // 2
    draw.text((x, y), icon, font=ef, fill=color)
    draw.text((x + icon_w + 3, y), text, font=text_font, fill=color)
    h = max(_th(icon, ef), _th(text, text_font))
    return y + h + LINE_GAP


import re as _re

# Regex matching emoji characters (common ranges)
_EMOJI_RE = _re.compile(
    "["
    "\U0000200D"          # zero width joiner
    "\U00002600-\U000027BF"  # misc symbols
    "\U0000FE00-\U0000FE0F"  # variation selectors
    "\U0001F000-\U0001FAFF"  # all extended emoji blocks
    "\U00002702-\U000027B0"  # dingbats
    "\U0000FE0F"          # variation selector-16
    "]+", _re.UNICODE
)


def _draw_mixed(draw, x, y, text, text_font, color=(0, 0, 0)):
    """Draw text with mixed NotoSans + NotoEmoji fonts.

    Splits text into emoji and non-emoji segments, rendering each
    with the appropriate font. Returns x position after drawing.
    """
    ef = _emoji_font(text_font.size)
    parts = _EMOJI_RE.split(text)
    emojis = _EMOJI_RE.findall(text)

    for i, part in enumerate(parts):
        if part:
            draw.text((x, y), part, font=text_font, fill=color)
            x += _tw(part, text_font)
        if i < len(emojis):
            draw.text((x, y), emojis[i], font=ef, fill=color)
            x += _tw(emojis[i], ef)
    return x


def _mixed_tw(text, text_font) -> int:
    """Measure width of mixed emoji+text string."""
    ef = _emoji_font(text_font.size)
    parts = _EMOJI_RE.split(text)
    emojis = _EMOJI_RE.findall(text)
    w = 0
    for i, part in enumerate(parts):
        if part:
            w += _tw(part, text_font)
        if i < len(emojis):
            w += _tw(emojis[i], ef)
    return w


_NOTE_LINE_GAP = 10  # extra spacing for note lines

def _left_mixed(draw, y, text, font, color=(0, 0, 0), x=None):
    """Draw left-aligned mixed emoji+text. Return y after with note-friendly spacing."""
    x = x if x is not None else MARGIN
    _draw_mixed(draw, x, y, text, font, color)
    return y + _th("A", font) + _NOTE_LINE_GAP


def _wrap(text, font, max_w):
    """Word-wrap text to fit max_w. Handles embedded newlines. Return list of lines."""
    if not text:
        return []
    paragraphs = text.split("\n")
    lines = []
    for para in paragraphs:
        words = para.split()
        if not words:
            lines.append("")
            continue
        cur = ""
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
    """Draw shop header: name (large), specialty, address, phones."""
    # Shop name — large bold, prominent
    y = _center(draw, y, cfg["receipt_shop_name"], _font(36, True))
    y += 2

    # Specialty — smaller, muted
    spec = cfg.get("receipt_shop_specialty", "")
    if spec:
        # Title-case style for readability
        y = _center(draw, y, spec, _font(_SZ_SMALL, True), (80, 80, 80))
    y += 4

    # Address with pin icon
    addr = cfg.get("receipt_shop_address", "")
    if addr:
        y = _icon_text_centered(draw, y, "\U0001F4CD", addr, _font(_SZ_SMALL), (80, 80, 80))

    # Phone numbers with phone icon
    phone = cfg.get("receipt_shop_phone", "")
    if phone:
        parts = [p.strip() for p in phone.split("-") if p.strip()]
        phone_line = " \u2022 ".join(parts)
        y = _icon_text_centered(draw, y, "\u260E", phone_line, _font(_SZ_SMALL), (80, 80, 80))

    y += 8
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

    # Date
    created = order.get("createdAt", "") or order.get("created_at", "")
    if created:
        y = _left(draw, y, f"Ngày: {created[:10]}", fb)
    y += 4
    y = _double(draw, y)

    # --- Section 1: Customer Info ---
    y = _left(draw, y, "KHÁCH HÀNG", fs_title)
    y = _sep(draw, y)

    name = order.get("customerName", "") or order.get("customer_name", "")
    source = order.get("source", "") or ""
    source_vn = "Tại tiệm" if source == "walk_in" else source.replace("_", " ").title() if source else ""
    if name:
        y = _left(draw, y, f"Tên: {name}", fb)
    else:
        y = _left(draw, y, "Tên: Khách tại tiệm", fb)
    if source_vn:
        y = _left(draw, y, f"Nguồn: {source_vn}", fb)
    y += 4
    y = _double(draw, y)

    # --- Section 2: Order Item (table layout matching customer receipt) ---
    y = _left(draw, y, "SẢN PHẨM", fs_title)
    y = _sep(draw, y)

    # Table header
    col_sl = MARGIN + 320
    col_gia = MARGIN + 380
    col_tt = RECEIPT_WIDTH - MARGIN

    draw.text((MARGIN, y), "Sản phẩm", font=fbb, fill=(100, 100, 100))
    draw.text((col_sl, y), "SL", font=fbb, fill=(100, 100, 100))
    draw.text((col_gia, y), "Giá", font=fbb, fill=(100, 100, 100))
    tt_label = "T.Tiền"
    draw.text((col_tt - _tw(tt_label, fbb), y), tt_label, font=fbb, fill=(100, 100, 100))
    y += _th("SL", fbb) + LINE_GAP + 4
    y = _sep(draw, y)

    # Category name (bold, own line) above product row
    product = work_item.get("productName", "") or work_item.get("product_name", "")
    pid = work_item.get("productId", "") or work_item.get("product_id", "")
    if pid:
        cat_name_row = conn.execute(
            "SELECT c.name FROM products p JOIN categories c ON p.category = c.slug "
            "WHERE p.id = ? OR p.product_code = ?",
            (pid, pid),
        ).fetchone()
        if cat_name_row:
            y = _left(draw, y, cat_name_row["name"], fbb)

    # Product row with dotted leaders
    qty = work_item.get("quantity", 1)
    unit_price = float(work_item.get("unitPrice", 0) or work_item.get("unit_price", 0))
    total = qty * unit_price

    name_max_w = col_sl - MARGIN - 10
    name_lines = _wrap(product, fb, name_max_w) or [product]

    # First line: product name ....... SL ....... Giá ....... T.Tiền
    draw.text((MARGIN, y), name_lines[0], font=fb, fill=(0, 0, 0))
    name_end = MARGIN + _tw(name_lines[0], fb)
    _dots(draw, y, name_end, col_sl - 4, fs)
    qty_str = str(qty)
    draw.text((col_sl, y), qty_str, font=fb, fill=(0, 0, 0))
    sl_end = col_sl + _tw(qty_str, fb)
    if unit_price > 0:
        gia_str = _format_vnd(unit_price)
        tt_str = _format_vnd(total)
        tt_x = col_tt - _tw(tt_str, fbb)
        _dots(draw, y, sl_end, col_gia - 4, fs)
        draw.text((col_gia, y), gia_str, font=fb, fill=(0, 0, 0))
        gia_end = col_gia + _tw(gia_str, fb)
        _dots(draw, y, gia_end, tt_x - 4, fs)
        draw.text((tt_x, y), tt_str, font=fbb, fill=(0, 0, 0))
    else:
        _dots(draw, y, sl_end, col_tt - 4, fs)
    y += _th(name_lines[0], fb) + LINE_GAP

    # Remaining name lines (overflow)
    for nl in name_lines[1:]:
        draw.text((MARGIN, y), nl, font=fb, fill=(0, 0, 0))
        y += _th(nl, fb) + LINE_GAP

    # Birthday
    if work_item.get("isBirthday") or work_item.get("is_birthday"):
        age = work_item.get("age")
        age_suffix = f" SINH NHẬT{(' - ' + str(age) + ' tuổi') if age else ''}"
        y = _icon_text(draw, y, "\U0001F382", age_suffix, fbb, (180, 0, 0), x=MARGIN + 10)

    # Extra item badge
    if work_item.get("isExtra") or work_item.get("is_extra"):
        y = _icon_text(draw, y, "\U0001F4E6", "PHỤ LIỆU", fbb, (0, 100, 180), x=MARGIN + 10)

    # Photo — larger, centered
    if photo_bytes:
        photo_size = 192
        try:
            photo = Image.open(io.BytesIO(photo_bytes)).convert("RGB")
            photo.thumbnail((photo_size, photo_size), Image.LANCZOS)
            x_photo = (RECEIPT_WIDTH - photo.width) // 2
            img.paste(photo, (x_photo, y))
            draw.rectangle(
                [x_photo, y, x_photo + photo.width, y + photo.height],
                outline=(200, 200, 200),
            )
            y += photo.height + LINE_GAP
        except Exception:
            pass

    # Item notes
    notes = work_item.get("notes", "") or ""
    if notes:
        y = _left(draw, y, "Ghi chú:", fbb)
        for ln in _wrap(notes, fb, CONTENT_WIDTH):
            y = _left_mixed(draw, y, ln, fb, (80, 80, 80))

    y += 4
    y = _double(draw, y)

    # --- Section 3: Delivery ---
    y = _left(draw, y, "GIAO HÀNG", fs_title)
    y = _sep(draw, y)

    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    if due:
        due_str = f"Ngày giao: {due}"
        if due_time:
            due_str += f" {due_time}"
        y = _left(draw, y, due_str, fbb)

    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    _DTYPE_VN = {"pickup": "Nhận tại tiệm", "bus": "Gửi xe buýt", "door": "Giao tận nơi"}
    dtype_vn = _DTYPE_VN.get(dtype, dtype)
    y = _left(draw, y, f"Hình thức: {dtype_vn}", fb)

    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    if phone:
        y = _icon_text(draw, y, "\u260E", phone, fb)

    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    if dtype != "pickup" and daddr:
        y = _left(draw, y, "Địa chỉ:", fbb)
        for ln in _wrap(daddr, fs, CONTENT_WIDTH - 20):
            y = _left(draw, y, f"  {ln}", fs)

    # Order-level notes
    order_notes = order.get("notes", "") or ""
    if order_notes:
        y = _left(draw, y, "Ghi chú:", fbb)
        for ln in _wrap(order_notes, fb, CONTENT_WIDTH):
            y = _left_mixed(draw, y, ln, fb, (80, 80, 80))

    # Footer
    y += 4
    y = _double(draw, y)
    y = _center(draw, y, "--- Phiếu nội bộ ---", fs, (120, 120, 120))

    return img.crop((0, 0, RECEIPT_WIDTH, y + MARGIN))


def _render_bus_label(order, cfg) -> Image.Image:
    """Bus shipping label — landscape layout for 76×128mm label paper.

    Draws text in virtual landscape (1024×576), then rotates 90° CCW
    to produce a 576×1024 printer-ready image matching the label dimensions.
    """
    # Label: 76mm wide × 128mm long → 576×1024 dots at 203 DPI
    # Virtual landscape canvas: width=1024 (label length), height=576 (paper width)
    label_len = 1024  # 128mm × 8 dots/mm
    paper_w = RECEIPT_WIDTH  # 576 dots (72mm print area)
    margin = MARGIN

    img = Image.new("RGB", (label_len, paper_w), "white")
    draw = ImageDraw.Draw(img)

    content_w = label_len - 2 * margin  # text wrap area

    f_phone = _font(80, bold=True)
    f_addr = _font(64, bold=True)
    f_note = _font(40, bold=True)
    f_shop = _font(18)
    f_specialty = _font(16)

    def _draw_centered(yy, text, font, color=(0, 0, 0)):
        """Center text within label_len width. Return y after."""
        tw, th = _tw(text, font), _th(text, font)
        draw.text(((label_len - tw) // 2, yy), text, font=font, fill=color)
        return yy + th + LINE_GAP

    # --- Shop info: pre-calculate height, draw at bottom ---
    shop_name = cfg.get("receipt_shop_name", "")
    shop_specialty = cfg.get("receipt_shop_specialty", "")
    shop_phone = cfg.get("receipt_shop_phone", "")
    shop_addr = cfg.get("receipt_shop_address", "")

    shop_lines = []
    if shop_name:
        shop_lines.append((shop_name, f_shop))
    if shop_specialty:
        shop_lines.append((shop_specialty, f_specialty))
    if shop_phone:
        shop_lines.append((shop_phone, f_shop))
    if shop_addr:
        shop_lines.append((shop_addr, f_shop))

    shop_h = sum(_th(t, f) + LINE_GAP for t, f in shop_lines)
    sep_h = 16  # double line separator height

    # Draw shop info anchored to bottom
    sy = paper_w - margin - shop_h
    # Thick-thin double line separator
    draw.line([(margin, sy - sep_h), (label_len - margin, sy - sep_h)],
              fill=(0, 0, 0), width=3)
    draw.line([(margin, sy - sep_h + 6), (label_len - margin, sy - sep_h + 6)],
              fill=(0, 0, 0), width=1)
    for text, font in shop_lines:
        sy = _draw_centered(sy, text, font)

    # --- Main content: draw from top ---
    y = margin
    section_gap = 16  # extra spacing between phone / address / notes

    # Phone — largest, centered, bold
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    if phone:
        y = _draw_centered(y, phone, f_phone)
        y += section_gap

    # Address — large bold, centered, wrapped
    addr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    if addr:
        for ln in _wrap(addr, f_addr, content_w):
            y = _draw_centered(y, ln, f_addr)
        y += section_gap

    # Order notes — medium bold, centered, wrapped
    notes = order.get("notes", "") or ""
    if notes:
        for ln in _wrap(notes, f_note, content_w):
            y = _draw_centered(y, ln, f_note)

    # Rotate 90° CCW → 576 wide × 1024 tall (matches printer paper)
    rotated = img.transpose(Image.Transpose.ROTATE_90)

    return rotated


def _render_customer_receipt(order, cfg, conn, show_photos=True) -> Image.Image:
    """Customer receipt ('BIÊN NHẬN') — full details with photos per item."""
    work_items = order.get("workItems", [])
    order_id = order.get("id")

    # Taller canvas to accommodate photos
    img = Image.new("RGB", (RECEIPT_WIDTH, 4000), "white")
    draw = ImageDraw.Draw(img)

    fb = _font(_SZ_BODY)
    fbb = _font(_SZ_BODY, True)
    fs = _font(_SZ_SMALL)
    ft = _font(_SZ_TITLE, True)

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

    # --- Section 1: Customer Info ---
    y = _left(draw, y, "KHÁCH HÀNG", _font(_SZ_SUBTITLE, True))
    y = _sep(draw, y)

    name = order.get("customerName", "") or order.get("customer_name", "")
    if name:
        y = _left(draw, y, f"Tên: {name}", fb)
    y += 4
    y = _double(draw, y)

    # --- Section 2: Order Items ---
    y = _left(draw, y, "NỘI DUNG ĐƠN HÀNG", _font(_SZ_SUBTITLE, True))
    y = _sep(draw, y)

    # Table header
    col_sl = MARGIN + 320  # SL column
    col_gia = MARGIN + 380  # Giá column
    col_tt = RECEIPT_WIDTH - MARGIN  # Thành tiền (right-aligned)

    draw.text((MARGIN, y), "Sản phẩm", font=fbb, fill=(100, 100, 100))
    draw.text((col_sl, y), "SL", font=fbb, fill=(100, 100, 100))
    draw.text((col_gia, y), "Giá", font=fbb, fill=(100, 100, 100))
    tt_label = "T.Tiền"
    draw.text((col_tt - _tw(tt_label, fbb), y), tt_label, font=fbb, fill=(100, 100, 100))
    y += _th("SL", fbb) + LINE_GAP + 4
    y = _sep(draw, y)

    for i, item in enumerate(work_items):
        is_gift = item.get("isGift") or item.get("is_gift") or False
        item_name = item.get("productName", "") or item.get("product_name", "")
        if is_gift:
            item_name = f"{item_name} (Tặng)"
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        total = 0 if is_gift else qty * unit_price

        # Item row: name | SL | Giá | Thành tiền
        # Wrap product name within column width
        name_max_w = col_sl - MARGIN - 10
        name_lines = _wrap(item_name, fb, name_max_w) or [item_name]

        # First line: product name ....... SL ....... Giá ....... T.Tiền
        draw.text((MARGIN, y), name_lines[0], font=fb, fill=(0, 0, 0))
        name_end = MARGIN + _tw(name_lines[0], fb)
        _dots(draw, y, name_end, col_sl - 4, fs)
        qty_str = str(qty)
        draw.text((col_sl, y), qty_str, font=fb, fill=(0, 0, 0))
        sl_end = col_sl + _tw(qty_str, fb)
        if unit_price > 0:
            gia_str = _format_vnd(unit_price)
            tt_str = _format_vnd(total)
            tt_x = col_tt - _tw(tt_str, fbb)
            _dots(draw, y, sl_end, col_gia - 4, fs)
            draw.text((col_gia, y), gia_str, font=fb, fill=(0, 0, 0))
            gia_end = col_gia + _tw(gia_str, fb)
            _dots(draw, y, gia_end, tt_x - 4, fs)
            draw.text((tt_x, y), tt_str, font=fbb, fill=(0, 0, 0))
        else:
            _dots(draw, y, sl_end, col_tt - 4, fs)
        y += _th(name_lines[0], fb) + LINE_GAP

        # Remaining name lines (overflow)
        for nl in name_lines[1:]:
            draw.text((MARGIN, y), nl, font=fb, fill=(0, 0, 0))
            y += _th(nl, fb) + LINE_GAP

        # Birthday (sub-row)
        if item.get("isBirthday") or item.get("is_birthday"):
            age = item.get("age")
            age_suffix = f" SINH NHẬT{(' - ' + str(age) + ' tuổi') if age else ''}"
            y = _icon_text(draw, y, "\U0001F382", age_suffix, fbb, (180, 0, 0), x=MARGIN + 10)

        # Photo — only for cake-category products, larger + centered, display only
        item_id = item.get("id")
        product_id = item.get("productId", "") or item.get("product_id", "")
        is_cake = False
        if product_id:
            cat_row = conn.execute(
                "SELECT category FROM products WHERE id = ? OR product_code = ?",
                (product_id, product_id),
            ).fetchone()
            if cat_row and cat_row["category"] in ("cake", "banh_kem"):
                is_cake = True
        photo_size = 192  # larger than default 128
        if show_photos and is_cake and order_id and item_id:
            photo_bytes = _get_photo(conn, order_id, item_id)
            if photo_bytes:
                try:
                    photo = Image.open(io.BytesIO(photo_bytes)).convert("RGB")
                    photo.thumbnail((photo_size, photo_size), Image.LANCZOS)
                    x_photo = (RECEIPT_WIDTH - photo.width) // 2
                    img.paste(photo, (x_photo, y))
                    draw.rectangle(
                        [x_photo, y, x_photo + photo.width, y + photo.height],
                        outline=(200, 200, 200),
                    )
                    y += photo.height + LINE_GAP
                except Exception:
                    pass

        # Notes/remarks (sub-row, indented, bold label + body font, mixed emoji)
        notes = item.get("notes", "") or ""
        if notes:
            full = f"  Ghi chú: {notes}"
            if "\n" not in notes and _mixed_tw(full, fb) <= CONTENT_WIDTH:
                y = _left(draw, y, "  Ghi chú: ", fbb, (80, 80, 80))
                y -= _th("Ghi chú:", fbb) + LINE_GAP  # back up
                _draw_mixed(draw, MARGIN + _tw("  Ghi chú: ", fbb), y, notes, fb, (80, 80, 80))
                y += _th("A", fb) + _NOTE_LINE_GAP
            else:
                y = _left(draw, y, "  Ghi chú:", fbb, (80, 80, 80))
                for ln in _wrap(notes, fb, CONTENT_WIDTH - 20):
                    y = _left_mixed(draw, y, f"    {ln}", fb, (80, 80, 80))

        # Separator between items
        if i < len(work_items) - 1:
            y = _sep(draw, y)

    y += 4
    y = _double(draw, y)

    # --- Financial Summary ---
    # Calculate subtotal (non-gift items only)
    subtotal = sum(
        item.get("quantity", 1) * float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        for item in work_items
        if not (item.get("isGift") or item.get("is_gift"))
    )
    shipping_fee = float(order.get("shippingFee", 0) or order.get("shipping_fee", 0))
    total_price = float(order.get("totalPrice", 0) or order.get("total_price", 0))

    y = _row(draw, y, "Tạm tính:", _format_vnd_full(subtotal), fbb)
    if shipping_fee > 0:
        y = _row(draw, y, "Phí giao hàng:", _format_vnd_full(shipping_fee), fbb)
        y = _row(draw, y, "Tổng cộng:", _format_vnd_full(total_price), fbb)
    else:
        y = _row(draw, y, "Tổng cộng:", _format_vnd_full(total_price), fbb)

    order_id = order.get("id")
    total_paid = PaymentTransaction.total_for_order(conn, order_id) if order_id else 0.0
    remaining = total_price - total_paid

    y = _row(draw, y, "Đã thanh toán:", _format_vnd_full(total_paid), fb, color_v=(0, 100, 0))
    if remaining > 0:
        y = _row(draw, y, "Còn lại:", _format_vnd_full(remaining), fbb, color_v=(180, 0, 0))
    else:
        y = _row(draw, y, "Còn lại:", "0đ", fb, color_v=(0, 100, 0))
    y += 4
    y = _double(draw, y)

    # --- Section 3: Delivery ---
    y = _left(draw, y, "GIAO HÀNG", _font(_SZ_SUBTITLE, True))
    y = _sep(draw, y)

    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    if due:
        due_str = f"Ngày nhận: {due}"
        if due_time:
            due_str += f" {due_time}"
        y = _left(draw, y, due_str, fbb)

    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    _DTYPE_VN = {"pickup": "Nhận tại tiệm", "bus": "Gửi xe buýt", "door": "Giao tận nơi"}
    dtype_vn = _DTYPE_VN.get(dtype, dtype)
    y = _left(draw, y, f"Hình thức: {dtype_vn}", fb)

    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    if phone:
        y = _icon_text(draw, y, "\u260E", phone, fb)

    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    if dtype != "pickup" and daddr:
        y = _left(draw, y, f"Địa chỉ:", fbb)
        for ln in _wrap(daddr, fs, CONTENT_WIDTH - 20):
            y = _left(draw, y, f"  {ln}", fs)

    # Order-level notes
    order_notes = order.get("notes", "") or ""
    if order_notes:
        y = _left(draw, y, "Ghi chú:", fbb)
        for ln in _wrap(order_notes, fb, CONTENT_WIDTH):
            y = _left_mixed(draw, y, ln, fb, (80, 80, 80))

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
    """Get first photo bytes attached to a specific work item only."""
    row = conn.execute(
        "SELECT hash FROM photos p JOIN order_photos op ON p.id = op.photo_id "
        "WHERE op.order_id = ? AND op.work_item_id = ? LIMIT 1",
        (order_id, work_item_id),
    ).fetchone()
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
    photos: bool = Query(True, description="Include photos (set false for print version)"),
):
    """Generate receipt image as PNG.

    - type=work_ticket: internal receipt (Phiếu Nội Bộ), single item, requires item_id
    - type=customer: clean customer-facing receipt (BIÊN NHẬN)
    - type=bus_label: bus shipping label — phone, address, notes, rotated landscape
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
            img = _render_work_ticket(detail, work_item, cfg, photo, conn)
        elif type == "customer":
            img = _render_customer_receipt(detail, cfg, conn, show_photos=photos)
        elif type == "bus_label":
            img = _render_bus_label(detail, cfg)
        else:
            raise HTTPException(status_code=400, detail="Invalid type: work_ticket, customer, or bus_label")

        buf = io.BytesIO()
        img.save(buf, format="PNG", quality=95)
        buf.seek(0)

        return StreamingResponse(
            iter([buf.getvalue()]),
            media_type="image/png",
            headers={"Content-Disposition": f"inline; filename=receipt-{ref}-{type}.png"},
        )
