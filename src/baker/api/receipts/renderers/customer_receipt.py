"""Renderer module: _render_customer_receipt (extracted from receipts.py)."""

from .._drawing import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

import io
from PIL import Image, ImageDraw, ImageFont
from baker.formatters import format_phone
from baker.models.payment_transaction import PaymentTransaction

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
    col_sl = COL_SL
    col_gia = COL_GIA
    col_tt = COL_TT

    draw.text((MARGIN, y), "Sản phẩm", font=fbb, fill=(100, 100, 100))
    draw.text((col_sl, y), "SL", font=fbb, fill=(100, 100, 100))
    draw.text((col_gia, y), "Giá", font=fbb, fill=(100, 100, 100))
    tt_label = "T.Tiền"
    draw.text((col_tt - _tw(tt_label, fbb), y), tt_label, font=fbb, fill=(100, 100, 100))
    y += _th("SL", fbb) + LINE_GAP + 4
    y = _sep(draw, y)

    # DG-228 review cycle 3: bundle all gift items into a single "Tặng:" line.
    gift_items = [
        it for it in work_items
        if it.get("isGift") or it.get("is_gift") or False
    ]
    if gift_items:
        gift_label = "Tặng:"
        gift_body_parts = []
        for it in gift_items:
            g_name = it.get("productName", "") or it.get("product_name", "")
            g_qty = it.get("quantity", 1)
            gift_body_parts.append(f"{g_name} x{g_qty}")
        gift_body = ", ".join(gift_body_parts)
        label_w = _tw(gift_label, fbb)
        space_w = _tw(" ", fbb)
        body_max_w = CONTENT_WIDTH - label_w - space_w
        gift_lines = _wrap(gift_body, fb, body_max_w) or [gift_body]
        # First line: "Tặng: <first body line>" — green label, black body
        draw.text((MARGIN, y), gift_label, font=fbb, fill=(0, 128, 0))
        draw.text((MARGIN + label_w + space_w, y), gift_lines[0], font=fb, fill=(0, 0, 0))
        y += max(_th(gift_label, fbb), _th(gift_lines[0], fb)) + LINE_GAP
        # Continuation lines (wrap)
        for gl in gift_lines[1:]:
            draw.text((MARGIN + label_w + space_w, y), gl, font=fb, fill=(0, 0, 0))
            y += _th(gl, fb) + LINE_GAP
        # No price columns, no attribute/note/photo sub-rows for gifts.

    for i, item in enumerate(work_items):
        is_gift = item.get("isGift") or item.get("is_gift") or False
        item_name = item.get("productName", "") or item.get("product_name", "")
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unitPrice", 0) or item.get("unit_price", 0))
        total = 0 if is_gift else qty * unit_price

        if is_gift:
            # Gift items already rendered as a single bundled line above.
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
            y = _icon_text(draw, y, "\U0001F382", age_suffix, fbb, (180, 0, 0), x=MARGIN)

        # Enum attribute lines — each on its own row (Q3 / R3), indented
        for line in _wrapped_enum_attribute_lines(item, enum_labels, fb, CONTENT_WIDTH - 10):
            y = _left(draw, y, line, fb, x=MARGIN)

        # Photo — first attached photo for any item, larger + centered, display only
        item_id = item.get("id")
        photo_size = 192  # larger than default 128
        if show_photos and order_id and item_id:
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
        item_cash = _cash_amount_value(item)
        if item_cash > 0:
            cash_str = _format_vnd_full(item_cash)
            y = _icon_text(draw, y, "\U0001F4B0", f" Số tiền rút: {cash_str}", fbb, (0, 128, 0), x=MARGIN)

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
    dphone = _delivery_phone_value(order)
    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""
    order_notes = order.get("notes", "") or ""

    has_delivery_content = bool(due or phone or dphone or order_notes or (dtype != "pickup" and daddr))

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

        # FR6: show delivery phone in the delivery section when it differs
        # from the customer phone; otherwise show the customer phone once.
        if _phones_differ(phone, dphone):
            y = _icon_text(draw, y, "\U0001F4DE", format_phone(dphone), fb, color=(0, 100, 180))
        elif phone:
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

