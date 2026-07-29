"""Renderer module: _render_work_ticket (extracted from receipts.py)."""

from .._drawing import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

from typing import Optional
from PIL import Image, ImageDraw, ImageFont
from baker.formatters import format_phone
from baker.models.payment_transaction import PaymentTransaction

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
    # DG-228 review cycle 3: sub-item index moved from header to bottom ref line.
    header_line = f"Mã: {ref}"
    if created:
        header_line += f"  •  {created[:10]}"
    y = _center(draw, y, header_line, fs)
    y += 10

    # ── Delivery section (on top) ──
    dtype = order.get("deliveryType", "") or order.get("delivery_type", "pickup")
    _DTYPE_VN = {"pickup": "Nhận tại tiệm", "bus": "Gửi xe buýt", "door": "Giao tận nơi"}
    dtype_vn = _DTYPE_VN.get(dtype, dtype)

    phone = order.get("customerPhone", "") or order.get("customer_phone", "") or ""
    dphone = _delivery_phone_value(order)
    daddr = order.get("deliveryAddress", "") or order.get("delivery_address", "") or ""

    y = _left(draw, y, f"GIAO HÀNG:  {dtype_vn}", fnormal)

    if _phones_differ(phone, dphone):
        # FR10: delivery phone takes precedence in the delivery section; the
        # customer phone is not duplicated here so production staff see the
        # contact that matters for this delivery.
        y = _icon_text(draw, y, "\u260E", format_phone(dphone), fb)
    elif phone:
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
        y += 10
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
    cash_amount = _cash_amount_value(work_item)
    if cash_amount > 0:
        ef = _emoji_font(_SZ_MEDIUM)
        tf = _font(_SZ_MEDIUM, True)
        icon = "\U0001F4B0"
        icon_w = _tw(icon, ef)
        amount_str = _format_vnd_full(cash_amount)
        draw.text((MARGIN, y), icon, font=ef, fill=(0, 128, 0))
        draw.text((MARGIN + icon_w + 4, y), f" Số tiền rút: {amount_str}", font=tf, fill=(0, 128, 0))
        y += max(_th(icon, ef), _th(f" Số tiền rút: {amount_str}", tf)) + LINE_GAP
        # Rut tien transaction summary (received vs target)
        order_id = order.get("id")
        rut_received = _tien_rut_received(conn, order_id) if order_id else 0.0
        if rut_received >= cash_amount:
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
    # DG-228 review cycle 3: draw a rectangle border around the group of enum
    # attribute lines to visually highlight them.
    enum_labels = _enum_attribute_labels(conn)
    enum_font = _font(_SZ_MEDIUM, True)
    enum_lines = list(_wrapped_enum_attribute_lines(work_item, enum_labels, enum_font, CONTENT_WIDTH))
    if enum_lines:
        y += 12
        y = _sep(draw, y)
        y += 8
        ENUM_PAD = 6
        box_start_y = y
        for line in enum_lines:
            y = _left(draw, y, line, enum_font)
        draw.rectangle(
            [MARGIN - ENUM_PAD, box_start_y - ENUM_PAD,
             RECEIPT_WIDTH - MARGIN + ENUM_PAD, y + ENUM_PAD - LINE_GAP],
            outline=(100, 100, 100), width=2,
        )
        y += ENUM_BOX_BOTTOM_PAD

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
        y = _left(draw, y, "Phụ kiện:", _font(_SZ_MEDIUM, bold=True))
        for ex in extras:
            ex_name = ex.get("productName", "") or ex.get("product_name", "") or "N/A"
            ex_qty = ex.get("quantity", 1)
            y = _left(draw, y, f"  {ex_name} x{ex_qty}", _font(_SZ_NORMAL, bold=True))

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
        # DG-228 review cycle 3: append sub-item index (n/m) to bottom ref
        # for multi-item orders (moved from header line).
        if item_index is not None and item_total is not None and item_total > 1:
            bottom_ref = f"{bottom_ref} ({item_index}/{item_total})"
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

