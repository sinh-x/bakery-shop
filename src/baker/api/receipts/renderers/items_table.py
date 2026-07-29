"""Renderer module: _render_items_table, _render_financial_summary (extracted from receipts.py)."""

from .._drawing import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

from baker.models.payment_transaction import PaymentTransaction

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

