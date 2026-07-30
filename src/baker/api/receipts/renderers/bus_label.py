"""Renderer module: _render_bus_label (extracted from receipts.py)."""

from .._drawing import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

from PIL import Image, ImageDraw, ImageFont
from baker.formatters import format_phone

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
    # FR8: prefer delivery phone as the prominent contact when it differs from
    # the customer phone; otherwise fall back to the customer phone.
    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    dphone = _delivery_phone_value(order)
    if _phones_differ(phone, dphone):
        phone = dphone
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

