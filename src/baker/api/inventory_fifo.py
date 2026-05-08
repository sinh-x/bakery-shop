"""Helpers for chip-aware inventory lots and FIFO consumption."""

import uuid

from fastapi import HTTPException


def normalize_price_chip(conn, product_id: int, price_chip_id: int | None) -> int | None:
    """Validate chip belongs to product; None means base-price stock."""
    if price_chip_id is None:
        return None
    row = conn.execute(
        "SELECT id FROM product_price_chips WHERE id = ? AND product_id = ?",
        (price_chip_id, product_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=422, detail="Mức giá không hợp lệ cho sản phẩm")
    return price_chip_id


def normalize_price_value(price_value: float | int | None) -> int:
    return int(round(float(price_value or 0)))


def product_base_normalized_price(conn, product_id: int) -> int:
    row = conn.execute(
        "SELECT base_price FROM products WHERE id = ?",
        (product_id,),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
    return normalize_price_value(row["base_price"])


def normalized_price_for_chip(conn, product_id: int, price_chip_id: int | None) -> int:
    if price_chip_id is None:
        return product_base_normalized_price(conn, product_id)
    chip_row = conn.execute(
        "SELECT price FROM product_price_chips WHERE id = ? AND product_id = ?",
        (price_chip_id, product_id),
    ).fetchone()
    if chip_row is None:
        raise HTTPException(status_code=422, detail="Mức giá không hợp lệ cho sản phẩm")
    return normalize_price_value(chip_row["price"])


def resolve_price_bucket_chip_id(conn, product_id: int, normalized_price: int) -> int | None:
    base_price = product_base_normalized_price(conn, product_id)
    if base_price == normalized_price:
        return None

    chip_rows = conn.execute(
        """SELECT id, price
           FROM product_price_chips
           WHERE product_id = ?
           ORDER BY position ASC, id ASC""",
        (product_id,),
    ).fetchall()
    for chip_row in chip_rows:
        if normalize_price_value(chip_row["price"]) == normalized_price:
            return int(chip_row["id"])

    raise HTTPException(status_code=422, detail="Mức giá không hợp lệ cho sản phẩm")


def resolve_price_bucket_option(
    conn,
    product_id: int,
    normalized_price: int | None,
    price_chip_id: int | None,
) -> tuple[int | None, int]:
    if normalized_price is not None:
        resolved_chip_id = resolve_price_bucket_chip_id(conn, product_id, normalized_price)
        return resolved_chip_id, int(normalized_price)

    resolved_chip_id = normalize_price_chip(conn, product_id, price_chip_id)
    resolved_price = normalized_price_for_chip(conn, product_id, resolved_chip_id)
    return resolved_chip_id, resolved_price


def create_lot_with_items(conn, product_id: int, price_chip_id: int | None, quantity: int) -> int:
    """Create one stock lot and N available inventory items."""
    cursor = conn.execute(
        """INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty)
           VALUES (?, ?, ?, ?)""",
        (product_id, price_chip_id, quantity, quantity),
    )
    lot_id = cursor.lastrowid
    conn.executemany(
        """INSERT INTO inventory_items (lot_id, uuid, status)
           VALUES (?, ?, 'available')""",
        [(lot_id, str(uuid.uuid4())) for _ in range(quantity)],
    )
    return lot_id


def consume_fifo_items(
    conn,
    product_id: int,
    price_chip_id: int | None,
    quantity: int,
    consumed_by_movement_id: int,
) -> None:
    """Consume available inventory using lot-first then item-first FIFO."""
    remaining = quantity
    lots = conn.execute(
        """SELECT id
           FROM stock_lots
           WHERE product_id = ?
             AND remaining_qty > 0
             AND ((price_chip_id IS NULL AND ? IS NULL) OR price_chip_id = ?)
           ORDER BY restocked_at ASC, id ASC""",
        (product_id, price_chip_id, price_chip_id),
    ).fetchall()

    for lot in lots:
        if remaining <= 0:
            break
        items = conn.execute(
            """SELECT id
               FROM inventory_items
               WHERE lot_id = ? AND status = 'available'
               ORDER BY created_at ASC, id ASC
               LIMIT ?""",
            (lot["id"], remaining),
        ).fetchall()
        if not items:
            continue

        item_ids = [row["id"] for row in items]
        placeholders = ", ".join(["?"] * len(item_ids))
        conn.execute(
            f"""UPDATE inventory_items
                SET status = 'consumed', consumed_by_movement_id = ?
                WHERE id IN ({placeholders})""",
            [consumed_by_movement_id] + item_ids,
        )
        consumed_count = len(item_ids)
        conn.execute(
            "UPDATE stock_lots SET remaining_qty = remaining_qty - ? WHERE id = ?",
            (consumed_count, lot["id"]),
        )
        remaining -= consumed_count

    if remaining > 0:
        raise HTTPException(status_code=422, detail="Không đủ tồn kho")


def available_quantity(conn, product_id: int, price_chip_id: int | None) -> int:
    """Count available items for a product stock option."""
    row = conn.execute(
        """SELECT COUNT(*) AS qty
           FROM inventory_items ii
           JOIN stock_lots sl ON sl.id = ii.lot_id
           WHERE sl.product_id = ?
             AND ii.status = 'available'
             AND ((sl.price_chip_id IS NULL AND ? IS NULL) OR sl.price_chip_id = ?)""",
        (product_id, price_chip_id, price_chip_id),
    ).fetchone()
    return int(row["qty"] if row else 0)
