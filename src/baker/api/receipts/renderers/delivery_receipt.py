"""Renderer module: _render_delivery_receipt (extracted from receipts.py)."""

from .._drawing import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403
from .items_table import _render_items_table, _render_financial_summary  # noqa: F401

from PIL import Image, ImageDraw, ImageFont
from baker.formatters import format_phone

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
    dphone = _delivery_phone_value(order)

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
    # FR7: print delivery phone prominently when it differs from customer phone.
    if _phones_differ(phone, dphone):
        y = _icon_text(draw, y, "\U0001F4DE", format_phone(dphone), fbb, color=(0, 100, 180))
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

