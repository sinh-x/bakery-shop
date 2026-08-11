"""Config, label, order-reference, and header helpers for receipt rendering."""



from typing import Optional

import baker.config
from ._drawing import *  # noqa: F401,F403

def _shop_config(conn) -> dict:
    cfg = dict(_SHOP_DEFAULTS)
    rows = conn.execute(
        "SELECT config_key, config_value FROM app_config WHERE config_key LIKE 'receipt_%'"
    ).fetchall()
    for r in rows:
        if r["config_key"] in cfg:
            cfg[r["config_key"]] = r["config_value"]
    return cfg

# DG-361 Phase 4.3: candle type display labels for backend receipt renderers.
# Mirrors `VN.candleTypeLabel()` in `vietnamese_labels.dart`. Raw value is
# returned for unknown keys so unexpected stored values remain visible rather
# than blank.
CANDLE_TYPE_LABELS = {
    "nen_so": "Nến số",
    "nen_xoan": "Nến xoắn",
    "nen_nho": "Nến nhỏ",
    "khong_nen": "Không nến",
}


def _candle_type_label(value) -> str:
    """Return the Vietnamese display label for a stored `candle_type` value.

    Returns empty string when `value` is None/empty/`khong_nen` so callers can
    skip rendering the candle line entirely (AC8, AC9).
    """
    if value is None:
        return ""
    s = str(value).strip()
    if not s or s == "khong_nen":
        return ""
    return CANDLE_TYPE_LABELS.get(s, s)


def _candle_type_value(item: dict) -> str:
    """Return the trimmed candle_type stored on an item, or empty string.

    Reads from `attributes['candle_type']` (camelCase or snake_case `attributes`
    keys are both supported via `.get`).
    """
    attrs = item.get("attributes") or {}
    raw = attrs.get("candle_type") or attrs.get("candleType") or ""
    return str(raw).strip()


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

def _delivery_phone_value(order: dict) -> str:
    """Return trimmed delivery phone from order dict (camelCase or snake_case)."""
    raw = order.get("deliveryPhone", "") or order.get("delivery_phone", "") or ""
    return str(raw).strip()

def _phones_differ(customer_phone: str, delivery_phone: str) -> bool:
    """True when delivery_phone is non-empty and its digits differ from customer phone.

    DG-283 Phase 4 / FR11: digit-only comparison so format differences
    ("0972 283 134" vs "0972-283-134") do not count as a difference.
    Returns False when delivery phone is blank or identical — callers then
    render a single phone (no duplication).
    """
    d = (delivery_phone or "").strip()
    if not d:
        return False
    c_digits = "".join(c for c in (customer_phone or "") if c.isdigit())
    d_digits = "".join(c for c in d if c.isdigit())
    if not d_digits:
        return False
    return d_digits != c_digits

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


__all__ = [
    '_shop_config',
    'CANDLE_TYPE_LABELS',
    '_candle_type_label',
    '_candle_type_value',
    '_enum_attribute_labels',
    '_enum_attribute_lines',
    '_wrapped_enum_attribute_lines',
    '_delivery_phone_value',
    '_phones_differ',
    '_order_public_code',
    '_order_ref_value',
    '_order_visual_ref',
    '_main_item_index_total',
    '_customer_name_value',
    '_customer_last_word',
    '_customer_reference_text',
    '_customer_heading_text',
    '_shop_delivery_code_text',
    '_draw_compact_reference_box',
    '_header',
    '_get_photo',
]
