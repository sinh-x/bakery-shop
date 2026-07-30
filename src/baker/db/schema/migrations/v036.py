"""Migration v036: _migrate_v36_chip_aware_inventory (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v36_chip_aware_inventory(conn):
    """Migrate product_stock rows into stock_lots + inventory_items using lowest-priced option."""
    import uuid

    def _table_exists(table_name: str) -> bool:
        exists_row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
            (table_name,),
        ).fetchone()
        return exists_row is not None

    if _table_exists("stock_movements"):
        _guard_add_column(
            conn,
            "stock_movements",
            "lot_id",
            "lot_id INTEGER REFERENCES stock_lots(id)",
        )
        _guard_add_column(
            conn,
            "stock_movements",
            "price_chip_id",
            "price_chip_id INTEGER REFERENCES product_price_chips(id)",
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_stock_movements_lot ON stock_movements(lot_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_stock_movements_product_chip_created "
            "ON stock_movements(product_id, price_chip_id, created_at)"
        )

    if _table_exists("order_items"):
        _guard_add_column(
            conn,
            "order_items",
            "price_chip_id",
            "price_chip_id INTEGER REFERENCES product_price_chips(id)",
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_order_items_price_chip ON order_items(price_chip_id)"
        )

    if _table_exists("reconciliation_lines"):
        _guard_add_column(
            conn,
            "reconciliation_lines",
            "price_chip_id",
            "price_chip_id INTEGER REFERENCES product_price_chips(id)",
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_reconciliation_lines_price_chip ON reconciliation_lines(price_chip_id)"
        )

    has_product_stock = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='product_stock'"
    ).fetchone()
    if has_product_stock:
        rows = conn.execute(
            "SELECT product_id, quantity FROM product_stock ORDER BY product_id"
        ).fetchall()

        for row in rows:
            product_id = int(row["product_id"])
            quantity = int(row["quantity"] or 0)

            base_row = conn.execute(
                "SELECT base_price FROM products WHERE id = ?",
                (product_id,),
            ).fetchone()
            if base_row is None:
                continue

            best_chip_id = None
            best_price = float(base_row["base_price"] or 0)

            chip_rows = conn.execute(
                "SELECT id, price FROM product_price_chips WHERE product_id = ? ORDER BY id",
                (product_id,),
            ).fetchall()
            for chip in chip_rows:
                chip_price = float(chip["price"] or 0)
                if chip_price < best_price:
                    best_price = chip_price
                    best_chip_id = int(chip["id"])

            lot_cursor = conn.execute(
                """INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty)
                   VALUES (?, ?, ?, ?)""",
                (product_id, best_chip_id, quantity, quantity),
            )
            lot_id = int(lot_cursor.lastrowid)

            for _ in range(quantity):
                conn.execute(
                    """INSERT INTO inventory_items (lot_id, uuid, status)
                       VALUES (?, ?, 'available')""",
                    (lot_id, str(uuid.uuid4())),
                )

        conn.execute("DROP TABLE product_stock")
