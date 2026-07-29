"""Migration v037: _migrate_v37_price_bucket_consolidation (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v37_price_bucket_consolidation(conn):
    """Consolidate duplicate stock lots that share the same normalized price bucket."""
    required_tables = {"products", "stock_lots", "inventory_items"}
    existing_tables = {
        row["name"]
        for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    }
    if not required_tables.issubset(existing_tables):
        return

    product_rows = conn.execute("SELECT id, base_price FROM products").fetchall()
    for product_row in product_rows:
        product_id = int(product_row["id"])
        base_normalized = int(round(float(product_row["base_price"] or 0)))
        chip_rows = conn.execute(
            """SELECT id, price
               FROM product_price_chips
               WHERE product_id = ?
               ORDER BY position ASC, id ASC""",
            (product_id,),
        ).fetchall()
        chip_price_map = {
            int(chip_row["id"]): int(round(float(chip_row["price"] or 0))) for chip_row in chip_rows
        }

        lot_rows = conn.execute(
            """SELECT id, price_chip_id, quantity, remaining_qty, restocked_at
               FROM stock_lots
               WHERE product_id = ?
               ORDER BY restocked_at ASC, id ASC""",
            (product_id,),
        ).fetchall()
        if not lot_rows:
            continue

        bucket_map: dict[int, list] = {}
        for lot_row in lot_rows:
            chip_id = lot_row["price_chip_id"]
            normalized_price = base_normalized if chip_id is None else chip_price_map.get(int(chip_id), base_normalized)
            bucket_map.setdefault(normalized_price, []).append(lot_row)

        for bucket_lots in bucket_map.values():
            if len(bucket_lots) <= 1:
                continue

            canonical_lot = bucket_lots[0]
            canonical_lot_id = int(canonical_lot["id"])
            total_quantity = sum(int(lot["quantity"] or 0) for lot in bucket_lots)
            total_remaining = sum(int(lot["remaining_qty"] or 0) for lot in bucket_lots)

            for lot in bucket_lots[1:]:
                source_lot_id = int(lot["id"])
                conn.execute(
                    "UPDATE inventory_items SET lot_id = ? WHERE lot_id = ?",
                    (canonical_lot_id, source_lot_id),
                )
                conn.execute(
                    "UPDATE stock_movements SET lot_id = ? WHERE lot_id = ?",
                    (canonical_lot_id, source_lot_id),
                )
                conn.execute("DELETE FROM stock_lots WHERE id = ?", (source_lot_id,))

            conn.execute(
                "UPDATE stock_lots SET quantity = ?, remaining_qty = ?, price_chip_id = NULL WHERE id = ?",
                (total_quantity, total_remaining, canonical_lot_id),
            )
