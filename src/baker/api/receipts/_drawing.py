"""Drawing primitives, fonts, and canvas helpers for receipt rendering."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import re as _re


RECEIPT_WIDTH = 576  # 80mm at 203 DPI (76mm print area)

RECEIPT_MAX_HEIGHT = 1040  # 130mm at 203 DPI — height cap for work_ticket/customer receipts

MARGIN = 28

CONTENT_WIDTH = RECEIPT_WIDTH - 2 * MARGIN

# Table column x-positions shared by customer_receipt and items_table
# renderers (DG-308 CQ-3: de-duplicated from both renderer modules).
COL_SL = MARGIN + 320   # SL column
COL_GIA = MARGIN + 380  # Giá column
COL_TT = RECEIPT_WIDTH - MARGIN  # Thành tiền (right-aligned)

THUMBNAIL_SIZE = 128

LINE_GAP = 4  # DG-228 Phase 2: reduced from 6 for vertical compaction

_SZ_FOOTER = 14  # DG-228 Phase 3 / FR-6: "Trang N/M" footer marker font (metadata-only exception to 16pt floor)

_SZ_TITLE = 32

_SZ_SUBTITLE = 24

_SZ_BODY = 20

_SZ_SMALL = 16

_SZ_HUGE = 40       # due date at bottom (unused — 36pt used instead)

_SZ_BIG = 36        # customer name, category, price, due date

_SZ_MEDIUM = 28     # notes text, birthday

_SZ_NORMAL = 24     # product name, section headers, title

ENUM_BOX_BOTTOM_PAD = 10  # bottom padding after enum attribute box

_SHOP_DEFAULTS = {
    "receipt_shop_name": "TIỆM BÁNH ĐOÀN GIA",
    "receipt_shop_specialty": "BÁNH KEM SINH NHẬT - RAU CÂU FLAN - BÔNG LAN TRỨNG MUỐI",
    "receipt_shop_address": "61 Hòn Khói, Ninh Diêm, Ninh Hòa, Khánh Hòa",
    "receipt_shop_phone": "0972 283 134 - 0968 187 434 - 0981 960 535",
}

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

_NOTE_LINE_GAP = 10  # extra spacing for note lines


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
    """Sum of cash_amount across all tien_rut items in an order.

    CQ-8: uses the guarded ``_cash_amount_value`` helper so a malformed
    ``cash_amount`` (e.g. ``"abc"``) on one item cannot raise ValueError
    and break the whole receipt render.
    """
    return sum(_cash_amount_value(item) for item in work_items)

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

def _left_mixed(draw, y, text, font, color=(0, 0, 0), x=None):
    """Draw left-aligned mixed emoji+text. Return y after with note-friendly spacing."""
    x = x if x is not None else MARGIN
    _draw_mixed(draw, x, y, text, font, color)
    return y + _th("A", font) + _NOTE_LINE_GAP

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

def _cash_amount_value(item: dict) -> float:
    """Return the ``cash_amount`` for an item, or 0.0 when missing/malformed.

    CQ-8: mirrors the ``_cash_fee_amount`` guard so a malformed
    ``cash_amount`` (e.g. non-numeric string, None, list) cannot raise
    ValueError/TypeError during receipt rendering and cause an HTTP 500.
    Only returns a non-zero amount when the item has ``rut_tien == "true"``
    and a parseable numeric amount.
    """
    attrs = item.get("attributes") or {}
    if attrs.get("rut_tien") != "true":
        return 0.0
    raw = attrs.get("cash_amount")
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



__all__ = [
    'RECEIPT_WIDTH',
    'RECEIPT_MAX_HEIGHT',
    'MARGIN',
    'CONTENT_WIDTH',
    'COL_SL',
    'COL_GIA',
    'COL_TT',
    'THUMBNAIL_SIZE',
    'LINE_GAP',
    '_SZ_FOOTER',
    '_SZ_TITLE',
    '_SZ_SUBTITLE',
    '_SZ_BODY',
    '_SZ_SMALL',
    '_SZ_HUGE',
    '_SZ_BIG',
    '_SZ_MEDIUM',
    '_SZ_NORMAL',
    'ENUM_BOX_BOTTOM_PAD',
    '_SHOP_DEFAULTS',
    '_EMOJI_RE',
    '_NOTE_LINE_GAP',
    '_font',
    '_emoji_font',
    '_tien_rut_received',
    '_tien_rut_target',
    '_format_vnd',
    '_format_vnd_full',
    '_th',
    '_tw',
    '_center',
    '_left',
    '_right_at',
    '_row',
    '_sep',
    '_double',
    '_thick',
    '_add_tear_indicator',
    '_find_content_bottom',
    '_find_split_boundaries',
    '_split_pages',
    '_dots',
    '_icon_text',
    '_icon_text_centered',
    '_draw_mixed',
    '_mixed_tw',
    '_wrap',
    '_draw_wrapped',
    '_left_mixed',
    '_cash_fee_amount',
    '_cash_amount_value',
    '_ensure_canvas_capacity',
]
