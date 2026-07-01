"""Public stock service helpers used by order-related APIs."""

import json

from fastapi import HTTPException

from baker.api.inventory_fifo import (
    consume_fifo_items,
    create_lot_with_items,
    normalize_price_value,
    normalize_price_chip,
    resolve_price_bucket_chip_id,
)
from baker.models.event import Event
from baker.utils.time import now_utc


def _order_sale_was_deducted(conn, order_ref: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM stock_movements WHERE reference_id = ? AND movement_type = 'sale' LIMIT 1",
        (order_ref,),
    ).fetchone()
    return row is not None


def auto_decrement_stock(conn, order_id: int, order_ref: str) -> None:
    """Auto-decrement stock for trung bay products when order is delivered/completed.

    Idempotent: skips deduction if a sale movement already exists for this order."""
    if _order_sale_was_deducted(conn, order_ref):
        return

    order_items = conn.execute(
        """SELECT oi.product_id, oi.product_name, oi.quantity, oi.price_chip_id, oi.unit_price, oi.attributes, o.source
           FROM order_items oi
           JOIN orders o ON o.id = oi.order_id
           WHERE oi.order_id = ?
             AND oi.product_id != ''
             AND oi.is_gift = 0""",
        (order_id,),
    ).fetchall()

    for item in order_items:
        code_or_id = item["product_id"]
        product_row = conn.execute(
            "SELECT id FROM products WHERE product_code = ?",
            (code_or_id,),
        ).fetchone()
        if not product_row:
            try:
                product_row = conn.execute(
                    "SELECT id FROM products WHERE id = ?",
                    (int(code_or_id),),
                ).fetchone()
            except (ValueError, TypeError):
                continue
        if not product_row:
            continue

        product_id = product_row["id"]
        qty = item["quantity"]
        explicit_chip_id = item["price_chip_id"]
        if explicit_chip_id is not None:
            chip_id = normalize_price_chip(conn, product_id, explicit_chip_id)
        else:
            normalized_unit_price = normalize_price_value(item["unit_price"])
            try:
                chip_id = resolve_price_bucket_chip_id(
                    conn,
                    product_id,
                    normalized_unit_price,
                )
            except HTTPException:
                chip_id = None

        attr_row = conn.execute(
            """SELECT value FROM product_attribute_values
               WHERE product_id = ? AND attribute_type = 'trung_bay'""",
            (product_id,),
        ).fetchone()
        if not attr_row or attr_row["value"] != "true":
            continue

        attrs = {}
        if item["attributes"]:
            if isinstance(item["attributes"], str):
                try:
                    attrs = json.loads(item["attributes"])
                except json.JSONDecodeError:
                    attrs = {}
            elif isinstance(item["attributes"], dict):
                attrs = item["attributes"]

        has_use_inventory = "useInventory" in attrs
        use_inventory = attrs.get("useInventory")
        if isinstance(use_inventory, str):
            use_inventory_enabled = use_inventory.lower() == "true"
        else:
            use_inventory_enabled = use_inventory is True

        is_pos_order = item["source"] == "Tại tiệm - POS"
        is_reconciliation_order = item["source"] == "reconciliation"
        default_consume_sources = is_pos_order or is_reconciliation_order
        should_consume_fifo = use_inventory_enabled if has_use_inventory else default_consume_sources

        movement_cursor = conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
               VALUES (?, 'sale', ?, ?, ?, ?, ?)""",
            (product_id, -qty, f"Order {order_ref}", order_ref, chip_id, now_utc()),
        )
        movement_id = movement_cursor.lastrowid
        if should_consume_fifo:
            consume_fifo_items(conn, product_id, chip_id, qty, movement_id)

        if should_consume_fifo:
            lot_row = conn.execute(
                "SELECT lot_id FROM inventory_items WHERE consumed_by_movement_id = ? ORDER BY id ASC LIMIT 1",
                (movement_id,),
            ).fetchone()
            if lot_row:
                conn.execute(
                    "UPDATE stock_movements SET lot_id = ? WHERE id = ?",
                    (lot_row["lot_id"], movement_id),
                )

        Event(
            summary=f"Ban hang -{qty} {item['product_name']}",
            type="inventory",
            data={
                "product_id": product_id,
                "product_name": item["product_name"],
                "movement_type": "sale",
                "quantity": -qty,
                "reference_id": order_ref,
                "price_chip_id": chip_id,
            },
        ).save(conn)


def restore_stock_for_order(conn, order_id: int, order_ref: str) -> None:
    """Reverse stock deductions for a cancelled order.

    Idempotent: skips if no sale movement exists or a restore already happened."""
    sale_movements = conn.execute(
        """SELECT id, product_id, price_chip_id, quantity
           FROM stock_movements
           WHERE reference_id = ? AND movement_type = 'sale'""",
        (order_ref,),
    ).fetchall()

    for movement in sale_movements:
        qty = -movement["quantity"]
        chip_id = movement["price_chip_id"]

        already_restored = conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? AND movement_type = 'restore_sale' AND product_id = ? AND price_chip_id IS NOT DISTINCT FROM ? LIMIT 1",
            (order_ref, movement["product_id"], chip_id),
        ).fetchone()
        if already_restored:
            continue

        restore_cursor = conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
               VALUES (?, 'restore_sale', ?, ?, ?, ?, ?)""",
            (movement["product_id"], qty, f"Restore order {order_ref}", order_ref, chip_id, now_utc()),
        )
        restore_movement_id = restore_cursor.lastrowid
        create_lot_with_items(conn, movement["product_id"], chip_id, qty)

        Event(
            summary=f"Hoan hang +{qty} (order {order_ref})",
            type="inventory",
            data={
                "product_id": movement["product_id"],
                "movement_type": "restore_sale",
                "quantity": qty,
                "reference_id": order_ref,
                "price_chip_id": chip_id,
            },
        ).save(conn)
