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
from baker.formatters import format_phone
from baker.models.payment_transaction import PaymentTransaction
from baker.usb_printer import get_paper_mode

router = APIRouter(prefix="/api/orders", tags=["receipts"])

# --- Constants ---

RECEIPT_WIDTH = 576  # 80mm at 203 DPI (76mm print area)
RECEIPT_MAX_HEIGHT = 1040  # 130mm at 203 DPI — height cap for work_ticket/customer receipts
MARGIN = 20
CONTENT_WIDTH = RECEIPT_WIDTH - 2 * MARGIN
THUMBNAIL_SIZE = 128
LINE_GAP = 4  # DG-228 Phase 2: reduced from 6 for vertical compaction
_SZ_FOOTER = 14  # DG-228 Phase 3 / FR-6: "Trang N/M" footer marker font (metadata-only exception to 16pt floor)

# Font sizes (optimized for 203 DPI thermal print)
_SZ_TITLE = 32
_SZ_SUBTITLE = 24
_SZ_BODY = 20
_SZ_SMALL = 16

# Font sizes for new internal receipt layout (readability from ~2m)
_SZ_HUGE = 40       # due date at bottom (unused — 36pt used instead)
_SZ_BIG = 36        # customer name, category, price, due date
_SZ_MEDIUM = 28     # notes text, birthday
_SZ_NORMAL = 24     # product name, section headers, title

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


def _tien_rut_received(conn, order_id: int) -> float:
    """Sum of tien_rut transactions for an order."""
    row = conn.execute(
        "SELECT COALESCE(SUM(amount), 0) FROM payment_transactions WHERE order_id = ? AND type = 'tien_rut'",
        (order_id,),
    ).fetchone()
    return float(row[0]) if row else 0.0


def _tien_rut_target(work_items: list) -> float:
    """Sum of cash_amount across all tien_rut items in an order."""
    total = 0.0
    for item in work_items:
        attrs = item.get("attributes") or {}
        if attrs.get("rut_tien") == "true":
            cash_amount = attrs.get("cash_amount")
            if cash_amount:
                total += float(cash_amount)
    return total


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
    y += 8  # DG-228 Phase 2: reduced pre-separator padding (was 12)
    draw.line([(MARGIN, y), (RECEIPT_WIDTH - MARGIN, y)], fill=(160, 160, 160), width=1)
    return y + 10  # DG-228 Phase 2: reduced post-separator padding (was 14)


def _double(draw, y):
    """Double separator line."""
    y += 14  # padding above
    draw.line([(MARGIN, y), (RECEIPT_WIDTH - MARGIN, y)], fill=(0, 0, 0), width=1)
    draw.line([(MARGIN, y + 4), (RECEIPT_WIDTH - MARGIN, y + 4)], fill=(0, 0, 0), width=1)
    return y + 18  # padding below


def _thick(draw, y):
    """Thick separator for major sections."""
    y += 14  # padding above
    draw.line([(MARGIN, y), (RECEIPT_WIDTH - MARGIN, y)], fill=(0, 0, 0), width=3)
    return y + 16  # padding below


def _add_tear_indicator(img, draw, y, paper_mode):
    """Add horizontal dashed tear indicator line for continuous roll paper.

    When paper_mode is "roll", adds a visual gap (>=64 dots / 8mm) below the
    last content line and draws a dashed horizontal line spanning CONTENT_WIDTH.
    Returns the new y position after the tear indicator area. When paper_mode
    is not "roll", returns y unchanged (label mode = no tear indicator).

    Args:
        img: PIL Image (unused, kept for API consistency).
        draw: PIL ImageDraw.
        y: Current y position (bottom of last content line).
        paper_mode: "label" or "roll".

    Returns:
        New y position after tear indicator area (or unchanged y for label mode).
    """
    if paper_mode != "roll":
        return y
    gap = 64  # 8mm vertical gap (NFR2: >=8mm = >=64 dots)
    y += gap
    dash = 4
    space = 4
    color = (100, 100, 100)
    x = MARGIN
    end_x = RECEIPT_WIDTH - MARGIN
    while x < end_x:
        x2 = min(x + dash, end_x)
        draw.line([(x, y), (x2, y)], fill=color, width=1)
        x += dash + space
    return y


def _find_content_bottom(img):
    """Find the y-coordinate just after the bottommost non-white pixel.

    Returns 0 if the image is entirely white.
    """
    inverted = img.point(lambda p: 255 - p)
    bbox = inverted.getbbox()
    return bbox[3] + 1 if bbox else 0


def _find_split_boundaries(img, max_h: int) -> list:
    """Find natural section-break y-coordinates suitable as page split points.

    Scans the image for horizontal rows that are entirely white (content gaps)
    and returns a list of candidate y-coordinates. These are rows where the
    receipt has vertical whitespace, so splitting there keeps sections intact
    on each page. Only rows in the range [MARGIN, content_bottom - MARGIN] are
    considered; the very top and bottom are excluded to avoid degenerate splits.
    """
    inverted = img.point(lambda p: 255 - p)
    bbox = inverted.getbbox()
    if not bbox:
        return []
    content_bottom = bbox[3] + 1
    if content_bottom <= max_h:
        return []

    # Scan each row; a row is a "gap" if it is entirely white across content width.
    gap_rows = []
    px = img.load()
    for y in range(MARGIN, content_bottom - MARGIN):
        is_gap = True
        for x in range(MARGIN, RECEIPT_WIDTH - MARGIN):
            if px[x, y] != (255, 255, 255):
                is_gap = False
                break
        if is_gap:
            gap_rows.append(y)

    if not gap_rows:
        return []

    # Collapse consecutive gap rows into a single midpoint boundary.
    boundaries = []
    run_start = gap_rows[0]
    prev = gap_rows[0]
    for y in gap_rows[1:]:
        if y == prev + 1:
            prev = y
        else:
            boundaries.append((run_start + prev) // 2)
            run_start = y
            prev = y
    boundaries.append((run_start + prev) // 2)
    return boundaries


def _split_pages(img: Image.Image) -> list:
    """Split a receipt image into pages each no taller than RECEIPT_MAX_HEIGHT.

    Divides the image at natural section boundaries (horizontal whitespace gaps)
    when the content exceeds the cap. Each page is cropped to its content and a
    "Trang N/M" footer marker (14pt, centered) is drawn on every page when more
    than one page results. When the content fits within the cap, a single page is
    returned with no footer.

    The footer marker occupies a small band below the content; the content portion
    of each page is sized so content + footer together stay within RECEIPT_MAX_HEIGHT.

    Returns:
        list[PIL.Image.Image]: one or more receipt page images (each width=RECEIPT_WIDTH).
    """
    content_bottom = _find_content_bottom(img)
    if content_bottom == 0:
        return [img.crop((0, 0, RECEIPT_WIDTH, MARGIN))]

    footer_font = _font(_SZ_FOOTER)
    footer_marker_h = _th("Trang", footer_font)
    footer_band_h = footer_marker_h + 12  # marker + small padding above/below
    # Content budget per page: leave room for the footer band within the cap.
    content_budget = RECEIPT_MAX_HEIGHT - footer_band_h

    # Single page — content fits within the cap (footer only added on multi-page).
    if content_bottom <= RECEIPT_MAX_HEIGHT:
        return [img.crop((0, 0, RECEIPT_WIDTH, content_bottom))]

    # Multi-page: divide at natural section boundaries.
    boundaries = _find_split_boundaries(img, RECEIPT_MAX_HEIGHT)
    # CQ-1: greedy pack tracking the last boundary that fits within the budget.
    # Previously the loop only split when boundary - page_start == budget exactly,
    # so any boundary strictly beyond the budget caused a hard cut through text
    # rows and any boundary before the budget was forgotten — effectively never
    # splitting at natural section breaks. Now we remember the last in-budget
    # boundary and split there, falling back to a hard cut only when no
    # boundary fits in the window. The final tail is also re-checked: any
    # oversized segment (including the tail) is hard-cut to stay within budget.
    pages: list = []
    page_start = 0
    idx = 0
    n = len(boundaries)
    while page_start < content_bottom:
        limit = page_start + content_budget
        if limit >= content_bottom:
            # Remaining content fits within one page.
            pages.append((page_start, content_bottom))
            break
        # Find the last boundary within [page_start, limit].
        last_fit = None
        while idx < n and boundaries[idx] <= limit:
            last_fit = boundaries[idx]
            idx += 1
        if last_fit is not None and last_fit > page_start:
            pages.append((page_start, last_fit))
            page_start = last_fit
            # next iteration resumes from the same idx (boundaries are sorted
            # and strictly increasing; the next boundary is beyond `limit`).
        else:
            # No boundary fits in the window — hard cut at the budget.
            pages.append((page_start, limit))
            page_start = limit

    total_pages = len(pages)
    result = []
    for idx, (start, end) in enumerate(pages):
        content_img = img.crop((0, start, RECEIPT_WIDTH, end))
        marker = f"Trang {idx + 1}/{total_pages}"
        # Append a white footer band below the content and draw the marker centered.
        page_h = content_img.height + footer_band_h
        page_img = Image.new("RGB", (RECEIPT_WIDTH, page_h), "white")
        page_img.paste(content_img, (0, 0))
        draw = ImageDraw.Draw(page_img)
        footer_y = content_img.height + 6
        _center(draw, footer_y, marker, footer_font, color=(100, 100, 100))
        result.append(page_img)
    return result


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


def _draw_wrapped(draw, y, text, font, max_w, align="left", prefix="") -> int:
    """Wrap ``text`` to ``max_w`` then draw each line, returning y after.

    CQ-7: consolidates the wrap-then-draw idiom duplicated across five sites.

    When ``prefix`` is provided, it is prepended to the first wrapped line only
    and the first line's wrap width is reduced by the prefix width so the
    prefix + first line fits within ``max_w`` (the address-variant behavior).

    ``align`` may be "left" (drawn at MARGIN via ``_left``) or "center"
    (drawn centered via ``_center``).
    """
    if not text and not prefix:
        return y
    if prefix:
        first_w = max_w - _tw(prefix, font)
        lines = _wrap(text, font, first_w) or [text]
        if align == "center":
            y = _center(draw, y, f"{prefix}{lines[0]}", font)
        else:
            y = _left(draw, y, f"{prefix}{lines[0]}", font)
        for ln in lines[1:]:
            if align == "center":
                y = _center(draw, y, ln, font)
            else:
                y = _left(draw, y, ln, font)
    else:
        lines = _wrap(text, font, max_w) or [text]
        for ln in lines:
            if align == "center":
                y = _center(draw, y, ln, font)
            else:
                y = _left(draw, y, ln, font)
    return y


def _cash_fee_amount(item: dict) -> float:
    """Return the ``cash_fee`` amount for an item, or 0.0 when missing/malformed.

    CQ-6: tolerates arbitrary client-supplied ``attributes`` values without
    raising ValueError/TypeError, so a malformed ``cash_fee`` cannot cause
    an HTTP 500 during receipt rendering. Only returns a non-zero amount
    when the item has ``rut_tien == "true"`` and a parseable numeric fee.
    """
    attrs = item.get("attributes") or {}
    if attrs.get("rut_tien") != "true":
        return 0.0
    raw = attrs.get("cash_fee")
    if not raw:
        return 0.0
    try:
        return float(raw)
    except (TypeError, ValueError):
        return 0.0


def _ensure_canvas_capacity(img: Image.Image, draw: ImageDraw.ImageDraw,
                            y: int, headroom: int = 200) -> tuple:
    """Grow ``img`` vertically if ``y + headroom`` would exceed the canvas.

    CQ-3: the work-ticket (2000px) and customer-receipt (4000px) canvases are
    fixed-height, but page splitting now makes tall content a supported case.
    When a long note pushes the cursor past the canvas, PIL silently discards
    `draw.text` beyond the canvas and the later crop fills the missing region
    with solid black, producing solid-black printed labels. This helper grows
    the canvas (doubling until it fits) and blits the existing content into the
    top of the new canvas so no text is lost. Returns ``(new_img, new_draw)`` —
    callers must rebind their local ``img``/``draw`` references.
    """
    needed = y + headroom
    if needed <= img.height:
        return img, draw
    new_h = img.height
    while new_h < needed:
        new_h *= 2
    new_img = Image.new("RGB", (RECEIPT_WIDTH, new_h), "white")
    new_img.paste(img, (0, 0))
    new_draw = ImageDraw.Draw(new_img)
    return new_img, new_draw


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


def _enum_attribute_labels(conn) -> dict:
    """Map enum attribute_type → label_vi for receipt rendering."""
    rows = conn.execute(
        "SELECT attribute_type, label_vi FROM product_attributes WHERE value_type = 'enum'"
    ).fetchall()
    return {r["attribute_type"]: r["label_vi"] for r in rows}


def _enum_attribute_lines(item: dict, labels: dict) -> list:
    """Extract enum attribute lines as `[(label_vi, value_vi), ...]` for an item.

    Each enum attribute renders on its own line per Q3 / R3 (32-char-width concern).
    Returns empty list when no enum attributes are set on this item.
    """
    attrs = item.get("attributes") or {}
    out = []
    for attribute_type, label_vi in labels.items():
        value = attrs.get(attribute_type)
        if value is None:
            continue
        s = str(value).strip()
        if not s:
            continue
        out.append((label_vi, s))
    return out


def _wrapped_enum_attribute_lines(item: dict, labels: dict, font, max_w: int) -> list:
    """Build receipt-safe wrapped enum attribute lines for an item."""
    lines = []
    for label_vi, value_vi in _enum_attribute_lines(item, labels):
        text = f"{label_vi}: {value_vi}"
        lines.extend(_wrap(text, font, max_w) or [text])
    return lines


def _order_public_code(order: dict) -> str:
    """Return trimmed public order code or empty string."""
    public_code = order.get("publicOrderCode", "") or order.get("public_order_code", "") or ""
    return str(public_code).strip()


def _order_ref_value(order: dict) -> str:
    """Return trimmed internal order ref or empty string."""
    order_ref = order.get("orderRef", "") or order.get("order_ref", "") or ""
    return str(order_ref).strip()


def _order_visual_ref(order: dict) -> str:
    """Public code first, fallback to internal order ref for old orders."""
    public_code = _order_public_code(order)
    if public_code:
        return public_code
    return _order_ref_value(order)


def _main_item_index_total(order: dict, work_item: dict) -> tuple:
    """Return (1-based index, total) of work_item among main (non-extra/non-gift) items.

    DG-228 Phase 3 / FR-3: used to merge the sub-item index into the work ticket ref
    line. Extras and gifts are excluded from the numbering so production staff see
    only the count of main production items. Returns (None, None) when the work_item
    is not found among main items (e.g., it is itself an extra/gift) so the caller
    omits the suffix.
    """
    work_items = order.get("workItems", []) or []
    main_items = [
        wi for wi in work_items
        if not (wi.get("isExtra") or wi.get("is_extra")
                or wi.get("isGift") or wi.get("is_gift"))
    ]
    if len(main_items) <= 1:
        return None, None
    target_id = work_item.get("id")
    for idx, wi in enumerate(main_items, start=1):
        if str(wi.get("id")) == str(target_id):
            return idx, len(main_items)
    return None, None


def _customer_name_value(order: dict) -> str:
    """Return trimmed customer name or empty string."""
    raw_name = order.get("customerName", "") or order.get("customer_name", "") or ""
    return str(raw_name).strip()


def _customer_last_word(order: dict) -> str:
    """Return the last word from customer name, or empty if unavailable."""
    name = _customer_name_value(order)
    if not name:
        return ""
    parts = name.split()
    return parts[-1] if parts else ""


def _customer_reference_text(order: dict) -> str:
    """Customer-facing reference line for receipts."""
    public_code = _order_public_code(order)
    if not public_code:
        return f"Mã đơn: {_order_ref_value(order)}"
    last_word = _customer_last_word(order)
    if last_word:
        return f"Mã nhận bánh: {last_word} - {public_code}"
    return f"Mã nhận bánh: {public_code}"


def _customer_heading_text(order: dict) -> str:
    """Customer heading line for customer receipts."""
    name = _customer_name_value(order)
    return name or "KHÁCH HÀNG"


def _shop_delivery_code_text(order: dict) -> str:
    """Prominent pickup code content for shop/delivery receipts."""
    public_code = _order_public_code(order)
    if public_code:
        last_word = _customer_last_word(order)
        if last_word:
            return f"{last_word} - {public_code}"
        return public_code
    return _order_ref_value(order)


def _draw_compact_reference_box(draw, y: int, text: str, font) -> int:
    """Draw a compact bordered box around reference text."""
    lines = _wrap(text, font, CONTENT_WIDTH - 48) or [text]
    text_width = 0
    text_height = 0
    for line in lines:
        text_width = max(text_width, _tw(line, font))
        text_height += _th(line, font) + LINE_GAP

    pad_x = 22
    pad_y = 14
    box_w = min(CONTENT_WIDTH, text_width + (pad_x * 2))
    box_h = text_height + (pad_y * 2)
    box_x = MARGIN + (CONTENT_WIDTH - box_w) // 2

    draw.rectangle([box_x, y, box_x + box_w, y + box_h], outline=(0, 0, 0), width=3)

    text_y = y + pad_y
    for line in lines:
        text_x = box_x + (box_w - _tw(line, font)) // 2
        draw.text((text_x, text_y), line, font=font, fill=(0, 0, 0))
        text_y += _th(line, font) + LINE_GAP

    return y + box_h


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

def _render_work_ticket(order, work_item, cfg, photo_bytes, conn, paper_mode="label",
                        item_index: Optional[int] = None,
                        item_total: Optional[int] = None) -> Image.Image:
    """Internal receipt (Phiếu Nội Bộ) for production staff — single item per receipt.

    New layout: delivery on top, product info BIG, notes prominent, bottom boxes for
    customer name/source and due date/time. NO photo, NO table format.

    When item_index and item_total are provided (multi-item order), the order ref
    line merges the sub-item index per FR-3: "Mã: <ref> (n/m)".
    """
    img = Image.new("RGB", (RECEIPT_WIDTH, 2000), "white")
    draw = ImageDraw.Draw(img)

    BOX_PAD = 8       # padding inside bottom boxes
    BOX_GAP = 10     # gap between the two bottom boxes
    BOX_STROKE = 2   # box border width

    fb = _font(_SZ_BODY)
    fbb = _font(_SZ_BODY, True)
    fs = _font(_SZ_SMALL)
    fbig = _font(_SZ_BIG, True)
    fnormal = _font(_SZ_NORMAL, True)
    fproduct = _font(_SZ_NORMAL)

    y = MARGIN

    # ── Header: title + order ref + date (compact) ──
    y = _center(draw, y, "PHIẾU NỘI BỘ", fnormal)

    ref = _order_visual_ref(order)
    created = order.get("createdAt", "") or order.get("created_at", "")
    # DG-228 Phase 3 / FR-3: merge sub-item index into the ref line for multi-item orders.
    header_line = f"Mã: {ref}"
    if item_index is not None and item_total is not None and item_total > 1:
        header_line += f" ({item_index}/{item_total})"
    if created:
        header_line += f"  •  {created[:10]}"
    y = _center(draw, y, header_line, fs)
    y += 10

    # ── Delivery section (on top) ──
    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    _DTYPE_VN = {"pickup": "Nhận tại tiệm", "bus": "Gửi xe buýt", "door": "Giao tận nơi"}
    dtype_vn = _DTYPE_VN.get(dtype, dtype)

    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""

    y = _left(draw, y, f"GIAO HÀNG:  {dtype_vn}", fnormal)

    if phone:
        y = _icon_text(draw, y, "\u260E", format_phone(phone), fb)

    if dtype != "pickup" and daddr:
        y = _draw_wrapped(draw, y, daddr, fb, CONTENT_WIDTH, align="left", prefix="Địa chỉ: ")

    y = _double(draw, y)

    # ── Product section (BIG: category, name, qty + price) ──
    pid = work_item.get("productId", "") or work_item.get("product_id", "")
    if pid:
        cat_name_row = conn.execute(
            "SELECT c.name FROM products p JOIN categories c ON p.category = c.slug "
            "WHERE p.id = ? OR p.product_code = ?",
            (pid, pid),
        ).fetchone()
        if cat_name_row:
            y = _draw_wrapped(draw, y, cat_name_row["name"].upper(), fbig, CONTENT_WIDTH)

    product = work_item.get("productName", "") or work_item.get("product_name", "")
    y = _draw_wrapped(draw, y, product, fproduct, CONTENT_WIDTH)

    qty = work_item.get("quantity", 1)
    unit_price = float(work_item.get("unitPrice", 0) or work_item.get("unit_price", 0))

    # Qty and unit price on same line, both BIG
    qty_price = f"SL: {qty}"
    if unit_price > 0:
        qty_price += f"     {_format_vnd(unit_price)}"
    y = _left(draw, y, qty_price, fbig)

    # Birthday badge
    if work_item.get("isBirthday") or work_item.get("is_birthday"):
        age = work_item.get("age")
        age_text = f" SINH NHẬT"
        if age and age != 999:
            age_text += f" - {age} tuổi"
        ef = _emoji_font(_SZ_MEDIUM)
        tf = _font(_SZ_MEDIUM, True)
        icon = "\U0001F382"
        icon_w = _tw(icon, ef)
        draw.text((MARGIN, y), icon, font=ef, fill=(180, 0, 0))
        draw.text((MARGIN + icon_w + 4, y), age_text, font=tf, fill=(180, 0, 0))
        y += max(_th(icon, ef), _th(age_text, tf)) + LINE_GAP

    # Cash-in-cake badge (rut tien) — amount on work ticket (fee is in summary)
    attrs = work_item.get("attributes") or {}
    cash_amount = attrs.get("cash_amount")
    if attrs.get("rut_tien") == "true" and cash_amount and int(float(cash_amount)) > 0:
        ef = _emoji_font(_SZ_MEDIUM)
        tf = _font(_SZ_MEDIUM, True)
        icon = "\U0001F4B0"
        icon_w = _tw(icon, ef)
        amount_str = _format_vnd_full(float(cash_amount))
        draw.text((MARGIN, y), icon, font=ef, fill=(0, 128, 0))
        draw.text((MARGIN + icon_w + 4, y), f" Số tiền rút: {amount_str}", font=tf, fill=(0, 128, 0))
        y += max(_th(icon, ef), _th(f" Số tiền rút: {amount_str}", tf)) + LINE_GAP
        # Rut tien transaction summary (received vs target)
        order_id = order.get("id")
        rut_received = _tien_rut_received(conn, order_id) if order_id else 0.0
        if rut_received >= float(cash_amount):
            status_text = f"    Đã nhận: {_format_vnd_full(rut_received)}"
            status_color = (0, 128, 0)
        else:
            status_text = f"    Đã nhận: {_format_vnd_full(rut_received)} / {amount_str}"
            status_color = (200, 0, 0)
        draw.text((MARGIN, y), status_text, font=tf, fill=status_color)
        y += _th(status_text, tf) + LINE_GAP

    # Extra item badge
    if work_item.get("isExtra") or work_item.get("is_extra"):
        ef = _emoji_font(_SZ_MEDIUM)
        tf = _font(_SZ_MEDIUM, True)
        icon = "\U0001F4E6"
        icon_w = _tw(icon, ef)
        draw.text((MARGIN, y), icon, font=ef, fill=(0, 100, 180))
        draw.text((MARGIN + icon_w + 4, y), " PHỤ LIỆU", font=tf, fill=(0, 100, 180))
        y += max(_th(icon, ef), _th(" PHỤ LIỆU", tf)) + LINE_GAP

    # Enum attribute lines — each on its own row (Q3 / R3)
    enum_labels = _enum_attribute_labels(conn)
    enum_font = _font(_SZ_MEDIUM, True)
    for line in _wrapped_enum_attribute_lines(work_item, enum_labels, enum_font, CONTENT_WIDTH):
        y = _left(draw, y, line, enum_font)

    # Spacer between badge(s) and next section
    y += 10
    y = _double(draw, y)

    # ── Notes section (BIG, prominent) ──
    notes = work_item.get("notes", "") or ""
    order_notes = order.get("notes", "") or ""

    if notes or order_notes:
        # CQ-3: grow the canvas before drawing long notes so the cursor never
        # runs past the fixed 2000px canvas (which would silently discard text
        # and append a solid-black band to the cropped output).
        img, draw = _ensure_canvas_capacity(img, draw, y, headroom=max(len(notes), len(order_notes)) * 30)
        y = _left(draw, y, "GHI CHÚ", fnormal)
        y = _sep(draw, y)

        note_font = _font(_SZ_MEDIUM)
        if notes:
            for ln in _wrap(notes, note_font, CONTENT_WIDTH):
                y = _left_mixed(draw, y, ln, note_font)
                img, draw = _ensure_canvas_capacity(img, draw, y)

        if order_notes:
            if notes:
                y += 4
                y = _sep(draw, y)
            y = _left(draw, y, "Ghi chú đơn:", _font(_SZ_BODY, True), (100, 100, 100))
            for ln in _wrap(order_notes, note_font, CONTENT_WIDTH):
                y = _left_mixed(draw, y, ln, note_font, (80, 80, 80))
                img, draw = _ensure_canvas_capacity(img, draw, y)

    # ── Extras and Payment section (between notes and bottom boxes) ──
    work_items = order.get("workItems", [])
    extras = [
        wi for wi in work_items
        if wi.get("isExtra") or wi.get("is_extra") or wi.get("isGift") or wi.get("is_gift")
    ]
    main_count = len(work_items) - len(extras)

    # List extras if any
    if extras:
        y = _left(draw, y, "Phụ liệu kèm theo:", fnormal)
        for ex in extras:
            ex_name = ex.get("productName", "") or ex.get("product_name", "") or "N/A"
            ex_qty = ex.get("quantity", 1)
            y = _left(draw, y, f"  {ex_name} x{ex_qty}", fb)

    # Payment section — only when exactly 1 main item
    if main_count == 1:
        total_price = float(order.get("totalPrice", 0) or order.get("total_price", 0))
        order_id = order.get("id")
        total_paid = PaymentTransaction.total_paid_excl_outflows(conn, order_id) if order_id else 0.0
        remaining = total_price - total_paid

        y = _row(draw, y, "Tổng cộng:", _format_vnd_full(total_price), fbb)
        # Rut tien transaction summary
        rut_target = _tien_rut_target(work_items)
        if rut_target > 0 and order_id:
            rut_recv = _tien_rut_received(conn, order_id)
            rut_color = (0, 100, 0) if rut_recv >= rut_target else (200, 0, 0)
            y = _row(draw, y, "Tiền rút đã nhận:", f"{_format_vnd_full(rut_recv)} / {_format_vnd_full(rut_target)}", fb, color_v=rut_color)
        y = _row(draw, y, "Đã thanh toán:", _format_vnd_full(total_paid), fb, color_v=(0, 100, 0))
        if remaining > 0:
            y = _row(draw, y, "Còn lại:", _format_vnd_full(remaining), fbb, color_v=(180, 0, 0))
        else:
            y = _row(draw, y, "Còn lại:", "0đ", fb, color_v=(0, 100, 0))

    y = _thick(draw, y)

    # ── Bottom: Two side-by-side boxes [Customer + Source] | [Due Date/Time] ──
    half_w = (RECEIPT_WIDTH - 2 * MARGIN - BOX_GAP) // 2
    box_left_x = MARGIN
    box_right_x = MARGIN + half_w + BOX_GAP

    # --- Measure left box content: customer name + source ---
    name = order.get("customerName", "") or order.get("customer_name", "") or "Khách tại tiệm"
    source = order.get("source", "") or ""
    source_vn = ""
    if source:
        source_vn = "Tại tiệm" if source == "walk_in" else source.replace("_", " ").replace("-", " ").title()
    source_font = _font(_SZ_BODY)  # half of name size, black

    name_lines = _wrap(name, fbig, half_w - 2 * BOX_PAD) or [name]
    left_h = BOX_PAD
    for ln in name_lines:
        left_h += _th(ln, fbig) + LINE_GAP
    if source_vn:
        left_h += _th(source_vn, source_font) + LINE_GAP
    left_h += BOX_PAD

    # --- Measure right box content: due date/time ---
    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    due_short = ""
    if due:
        parts = due.split("-")
        if len(parts) == 3:
            due_short = f"{parts[2]}/{parts[1]}"
        else:
            due_short = due

    due_font = fbig
    time_font = fbig

    right_h = BOX_PAD
    if due_short:
        right_h += _th(due_short, due_font) + LINE_GAP
    if due_time:
        right_h += _th(due_time, time_font) + LINE_GAP
    elif not due_short:
        right_h += _th("N/A", fb) + LINE_GAP
    right_h += BOX_PAD

    box_h = max(left_h, right_h)

    # Draw left box (customer)
    draw.rectangle(
        [box_left_x, y, box_left_x + half_w, y + box_h],
        outline=(0, 0, 0), width=BOX_STROKE,
    )
    ty = y + BOX_PAD
    for ln in name_lines:
        draw.text((box_left_x + BOX_PAD, ty), ln, font=fbig, fill=(0, 0, 0))
        ty += _th(ln, fbig) + LINE_GAP
    if source_vn:
        draw.text((box_left_x + BOX_PAD, ty), source_vn, font=source_font, fill=(0, 0, 0))

    # Draw right box (due date/time)
    draw.rectangle(
        [box_right_x, y, box_right_x + half_w, y + box_h],
        outline=(0, 0, 0), width=BOX_STROKE,
    )
    right_content_h = 0
    if due_short:
        right_content_h += _th(due_short, due_font) + LINE_GAP
    if due_time:
        right_content_h += _th(due_time, time_font) + LINE_GAP
    ty = y + (box_h - right_content_h) // 2
    if due_short:
        dw = _tw(due_short, due_font)
        draw.text((box_right_x + (half_w - dw) // 2, ty), due_short, font=due_font, fill=(0, 0, 0))
        ty += _th(due_short, due_font) + LINE_GAP
    if due_time:
        tw = _tw(due_time, time_font)
        draw.text((box_right_x + (half_w - tw) // 2, ty), due_time, font=time_font, fill=(0, 0, 0))

    y += box_h + 10

    bottom_ref = _order_public_code(order) or _order_ref_value(order)
    if bottom_ref:
        y = _left(draw, y, bottom_ref, fbig)

    y += MARGIN

    # Tear indicator for roll mode (DG-184 Phase 2)
    y = _add_tear_indicator(img, draw, y, paper_mode)

    # DG-228 Phase 3: page splitting handled by _split_pages() at the API layer.
    # Crop to content bottom (no max-height cap here) so the splitter can divide
    # the full content at natural section boundaries when it exceeds the cap.
    # CQ-3: clamp crop to the canvas height so a cursor that somehow exceeds
    # the canvas cannot append a solid-black band to the cropped output.
    crop_h = min(max(y, 1), img.height)
    return img.crop((0, 0, RECEIPT_WIDTH, crop_h))


def _render_bus_label(order, cfg, paper_mode="label") -> Image.Image:
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

    # Order ref and customer name (small, centered) — sit between notes and separator
    order_ref = _order_visual_ref(order)
    customer_name = order.get("customerName", "") or order.get("customer_name", "") or ""
    order_line = f"Mã đơn: {order_ref}" if order_ref else ""
    customer_line = customer_name
    order_customer_h = (
        (_th(order_line, f_shop) + LINE_GAP) if order_line else 0
    ) + (
        (_th(customer_line, f_shop) + LINE_GAP) if customer_line else 0
    )
    new_sep_h = 8  # single thin separator between notes and order info

    # sy is the TOP of shop info block; anchor to bottom
    sy = paper_w - margin - shop_h
    # Reserve space above shop block for order/customer lines + thin separator
    sy_top = sy - new_sep_h - order_customer_h

    # Single thin separator line between notes and order/customer info
    draw.line([(margin, sy_top), (label_len - margin, sy_top)],
              fill=(0, 0, 0), width=1)

    # Order ref line
    if order_line:
        draw.text(((label_len - _tw(order_line, f_shop)) // 2, sy_top + new_sep_h),
                  order_line, font=f_shop, fill=(0, 0, 0))
    # Customer name line
    if customer_line:
        y_after_order = sy_top + new_sep_h + _th(order_line, f_shop) + LINE_GAP if order_line else sy_top + new_sep_h
        draw.text(((label_len - _tw(customer_line, f_shop)) // 2, y_after_order),
                  customer_line, font=f_shop, fill=(0, 0, 0))

    # Thick-thin double line separator above shop info
    draw.line([(margin, sy - sep_h), (label_len - margin, sy - sep_h)],
              fill=(0, 0, 0), width=3)
    draw.line([(margin, sy - sep_h + 6), (label_len - margin, sy - sep_h + 6)],
              fill=(0, 0, 0), width=1)
    for text, font in shop_lines:
        sy = _draw_centered(sy, text, font)

    # --- Main content: draw from top ---
    y = margin
    section_gap = 16  # extra spacing between phone / address / notes

    # Phone — largest, centered, bold, formatted as xxxx-xxx-xxx or xxx-xxx-xxx
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    if phone:
        phone = format_phone(phone)
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

    if paper_mode == "roll":
        content_bottom = _find_content_bottom(rotated)
        tear_draw = ImageDraw.Draw(rotated)
        gap = 64
        y_tear = content_bottom + gap
        dash = 4
        space = 4
        color = (100, 100, 100)
        x = MARGIN
        end_x = RECEIPT_WIDTH - MARGIN
        while x < end_x:
            x2 = min(x + dash, end_x)
            tear_draw.line([(x, y_tear), (x2, y_tear)], fill=color, width=1)
            x += dash + space
        new_height = y_tear + 20
        if new_height > rotated.height:
            extended = Image.new("RGB", (rotated.width, new_height), "white")
            extended.paste(rotated, (0, 0))
            rotated = extended

    return rotated


def _render_items_table(draw, y, work_items, fb, fbb, fs, conn) -> int:
    """Render items table for shop/delivery receipts. Returns y after table."""
    enum_labels = _enum_attribute_labels(conn)
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

    for i, item in enumerate(work_items):
        is_gift = item.get("isGift") or item.get("is_gift") or False
        item_name = item.get("productName", "") or item.get("product_name", "")
        if is_gift:
            item_name = f"{item_name} (Tặng)"
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        total = 0 if is_gift else qty * unit_price

        # Item row with dotted leaders
        name_max_w = col_sl - MARGIN - 10
        name_lines = _wrap(item_name, fb, name_max_w) or [item_name]

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

        # Birthday badge
        if item.get("isBirthday") or item.get("is_birthday"):
            age = item.get("age")
            age_suffix = f" SINH NHẬT{(' - ' + str(age) + ' tuổi') if age else ''}"
            y = _icon_text(draw, y, "\U0001F382", age_suffix, fbb, (180, 0, 0), x=MARGIN + 10)

        # Enum attribute lines — each on its own row (Q3 / R3), indented
        for line in _wrapped_enum_attribute_lines(item, enum_labels, fb, CONTENT_WIDTH - 10):
            y = _left(draw, y, line, fb, x=MARGIN + 10)

        # Item notes (sub-row, indented)
        notes = item.get("notes", "") or ""
        if notes:
            full = f"  Ghi chú: {notes}"
            if "\n" not in notes and _mixed_tw(full, fb) <= CONTENT_WIDTH:
                y = _left(draw, y, "  Ghi chú: ", fbb, (80, 80, 80))
                y -= _th("Ghi chú:", fbb) + LINE_GAP
                _draw_mixed(draw, MARGIN + _tw("  Ghi chú: ", fbb), y, notes, fb, (80, 80, 80))
                y += _th("A", fb) + _NOTE_LINE_GAP
            else:
                y = _left(draw, y, "  Ghi chú:", fbb, (80, 80, 80))
                for ln in _wrap(notes, fb, CONTENT_WIDTH - 20):
                    y = _left_mixed(draw, y, f"    {ln}", fb, (80, 80, 80))

        if i < len(work_items) - 1:
            y = _sep(draw, y)

    y += 4
    return y


def _render_financial_summary(draw, y, order, conn, fbb, fb) -> int:
    """Render financial summary for shop/delivery receipts. Returns y after."""
    work_items = order.get("workItems", [])
    subtotal = sum(
        item.get("quantity", 1) * float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        for item in work_items
        if not (item.get("isGift") or item.get("is_gift"))
    )
    shipping_fee = float(order.get("shippingFee", 0) or order.get("shipping_fee", 0))
    total_price = float(order.get("totalPrice", 0) or order.get("total_price", 0))

    y = _row(draw, y, "Tạm tính:", _format_vnd_full(subtotal), fbb)
    if shipping_fee > 0:
        y = _row(draw, y, "Phí giao hàng:", _format_vnd_full(shipping_fee), fb)
    # Cash-in-cake fee (non-bold, like shipping fee)
    for item in work_items:
        if _cash_fee_amount(item) > 0:
            fee_str = _format_vnd_full(_cash_fee_amount(item))
            y = _row(draw, y, "Phí rút tiền:", fee_str, fb)
    y = _row(draw, y, "Tổng cộng:", _format_vnd_full(total_price), fbb)

    order_id = order.get("id")
    # Rut tien transaction summary
    rut_target = _tien_rut_target(work_items)
    if rut_target > 0 and order_id:
        rut_recv = _tien_rut_received(conn, order_id)
        rut_color = (0, 100, 0) if rut_recv >= rut_target else (200, 0, 0)
        y = _row(draw, y, "Tiền rút đã nhận:", f"{_format_vnd_full(rut_recv)} / {_format_vnd_full(rut_target)}", fb, color_v=rut_color)
    total_paid = PaymentTransaction.total_paid_excl_outflows(conn, order_id) if order_id else 0.0
    remaining = total_price - total_paid

    y = _row(draw, y, "Đã thanh toán:", _format_vnd_full(total_paid), fb, color_v=(0, 100, 0))
    if remaining > 0:
        y = _row(draw, y, "Còn lại:", _format_vnd_full(remaining), fbb, color_v=(180, 0, 0))
    else:
        y = _row(draw, y, "Còn lại:", "0đ", fb, color_v=(0, 100, 0))
    y += 4
    return y


def _render_shop_receipt(order, cfg, conn, paper_mode="label") -> Image.Image:
    """Shop receipt (Phiếu giao hàng) — internal order summary for pickup verification."""
    work_items = order.get("workItems", [])

    img = Image.new("RGB", (RECEIPT_WIDTH, 4000), "white")
    draw = ImageDraw.Draw(img)

    fb = _font(_SZ_BODY)
    fbb = _font(_SZ_BODY, True)
    fs = _font(_SZ_SMALL)
    fnormal = _font(_SZ_NORMAL, True)

    y = MARGIN

    # Title
    y = _center(draw, y, "PHIẾU GIAO HÀNG", fnormal)

    # Order ref + date
    ref = _order_visual_ref(order)
    created = order.get("createdAt", "") or order.get("created_at", "")
    date_line = ref
    if created:
        date_line += f"  •  {created[:10]}"
    y = _center(draw, y, date_line, fb)
    y += 10

    y = _double(draw, y)

    # Customer section
    name = order.get("customerName", "") or order.get("customer_name", "")
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""

    if name:
        y = _left(draw, y, name, fbb)
    if phone:
        y = _icon_text(draw, y, "\u260E", format_phone(phone), fb)

    y = _sep(draw, y)

    code_box_text = _shop_delivery_code_text(order)
    if code_box_text:
        code_font = _font(_SZ_BIG, True)
        y = _draw_compact_reference_box(draw, y, code_box_text, code_font)
        y += 12
        y = _sep(draw, y)

    # Items table
    y = _render_items_table(draw, y, work_items, fb, fbb, fs, conn)
    y = _double(draw, y)

    # Financial summary
    y = _render_financial_summary(draw, y, order, conn, fbb, fb)
    y = _double(draw, y)

    # Due date/time
    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    if due:
        due_str = f"Ngày nhận: {due}"
        if due_time:
            due_str += f" {due_time}"
        y = _left(draw, y, due_str, fbb)

    # Order notes
    order_notes = order.get("notes", "") or ""
    if order_notes:
        if due or due_time:
            y += 4
        y = _left(draw, y, "Ghi chú:", fbb)
        for ln in _wrap(order_notes, fb, CONTENT_WIDTH):
            y = _left_mixed(draw, y, ln, fb, (80, 80, 80))

    y += MARGIN
    y = _add_tear_indicator(img, draw, y, paper_mode)
    return img.crop((0, 0, RECEIPT_WIDTH, y))


def _render_delivery_receipt(order, cfg, conn, paper_mode="label") -> Image.Image:
    """Delivery receipt (Phiếu giao tận nơi) — internal delivery summary with prominent address."""
    work_items = order.get("workItems", [])

    img = Image.new("RGB", (RECEIPT_WIDTH, 4000), "white")
    draw = ImageDraw.Draw(img)

    fb = _font(_SZ_BODY)
    fbb = _font(_SZ_BODY, True)
    fs = _font(_SZ_SMALL)
    fnormal = _font(_SZ_NORMAL, True)

    y = MARGIN

    # Title
    y = _center(draw, y, "PHIẾU GIAO TẬN NƠI", fnormal)

    # Order ref + date
    ref = _order_visual_ref(order)
    created = order.get("createdAt", "") or order.get("created_at", "")
    date_line = ref
    if created:
        date_line += f"  •  {created[:10]}"
    y = _center(draw, y, date_line, fb)
    y += 10

    y = _double(draw, y)

    # Customer section
    name = order.get("customerName", "") or order.get("customer_name", "")
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""

    if name:
        y = _left(draw, y, name, fbb)
    if phone:
        y = _icon_text(draw, y, "\u260E", format_phone(phone), fb)

    y = _sep(draw, y)

    code_box_text = _shop_delivery_code_text(order)
    if code_box_text:
        code_font = _font(_SZ_BIG, True)
        y = _draw_compact_reference_box(draw, y, code_box_text, code_font)
        y += 12
        y = _sep(draw, y)

    # Delivery section
    y = _left(draw, y, "Giao tận nơi", fbb)
    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    if daddr:
        for ln in _wrap(daddr, fb, CONTENT_WIDTH):
            y = _left(draw, y, f"  {ln}", fb)
    # Delivery notes
    delivery_notes = order.get("deliveryNotes", "") or order.get("delivery_notes", "") or ""
    if delivery_notes:
        for ln in _wrap(delivery_notes, fs, CONTENT_WIDTH - 20):
            y = _left(draw, y, f"  {ln}", fs, (80, 80, 80))

    y = _sep(draw, y)

    # Items table
    y = _render_items_table(draw, y, work_items, fb, fbb, fs, conn)
    y = _double(draw, y)

    # Financial summary
    y = _render_financial_summary(draw, y, order, conn, fbb, fb)
    y = _double(draw, y)

    # Due date/time
    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    if due:
        due_str = f"Ngày nhận: {due}"
        if due_time:
            due_str += f" {due_time}"
        y = _left(draw, y, due_str, fbb)

    # Order notes
    order_notes = order.get("notes", "") or ""
    if order_notes:
        if due or due_time:
            y += 4
        y = _left(draw, y, "Ghi chú:", fbb)
        for ln in _wrap(order_notes, fb, CONTENT_WIDTH):
            y = _left_mixed(draw, y, ln, fb, (80, 80, 80))

    y += MARGIN
    y = _add_tear_indicator(img, draw, y, paper_mode)
    return img.crop((0, 0, RECEIPT_WIDTH, y))


def _render_customer_receipt(order, cfg, conn, show_photos=True, paper_mode="label") -> Image.Image:
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

    enum_labels = _enum_attribute_labels(conn)

    y = MARGIN
    y = _header(draw, y, cfg)

    # Title — matching the paper form
    y = _center(draw, y, "BIÊN NHẬN", _font(_SZ_SUBTITLE, True))
    y = _sep(draw, y)

    # Order ref
    ref_font = _font(_SZ_SUBTITLE, True)
    y = _draw_wrapped(draw, y, _customer_reference_text(order), ref_font, CONTENT_WIDTH, align="center")

    # Date
    created = order.get("createdAt", "") or order.get("created_at", "")
    if created:
        y = _left(draw, y, f"Ngày: {created[:10]}", fb)

    # --- Section 1: Customer Info ---
    heading_font = _font(_SZ_SUBTITLE, True)
    heading_text = _customer_heading_text(order)
    y = _draw_wrapped(draw, y, heading_text, heading_font, CONTENT_WIDTH)
    y = _sep(draw, y)

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
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        total = 0 if is_gift else qty * unit_price

        if is_gift:
            # DG-228 Phase 2 / FR-10: single-line gift rendering
            # "Tặng: <name> xN" — no price columns, no attribute/note/photo sub-rows.
            gift_label = "Tặng:"
            gift_body = f"{item_name} x{qty}"
            label_w = _tw(gift_label, fbb)
            body_w = _tw(gift_body, fb)
            # Wrap body within remaining width (after label + space)
            body_max_w = CONTENT_WIDTH - label_w - _tw(" ", fbb)
            gift_lines = _wrap(gift_body, fb, body_max_w) or [gift_body]
            # First line: "Tặng: <first body line>"
            draw.text((MARGIN, y), gift_label, font=fbb, fill=(0, 128, 0))
            draw.text((MARGIN + label_w + _tw(" ", fbb), y), gift_lines[0], font=fb, fill=(0, 0, 0))
            y += max(_th(gift_label, fbb), _th(gift_lines[0], fb)) + LINE_GAP
            # Continuation lines (long gift names only)
            for gl in gift_lines[1:]:
                draw.text((MARGIN + label_w + _tw(" ", fbb), y), gl, font=fb, fill=(0, 0, 0))
                y += _th(gl, fb) + LINE_GAP
            # DG-228 Phase 2 / FR-11: no item-to-item separators.
            continue

        # Item row: name | SL | Giá | Thành tiền
        # Wrap product name within column width
        item_name_disp = item_name
        name_max_w = col_sl - MARGIN - 10
        name_lines = _wrap(item_name_disp, fb, name_max_w) or [item_name_disp]

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

        # Enum attribute lines — each on its own row (Q3 / R3), indented
        for line in _wrapped_enum_attribute_lines(item, enum_labels, fb, CONTENT_WIDTH - 10):
            y = _left(draw, y, line, fb, x=MARGIN + 10)

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

        # Cash-in-cake amount (sub-row within item)
        item_attrs = item.get("attributes") or {}
        item_cash = item_attrs.get("cash_amount")
        if item_attrs.get("rut_tien") == "true" and item_cash and int(float(item_cash)) > 0:
            cash_str = _format_vnd_full(float(item_cash))
            y = _icon_text(draw, y, "\U0001F4B0", f" Số tiền rút: {cash_str}", fbb, (0, 128, 0), x=MARGIN + 10)

        # DG-228 Phase 2 / FR-11: item-to-item separators removed for vertical compaction.
        # Section already bounded by the double sep below; no inter-item thin sep needed.

    y += 4
    y = _double(draw, y)

    # --- Financial Summary ---
    # DG-228 Phase 2 / FR-7,8,9: conditional financial lines.
    # Calculate subtotal (non-gift items only)
    subtotal = sum(
        item.get("quantity", 1) * float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        for item in work_items
        if not (item.get("isGift") or item.get("is_gift"))
    )
    shipping_fee = float(order.get("shippingFee", 0) or order.get("shipping_fee", 0))
    total_price = float(order.get("totalPrice", 0) or order.get("total_price", 0))

    # FR-7: hide "Tạm tính" when it equals "Tổng cộng" (no shipping/cash fees).
    has_fee_additions = shipping_fee > 0 or any(
        _cash_fee_amount(item) > 0 for item in work_items
    )
    if has_fee_additions or abs(subtotal - total_price) > 0.01:
        y = _row(draw, y, "Tạm tính:", _format_vnd_full(subtotal), fbb)
    if shipping_fee > 0:
        y = _row(draw, y, "Phí giao hàng:", _format_vnd_full(shipping_fee), fb)
    # Cash-in-cake fee in summary (like shipping fee, black text, not bold)
    for item in work_items:
        fee_amt = _cash_fee_amount(item)
        if fee_amt > 0:
            fee_str = _format_vnd_full(fee_amt)
            y = _row(draw, y, "Phí rút tiền:", fee_str, fb)
    y = _row(draw, y, "Tổng cộng:", _format_vnd_full(total_price), fbb)

    order_id = order.get("id")
    # Rut tien transaction summary
    rut_target = _tien_rut_target(work_items)
    if rut_target > 0 and order_id:
        rut_recv = _tien_rut_received(conn, order_id)
        rut_color = (0, 100, 0) if rut_recv >= rut_target else (200, 0, 0)
        y = _row(draw, y, "Tiền rút đã nhận:", f"{_format_vnd_full(rut_recv)} / {_format_vnd_full(rut_target)}", fb, color_v=rut_color)
    total_paid = PaymentTransaction.total_paid_excl_outflows(conn, order_id) if order_id else 0.0
    remaining = total_price - total_paid

    # FR-8/FR-9: conditional payment status lines.
    if total_paid <= 0:
        # FR-8: nothing paid — show only "Còn lại" (red, bold).
        y = _row(draw, y, "Còn lại:", _format_vnd_full(total_price), fbb, color_v=(180, 0, 0))
    elif remaining <= 0.01:
        # FR-9: fully paid — single "Đã thanh toán đủ" line (green).
        y = _row(draw, y, "Đã thanh toán đủ:", _format_vnd_full(total_paid), fbb, color_v=(0, 100, 0))
    else:
        # Partial payment — keep both lines (existing convention).
        y = _row(draw, y, "Đã thanh toán:", _format_vnd_full(total_paid), fb, color_v=(0, 100, 0))
        y = _row(draw, y, "Còn lại:", _format_vnd_full(remaining), fbb, color_v=(180, 0, 0))
    y += 4
    y = _double(draw, y)

    # --- Section 3: Delivery ---
    # DG-228 Phase 2 / FR-11, AC-13: skip the delivery section entirely when it
    # would have no meaningful content (pickup order with no due date, phone,
    # address, or notes). Avoids rendering an empty "GIAO HÀNG" block.
    due = order.get("dueDate", "") or order.get("due_date", "")
    due_time = order.get("dueTime", "") or order.get("due_time", "") or ""
    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    order_notes = order.get("notes", "") or ""

    has_delivery_content = bool(due or phone or order_notes or (dtype != "pickup" and daddr))

    if has_delivery_content:
        y = _left(draw, y, "GIAO HÀNG", _font(_SZ_SUBTITLE, True))
        y = _sep(draw, y)

        if due:
            due_str = f"Ngày nhận: {due}"
            if due_time:
                due_str += f" {due_time}"
            y = _left(draw, y, due_str, fbb)

        _DTYPE_VN = {"pickup": "Nhận tại tiệm", "bus": "Gửi xe buýt", "door": "Giao tận nơi"}
        dtype_vn = _DTYPE_VN.get(dtype, dtype)
        y = _left(draw, y, f"Hình thức: {dtype_vn}", fb)

        if phone:
            y = _icon_text(draw, y, "\u260E", format_phone(phone), fb)

        if dtype != "pickup" and daddr:
            y = _left(draw, y, f"Địa chỉ:", fbb)
            for ln in _wrap(daddr, fs, CONTENT_WIDTH - 20):
                y = _left(draw, y, f"  {ln}", fs)

        # Order-level notes
        if order_notes:
            # CQ-3: grow the 4000px canvas before drawing long order notes so
            # the cursor never runs past the canvas (which would silently
            # discard text and append a solid-black band to the crop).
            img, draw = _ensure_canvas_capacity(img, draw, y, headroom=len(order_notes) * 30)
            y = _left(draw, y, "Ghi chú:", fbb)
            for ln in _wrap(order_notes, fb, CONTENT_WIDTH):
                y = _left_mixed(draw, y, ln, fb, (80, 80, 80))
                img, draw = _ensure_canvas_capacity(img, draw, y)

    # Footer
    y += 4
    y = _double(draw, y)
    y = _center(draw, y, "Cảm ơn quý khách!", fb, (100, 100, 100))

    y += MARGIN
    y = _add_tear_indicator(img, draw, y, paper_mode)
    # DG-228 Phase 3: page splitting handled by _split_pages() at the API layer.
    # Crop to content bottom (no max-height cap here) so the splitter can divide
    # the full content at natural section boundaries when it exceeds the cap.
    # CQ-3: clamp crop to the canvas height so a cursor that somehow exceeds
    # the canvas cannot append a solid-black band to the cropped output.
    crop_h = min(max(y, 1), img.height)
    return img.crop((0, 0, RECEIPT_WIDTH, crop_h))


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
        # CQ-2: only split work_ticket/customer receipts on label paper — roll
        # mode and shop/delivery/bus_label types keep the single-image path so
        # long roll receipts print continuously and shop/delivery previews are
        # not truncated to page 1.
        if type in ("work_ticket", "customer") and paper_mode == "label":
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
