"""Receipt image generation API for thermal printer.

Generates three receipt types as PNG images:
- Order summary receipt (internal use)
- Work ticket receipt (production use)
- Customer receipt (clean, customer-facing)
"""

import io
import os
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse

from PIL import Image, ImageDraw, ImageFont

from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentTransaction


router = APIRouter(prefix="/api/orders", tags=["receipts"])

# Receipt dimensions: 576px width (80mm at 203 DPI), variable height
RECEIPT_WIDTH = 576

# Font sizes
FONT_SIZE_HEADER = 20
FONT_SIZE_BODY = 16
FONT_SIZE_SMALL = 12

# Line heights
LINE_HEIGHT = 22
LINE_HEIGHT_SMALL = 18

# Margins
MARGIN_LEFT = 15
MARGIN_RIGHT = 15
MARGIN_TOP = 15
MARGIN_BOTTOM = 15

# Content width
CONTENT_WIDTH = RECEIPT_WIDTH - MARGIN_LEFT - MARGIN_RIGHT

# Photo thumbnail size for work tickets
THUMBNAIL_SIZE = 128


def _get_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    """Load bundled NotoSans font at specified size."""
    import baker
    font_dir = Path(baker.__file__).parent / "assets" / "fonts"
    font_name = "NotoSans-Bold.ttf" if bold else "NotoSans-Regular.ttf"
    font_path = font_dir / font_name
    return ImageFont.truetype(str(font_path), size)


def _format_vnd(amount: float) -> str:
    """Format amount as Vietnamese currency string."""
    if amount == int(amount):
        return f"{int(amount):.0f}đ"
    return f"{amount:,.0f}đ"


def _draw_centered_text(draw: ImageDraw, y: int, text: str, font: ImageFont.FreeTypeFont, color: tuple[int, int, int]) -> int:
    """Draw centered text, return the y coordinate after the text."""
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    x = (RECEIPT_WIDTH - text_width) // 2
    draw.text((x, y), text, font=font, fill=color)
    return y + (bbox[3] - bbox[1]) + 4


def _draw_text(draw: ImageDraw, x: int, y: int, text: str, font: ImageFont.FreeTypeFont, color: tuple[int, int, int] = (0, 0, 0)) -> int:
    """Draw left-aligned text, return the y coordinate after the text."""
    draw.text((x, y), text, font=font, fill=color)
    bbox = draw.textbbox((0, 0), text, font=font)
    return y + (bbox[3] - bbox[1])


def _draw_right_text(draw: ImageDraw, right_x: int, y: int, text: str, font: ImageFont.FreeTypeFont, color: tuple[int, int, int] = (0, 0, 0)) -> int:
    """Draw right-aligned text, return the y coordinate after the text."""
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    x = right_x - text_width
    draw.text((x, y), text, font=font, fill=color)
    return y + (bbox[3] - bbox[1])


def _draw_separator(draw: ImageDraw, y: int, dash_gap: int = 4) -> int:
    """Draw dashed separator line, return y coordinate after."""
    draw.line([(MARGIN_LEFT, y), (RECEIPT_WIDTH - MARGIN_RIGHT, y)], fill=(180, 180, 180), width=1)
    return y + LINE_HEIGHT_SMALL


def _draw_double_line(draw: ImageDraw, y: int) -> int:
    """Draw double-line separator, return y coordinate after."""
    draw.line([(MARGIN_LEFT, y), (RECEIPT_WIDTH - MARGIN_RIGHT, y)], fill=(0, 0, 0), width=1)
    draw.line([(MARGIN_LEFT, y + 4), (RECEIPT_WIDTH - MARGIN_RIGHT, y + 4)], fill=(0, 0, 0), width=1)
    return y + LINE_HEIGHT


def _calculate_text_height(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> int:
    """Calculate total height needed for wrapped text."""
    words = text.split()
    lines = []
    current_line = ""
    for word in words:
        test_line = current_line + (" " if current_line else "") + word
        bbox = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), test_line, font=font)
        test_width = bbox[2] - bbox[0]
        if test_width <= max_width:
            current_line = test_line
        else:
            if current_line:
                lines.append(current_line)
            current_line = word
    if current_line:
        lines.append(current_line)
    bbox = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), "Aj", font=font)
    line_height = (bbox[3] - bbox[1]) + 4
    return len(lines) * line_height


def _wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    """Wrap text to fit within max_width, returning list of lines."""
    if not text:
        return []
    words = text.split()
    lines = []
    current_line = ""
    for word in words:
        test_line = current_line + (" " if current_line else "") + word
        bbox = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), test_line, font=font)
        test_width = bbox[2] - bbox[0]
        if test_width <= max_width:
            current_line = test_line
        else:
            if current_line:
                lines.append(current_line)
            current_line = word
    if current_line:
        lines.append(current_line)
    return lines


def _get_shop_config(conn) -> dict:
    """Get receipt shop config from app_config table."""
    config = {
        "receipt_shop_name": "Bánh Kem Đoàn Gia",
        "receipt_shop_address": "",
        "receipt_shop_phone": "",
    }
    rows = conn.execute("SELECT config_key, config_value FROM app_config WHERE config_key LIKE 'receipt_%'").fetchall()
    for row in rows:
        if row["config_key"] in config:
            config[row["config_key"]] = row["config_value"]
    return config


def _get_payment_status(order: dict, total_paid: float) -> tuple[str, str]:
    """Get payment status display text and indicator."""
    total_price = float(order.get("total_price", 0))
    if total_paid >= total_price:
        return "Đã thanh toán", "PAID"
    elif total_paid > 0:
        remaining = total_price - total_paid
        return f"Còn nợ: {remaining:,.0f}đ", "PARTIAL"
    else:
        return "Chưa thanh toán", "UNPAID"


def _get_order_photo_for_work_item(conn, order_id: int, work_item_id: int) -> Optional[bytes]:
    """Get first photo bytes for a work item if available."""
    row = conn.execute(
        "SELECT hash FROM photos p JOIN order_photos op ON p.id = op.photo_id WHERE op.order_id = ? AND op.work_item_id = ? LIMIT 1",
        (order_id, work_item_id),
    ).fetchone()
    if not row:
        # Try getting any photo for the order
        row = conn.execute(
            "SELECT hash FROM photos p JOIN order_photos op ON p.id = op.photo_id WHERE op.order_id = ? LIMIT 1",
            (order_id,),
        ).fetchone()
    if row:
        photo_dir = Path(__file__).parent.parent.parent.parent / "data" / "photos"
        photo_path = photo_dir / f"{row['hash']}.jpg"
        if photo_path.exists():
            with open(photo_path, "rb") as f:
                return f.read()
    return None


def _render_header(draw: ImageDraw, y: int, shop_config: dict) -> int:
    """Draw shop name header, return y after header."""
    font_title = _get_font(FONT_SIZE_HEADER, bold=True)
    y = _draw_centered_text(draw, y, shop_config["receipt_shop_name"], font_title, (0, 0, 0))
    if shop_config["receipt_shop_address"]:
        font_small = _get_font(FONT_SIZE_SMALL)
        y = _draw_centered_text(draw, y, shop_config["receipt_shop_address"], font_small, (80, 80, 80))
    if shop_config["receipt_shop_phone"]:
        font_small = _get_font(FONT_SIZE_SMALL)
        y = _draw_centered_text(draw, y, shop_config["receipt_shop_phone"], font_small, (80, 80, 80))
    y += 4
    y = _draw_double_line(draw, y)
    return y


def _render_order_receipt(order_detail: dict, shop_config: dict, conn) -> Image.Image:
    """Render order summary receipt (internal use).

    F2: shop name, order ref, date, customer, all items with name/qty/unit price/line total,
    subtotal, payment status, amount paid, remaining balance, due date/time, delivery type, notes
    """
    font_body = _get_font(FONT_SIZE_BODY)
    font_bold = _get_font(FONT_SIZE_BODY, bold=True)
    font_small = _get_font(FONT_SIZE_SMALL)

    # Calculate required height
    items = order_detail.get("items", [])
    work_items = order_detail.get("workItems", [])
    notes = order_detail.get("notes", "") or ""
    delivery_address = order_detail.get("delivery_address", "") or ""

    num_lines = 20  # Base lines
    for item in work_items:
        item_name = item.get("product_name", "")
        num_lines += _calculate_text_height(item_name, font_body, CONTENT_WIDTH - 200) // LINE_HEIGHT
        num_lines += 1  # item row
    num_lines += _calculate_text_height(notes, font_small, CONTENT_WIDTH) // LINE_HEIGHT_SMALL
    num_lines += _calculate_text_height(delivery_address, font_small, CONTENT_WIDTH) // LINE_HEIGHT_SMALL

    img_height = MARGIN_TOP + (num_lines * LINE_HEIGHT) + MARGIN_BOTTOM + 200
    img = Image.new("RGB", (RECEIPT_WIDTH, img_height), "white")
    draw = ImageDraw.Draw(img)

    y = MARGIN_TOP
    y = _render_header(draw, y, shop_config)

    # Order reference - prominent
    order_ref = order_detail.get("order_ref", "")
    font_ref = _get_font(FONT_SIZE_HEADER, bold=True)
    y = _draw_centered_text(draw, y, f"Mã đơn: {order_ref}", font_ref, (0, 0, 0))
    y += 4

    # Date
    created_at = order_detail.get("created_at", "")[:10] if order_detail.get("created_at") else ""
    y = _draw_text(draw, MARGIN_LEFT, y, f"Ngày tạo: {created_at}", font_body)
    y = _draw_separator(draw, y)

    # Customer info
    customer_name = order_detail.get("customer_name", "")
    customer_phone = order_detail.get("customer_phone", "") or ""
    y = _draw_text(draw, MARGIN_LEFT, y, f"Khách hàng: {customer_name}", font_body)
    if customer_phone:
        y = _draw_text(draw, MARGIN_LEFT, y, f"Điện thoại: {customer_phone}", font_body)
    y = _draw_separator(draw, y)

    # Items table header
    draw.text((MARGIN_LEFT, y), "SẢN PHẨM", font=font_bold, fill=(0, 0, 0))
    draw.text((MARGIN_LEFT + 220, y), "SL", font=font_bold, fill=(0, 0, 0))
    draw.text((MARGIN_LEFT + 280, y), "ĐƠN GIÁ", font=font_bold, fill=(0, 0, 0))
    draw.text((MARGIN_LEFT + 400, y), "T.TIỀN", font=font_bold, fill=(0, 0, 0))
    y += LINE_HEIGHT
    draw.line([(MARGIN_LEFT, y), (RECEIPT_WIDTH - MARGIN_RIGHT, y)], fill=(180, 180, 180), width=1)
    y += 4

    # Items
    for item in work_items:
        item_name = item.get("product_name", "")
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unit_price", 0))
        line_total = qty * unit_price

        # Draw item name (may wrap)
        lines = _wrap_text(item_name, font_body, 210)
        for i, line in enumerate(lines):
            y = _draw_text(draw, MARGIN_LEFT, y, line, font_body)
        y = _draw_text(draw, MARGIN_LEFT + 220, y - LINE_HEIGHT, str(qty), font_body)  # qty on first line
        y = _draw_text(draw, MARGIN_LEFT + 280, y - LINE_HEIGHT, _format_vnd(unit_price), font_body)  # price on first line
        y = _draw_text(draw, MARGIN_LEFT + 400, y - LINE_HEIGHT, _format_vnd(line_total), font_body)  # total on first line

        # Birthday info
        if item.get("is_birthday"):
            age = item.get("age")
            age_text = f"(Sinh nhật{(' - ' + str(age) + ' tuổi') if age else ''})"
            y = _draw_text(draw, MARGIN_LEFT + 30, y, age_text, font_small, (150, 0, 0))

        y += 4

    y = _draw_separator(draw, y)

    # Totals
    total_price = float(order_detail.get("total_price", 0))
    y = _draw_text(draw, MARGIN_LEFT, y, "TỔNG CỘNG:", font_bold)
    y = _draw_right_text(draw, RECEIPT_WIDTH - MARGIN_RIGHT, y - LINE_HEIGHT, _format_vnd(total_price), font_bold)

    # Payment info
    order_id = order_detail.get("id")
    total_paid = 0.0
    if order_id:
        total_paid = PaymentTransaction.total_for_order(conn, order_id)
    amount_paid = total_paid
    remaining = total_price - amount_paid

    y = _draw_text(draw, MARGIN_LEFT, y, "Đã thanh toán:", font_body)
    y = _draw_right_text(draw, RECEIPT_WIDTH - MARGIN_RIGHT, y - LINE_HEIGHT, _format_vnd(amount_paid), font_body, (0, 100, 0))

    if remaining > 0:
        y = _draw_text(draw, MARGIN_LEFT, y, "Còn nợ:", font_body)
        y = _draw_right_text(draw, RECEIPT_WIDTH - MARGIN_RIGHT, y - LINE_HEIGHT, _format_vnd(remaining), font_body, (180, 0, 0))

    status_text, _ = _get_payment_status(order_detail, total_paid)
    y = _draw_text(draw, MARGIN_LEFT, y, f"Trạng thái: {status_text}", font_body)

    y = _draw_separator(draw, y)

    # Due date/time
    due_date = order_detail.get("due_date", "")
    due_time = order_detail.get("due_time", "") or ""
    if due_date:
        due_str = f"Ngày giao/nhận: {due_date}"
        if due_time:
            due_str += f" {due_time}"
        y = _draw_text(draw, MARGIN_LEFT, y, due_str, font_bold)

    # Delivery type
    delivery_type = order_detail.get("delivery_type", "pickup")
    delivery_type_display = "Nhận tại tiệm" if delivery_type == "pickup" else "Giao hàng"
    y = _draw_text(draw, MARGIN_LEFT, y, f"Hình thức: {delivery_type_display}", font_body)
    if delivery_type != "pickup" and delivery_address:
        addr_lines = _wrap_text(delivery_address, font_small, CONTENT_WIDTH)
        for line in addr_lines:
            y = _draw_text(draw, MARGIN_LEFT, y, f"  {line}", font_small)

    # Notes
    if notes:
        y = _draw_separator(draw, y)
        y = _draw_text(draw, MARGIN_LEFT, y, "Ghi chú:", font_bold)
        note_lines = _wrap_text(notes, font_small, CONTENT_WIDTH)
        for line in note_lines:
            y = _draw_text(draw, MARGIN_LEFT, y, line, font_small, (80, 80, 80))

    # Footer
    y = _draw_double_line(draw, y + 10)
    y = _draw_centered_text(draw, y, "--- Hết phiếu ---", font_small, (120, 120, 120))

    # Crop to content
    bbox = img.getbbox()
    if bbox:
        img = img.crop((0, 0, RECEIPT_WIDTH, bbox[3] + MARGIN_BOTTOM))

    return img


def _render_work_ticket(order_detail: dict, work_item: dict, shop_config: dict, photo_bytes: Optional[bytes], conn) -> Image.Image:
    """Render work ticket receipt (production use).

    F3: shop name, order ref, product name, qty, unit price, notes,
    birthday info (flag + age), decoration photo thumbnail 128x128,
    due date/time, status
    """
    font_body = _get_font(FONT_SIZE_BODY)
    font_bold = _get_font(FONT_SIZE_BODY, bold=True)
    font_small = _get_font(FONT_SIZE_SMALL)

    # Calculate required height
    product_name = work_item.get("product_name", "")
    notes = work_item.get("notes", "") or ""

    num_lines = 15
    num_lines += _calculate_text_height(product_name, font_body, CONTENT_WIDTH - THUMBNAIL_SIZE - 20) // LINE_HEIGHT
    num_lines += _calculate_text_height(notes, font_small, CONTENT_WIDTH) // LINE_HEIGHT_SMALL
    if photo_bytes:
        num_lines += THUMBNAIL_SIZE // LINE_HEIGHT + 2

    img_height = MARGIN_TOP + (num_lines * LINE_HEIGHT) + MARGIN_BOTTOM + 150
    img = Image.new("RGB", (RECEIPT_WIDTH, img_height), "white")
    draw = ImageDraw.Draw(img)

    y = MARGIN_TOP
    y = _render_header(draw, y, shop_config)

    # PHIẾU LÀM VIỆC label
    font_title = _get_font(FONT_SIZE_HEADER, bold=True)
    y = _draw_centered_text(draw, y, "PHIẾU LÀM VIỆC", font_title, (0, 0, 0))
    y = _draw_separator(draw, y)

    # Order reference
    order_ref = order_detail.get("order_ref", "")
    font_ref = _get_font(FONT_SIZE_HEADER, bold=True)
    y = _draw_centered_text(draw, y, f"Mã đơn: {order_ref}", font_ref, (0, 0, 0))
    y += 4
    y = _draw_separator(draw, y)

    # Product name
    y = _draw_text(draw, MARGIN_LEFT, y, "Sản phẩm:", font_small)
    y = _draw_text(draw, MARGIN_LEFT, y, product_name, font_bold)
    if work_item.get("is_birthday"):
        age = work_item.get("age")
        age_text = f"SINH NHẬT{(' - ' + str(age) + ' tuổi') if age else ''}"
        y = _draw_text(draw, MARGIN_LEFT, y, age_text, font_bold, (150, 0, 0))
    y += 4

    # Qty and price
    qty = work_item.get("quantity", 1)
    unit_price = float(work_item.get("unit_price", 0))
    y = _draw_text(draw, MARGIN_LEFT, y, f"Số lượng: {qty}", font_body)
    y = _draw_text(draw, MARGIN_LEFT, y, f"Đơn giá: {_format_vnd(unit_price)}", font_body)
    y += 4

    # Photo thumbnail on the right side if available
    x_photo = RECEIPT_WIDTH - MARGIN_RIGHT - THUMBNAIL_SIZE
    if photo_bytes:
        try:
            photo_img = Image.open(io.BytesIO(photo_bytes))
            photo_img = photo_img.convert("RGB")
            photo_img.thumbnail((THUMBNAIL_SIZE, THUMBNAIL_SIZE), Image.LANCZOS)
            # Paste on white background
            thumb_bg = Image.new("RGB", (THUMBNAIL_SIZE, THUMBNAIL_SIZE), "white")
            thumb_x = (THUMBNAIL_SIZE - photo_img.width) // 2
            thumb_y = (THUMBNAIL_SIZE - photo_img.height) // 2
            thumb_bg.paste(photo_img, (thumb_x, thumb_y))
            img.paste(thumb_bg, (x_photo, y))
            draw.rectangle([x_photo, y, x_photo + THUMBNAIL_SIZE, y + THUMBNAIL_SIZE], outline=(200, 200, 200), width=1)
            y += THUMBNAIL_SIZE + 10
        except Exception:
            pass

    # Notes
    if notes:
        y = _draw_text(draw, MARGIN_LEFT, y, "Ghi chú:", font_small)
        note_lines = _wrap_text(notes, font_small, CONTENT_WIDTH - (THUMBNAIL_SIZE + 20) if photo_bytes else CONTENT_WIDTH)
        for line in note_lines:
            y = _draw_text(draw, MARGIN_LEFT, y, line, font_small, (80, 80, 80))

    y = _draw_separator(draw, y)

    # Due date/time
    due_date = order_detail.get("due_date", "")
    due_time = order_detail.get("due_time", "") or ""
    if due_date:
        due_str = f"NGÀY GIAO: {due_date}"
        if due_time:
            due_str += f" {due_time}"
        font_due = _get_font(FONT_SIZE_HEADER, bold=True)
        y = _draw_centered_text(draw, y, due_str, font_due, (0, 0, 0))

    # Status
    status = work_item.get("status", "pending")
    status_display = {
        "pending": "Chờ làm",
        "in_progress": "Đang làm",
        "done": "Xong",
    }.get(status, status)
    y = _draw_text(draw, MARGIN_LEFT, y, f"Trạng thái: {status_display}", font_body)

    y = _draw_double_line(draw, y + 10)
    y = _draw_centered_text(draw, y, "--- Phiếu sản xuất ---", font_small, (120, 120, 120))

    # Crop to content
    bbox = img.getbbox()
    if bbox:
        img = img.crop((0, 0, RECEIPT_WIDTH, bbox[3] + MARGIN_BOTTOM))

    return img


def _render_customer_receipt(order_detail: dict, shop_config: dict, conn) -> Image.Image:
    """Render customer receipt (clean, customer-facing).

    F4: shop name + contact, order ref, date, items (name, qty, price),
    total, amount paid, remaining balance, due date, delivery info.
    NO internal notes or statuses.
    """
    font_body = _get_font(FONT_SIZE_BODY)
    font_bold = _get_font(FONT_SIZE_BODY, bold=True)
    font_small = _get_font(FONT_SIZE_SMALL)

    # Calculate required height
    work_items = order_detail.get("workItems", [])
    delivery_address = order_detail.get("delivery_address", "") or ""

    num_lines = 15
    for item in work_items:
        item_name = item.get("product_name", "")
        num_lines += _calculate_text_height(item_name, font_body, CONTENT_WIDTH - 150) // LINE_HEIGHT
        num_lines += 1
    num_lines += _calculate_text_height(delivery_address, font_small, CONTENT_WIDTH) // LINE_HEIGHT_SMALL

    img_height = MARGIN_TOP + (num_lines * LINE_HEIGHT) + MARGIN_BOTTOM + 150
    img = Image.new("RGB", (RECEIPT_WIDTH, img_height), "white")
    draw = ImageDraw.Draw(img)

    y = MARGIN_TOP
    y = _render_header(draw, y, shop_config)

    # Customer receipt header
    font_title = _get_font(FONT_SIZE_HEADER, bold=True)
    y = _draw_centered_text(draw, y, "HÓA ĐƠN", font_title, (0, 0, 0))
    y = _draw_separator(draw, y)

    # Order reference
    order_ref = order_detail.get("order_ref", "")
    font_ref = _get_font(FONT_SIZE_HEADER, bold=True)
    y = _draw_centered_text(draw, y, f"Mã đơn: {order_ref}", font_ref, (0, 0, 0))
    y += 4

    # Date
    created_at = order_detail.get("created_at", "")[:10] if order_detail.get("created_at") else ""
    y = _draw_text(draw, MARGIN_LEFT, y, f"Ngày: {created_at}", font_body)
    y = _draw_separator(draw, y)

    # Customer info
    customer_name = order_detail.get("customer_name", "")
    customer_phone = order_detail.get("customer_phone", "") or ""
    y = _draw_text(draw, MARGIN_LEFT, y, f"Khách hàng: {customer_name}", font_body)
    if customer_phone:
        y = _draw_text(draw, MARGIN_LEFT, y, f"Điện thoại: {customer_phone}", font_body)
    y = _draw_separator(draw, y)

    # Items header
    draw.text((MARGIN_LEFT, y), "SẢN PHẨM", font=font_bold, fill=(0, 0, 0))
    draw.text((MARGIN_LEFT + 240, y), "SL", font=font_bold, fill=(0, 0, 0))
    draw.text((MARGIN_LEFT + 300, y), "T.TIỀN", font=font_bold, fill=(0, 0, 0))
    y += LINE_HEIGHT
    draw.line([(MARGIN_LEFT, y), (RECEIPT_WIDTH - MARGIN_RIGHT, y)], fill=(180, 180, 180), width=1)
    y += 4

    # Items (clean - no birthday flags, no internal notes)
    for item in work_items:
        item_name = item.get("product_name", "")
        qty = item.get("quantity", 1)
        unit_price = float(item.get("unit_price", 0))
        line_total = qty * unit_price

        lines = _wrap_text(item_name, font_body, 230)
        for i, line in enumerate(lines):
            y = _draw_text(draw, MARGIN_LEFT, y, line, font_body)
        y = _draw_text(draw, MARGIN_LEFT + 240, y - LINE_HEIGHT, str(qty), font_body)
        y = _draw_text(draw, MARGIN_LEFT + 300, y - LINE_HEIGHT, _format_vnd(line_total), font_body)
        y += 4

    y = _draw_separator(draw, y)

    # Totals
    total_price = float(order_detail.get("total_price", 0))
    y = _draw_text(draw, MARGIN_LEFT, y, "TỔNG CỘNG:", font_bold)
    y = _draw_right_text(draw, RECEIPT_WIDTH - MARGIN_RIGHT, y - LINE_HEIGHT, _format_vnd(total_price), font_bold)

    # Payment info
    order_id = order_detail.get("id")
    total_paid = 0.0
    if order_id:
        total_paid = PaymentTransaction.total_for_order(conn, order_id)
    amount_paid = total_paid
    remaining = total_price - amount_paid

    y = _draw_text(draw, MARGIN_LEFT, y, "Đã thanh toán:", font_body)
    y = _draw_right_text(draw, RECEIPT_WIDTH - MARGIN_RIGHT, y - LINE_HEIGHT, _format_vnd(amount_paid), font_body, (0, 100, 0))

    if remaining > 0:
        y = _draw_text(draw, MARGIN_LEFT, y, "Còn nợ:", font_body)
        y = _draw_right_text(draw, RECEIPT_WIDTH - MARGIN_RIGHT, y - LINE_HEIGHT, _format_vnd(remaining), font_body, (180, 0, 0))

    y = _draw_separator(draw, y)

    # Due date/time
    due_date = order_detail.get("due_date", "")
    due_time = order_detail.get("due_time", "") or ""
    if due_date:
        due_str = f"Ngày nhận: {due_date}"
        if due_time:
            due_str += f" {due_time}"
        y = _draw_text(draw, MARGIN_LEFT, y, due_str, font_body)

    # Delivery info
    delivery_type = order_detail.get("delivery_type", "pickup")
    delivery_type_display = "Nhận tại tiệm" if delivery_type == "pickup" else "Giao hàng"
    y = _draw_text(draw, MARGIN_LEFT, y, f"Hình thức: {delivery_type_display}", font_body)
    if delivery_type != "pickup" and delivery_address:
        addr_lines = _wrap_text(delivery_address, font_small, CONTENT_WIDTH)
        for line in addr_lines:
            y = _draw_text(draw, MARGIN_LEFT, y, f"  {line}", font_small)

    # Footer
    y = _draw_double_line(draw, y + 10)
    y = _draw_centered_text(draw, y, "Cảm ơn quý khách!", font_body, (100, 100, 100))

    # Crop to content
    bbox = img.getbbox()
    if bbox:
        img = img.crop((0, 0, RECEIPT_WIDTH, bbox[3] + MARGIN_BOTTOM))

    return img


def _order_detail(conn, row) -> dict:
    """Build full order detail dict including work items and payment transactions."""
    from baker.models.order import Order
    from baker.models.work_item import WorkItem

    order = Order.from_row(row, conn)
    result = order.to_api_dict()

    item_rows = conn.execute(
        "SELECT * FROM order_items WHERE order_id = ? ORDER BY position, id",
        (row["id"],),
    ).fetchall()
    result["workItems"] = [WorkItem.from_row(r).to_api_dict() for r in item_rows]
    result["id"] = row["id"]

    return result


@router.get("/{ref}/receipt")
def get_receipt(
    ref: str,
    type: str = Query(..., description="Receipt type: order, work_ticket, or customer"),
    item_id: Optional[int] = Query(None, description="Work item ID for work_ticket type"),
):
    """Generate receipt image for an order.

    Returns PNG image of the receipt.
    - type=order: Order summary receipt (internal use)
    - type=work_ticket: Work ticket for production (requires item_id)
    - type=customer: Clean customer-facing receipt
    """
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        order_detail = _order_detail(conn, row)
        shop_config = _get_shop_config(conn)

        # Render the appropriate receipt type
        if type == "order":
            img = _render_order_receipt(order_detail, shop_config, conn)
        elif type == "work_ticket":
            if item_id is None:
                raise HTTPException(status_code=400, detail="item_id is required for work_ticket type")
            # Find the work item (id may be string or int)
            work_item = None
            for wi in order_detail.get("workItems", []):
                if str(wi.get("id")) == str(item_id):
                    work_item = wi
                    break
            if not work_item:
                raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
            # Get photo for this work item
            photo_bytes = _get_order_photo_for_work_item(conn, row["id"], item_id)
            img = _render_work_ticket(order_detail, work_item, shop_config, photo_bytes, conn)
        elif type == "customer":
            img = _render_customer_receipt(order_detail, shop_config, conn)
        else:
            raise HTTPException(status_code=400, detail="Invalid receipt type: must be order, work_ticket, or customer")

        # Convert to PNG bytes
        buf = io.BytesIO()
        img.save(buf, format="PNG", quality=95)
        buf.seek(0)

        return StreamingResponse(
            iter([buf.getvalue()]),
            media_type="image/png",
            headers={"Content-Disposition": f"inline; filename=receipt-{ref}-{type}.png"},
        )
