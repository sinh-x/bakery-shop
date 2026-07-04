"""Public stock service helpers used by order-related APIs."""

import json

from fastapi import HTTPException

from baker.api.inventory_fifo import (
    consume_fifo_items,
    create_lot_with_items,
    normalize_price_value,
    normalize_price_chip,
    resolve_price_bucket_chip_id,
    upsert_negative_balance,
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
        # POS and reconciliation sources allow negative stock: oversold qty
        # is tracked in negative_balance (DG-200 Phase 2, FR-3). Non-POS
        # sources keep the historical FIFO-blocks-at-zero behaviour (NFR-3).
        allow_negative = is_pos_order or is_reconciliation_order

        movement_cursor = conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
               VALUES (?, 'sale', ?, ?, ?, ?, ?)""",
            (product_id, -qty, f"Order {order_ref}", order_ref, chip_id, now_utc()),
        )
        movement_id = movement_cursor.lastrowid
        deficit = 0
        if should_consume_fifo:
            deficit = consume_fifo_items(
                conn, product_id, chip_id, qty, movement_id,
                allow_negative=allow_negative,
            )

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

        # When a deficit remains, record a negative_sale movement and upsert
        # the negative_balance row. The 'sale' movement above captures the
        # full sold qty (FIFO-consumed portion); the 'negative_sale' movement
        # captures the oversold portion (AC-6).
        if deficit > 0:
            negative_movement_cursor = conn.execute(
                """INSERT INTO stock_movements
                   (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
                   VALUES (?, 'negative_sale', ?, ?, ?, ?, ?)""",
                (product_id, -deficit, f"Order {order_ref} (negative)", order_ref, chip_id, now_utc()),
            )
            negative_movement_id = negative_movement_cursor.lastrowid
            upsert_negative_balance(conn, product_id, chip_id, deficit)
            Event(
                summary=f"Ban am -{deficit} {item['product_name']}",
                type="inventory",
                data={
                    "product_id": product_id,
                    "product_name": item["product_name"],
                    "movement_type": "negative_sale",
                    "quantity": -deficit,
                    "reference_id": order_ref,
                    "price_chip_id": chip_id,
                    "movement_id": negative_movement_id,
                },
            ).save(conn)

            # DG-200 Phase 4, AC-8: COGS journal entry for the oversold
            # quantity. Mirrors the waste COGS sync pattern (DR COGS / CR
            # Inventory). Fire-and-forget: accounting failures never block
            # the primary sale operation (NFR1).
            from baker.services.journal_sync import (
                _sync_negative_sale_cogs_journal,
                run_journal_sync,
            )

            run_journal_sync(
                _sync_negative_sale_cogs_journal,
                conn, product_id, negative_movement_id, deficit,
                log_label=(
                    f"negative sale cogs sync for movement {negative_movement_id}"
                ),
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
        product_id = movement["product_id"]

        already_restored = conn.execute(
            "SELECT 1 FROM stock_movements WHERE reference_id = ? AND movement_type = 'restore_sale' AND product_id = ? AND price_chip_id IS NOT DISTINCT FROM ? LIMIT 1",
            (order_ref, product_id, chip_id),
        ).fetchone()
        if already_restored:
            continue

        # If a matching negative_sale exists, only the FIFO-consumed portion
        # was taken from lots; the deficit portion was recorded as negative
        # balance and must be reversed by reducing negative_balance (not by
        # creating new lot items, which would inflate stock).
        negative_row = conn.execute(
            """SELECT id, quantity FROM stock_movements
               WHERE reference_id = ? AND movement_type = 'negative_sale'
                 AND product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?
               LIMIT 1""",
            (order_ref, product_id, chip_id),
        ).fetchone()
        deficit = -int(negative_row["quantity"]) if negative_row else 0
        fifo_consumed_qty = qty - deficit

        restore_cursor = conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
               VALUES (?, 'restore_sale', ?, ?, ?, ?, ?)""",
            (product_id, qty, f"Restore order {order_ref}", order_ref, chip_id, now_utc()),
        )
        restore_movement_id = restore_cursor.lastrowid
        if fifo_consumed_qty > 0:
            create_lot_with_items(conn, product_id, chip_id, fifo_consumed_qty)
        if deficit > 0:
            conn.execute(
                """UPDATE negative_balance
                   SET qty = qty - ?, updated_at = ?
                   WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?""",
                (deficit, now_utc(), product_id, chip_id),
            )

        Event(
            summary=f"Hoan hang +{qty} (order {order_ref})",
            type="inventory",
            data={
                "product_id": product_id,
                "movement_type": "restore_sale",
                "quantity": qty,
                "reference_id": order_ref,
                "price_chip_id": chip_id,
            },
        ).save(conn)
