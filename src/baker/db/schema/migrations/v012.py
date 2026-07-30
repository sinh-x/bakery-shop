"""Migration v012: _migrate_v12_data (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v12_data(conn):
    """Migrate orders.items JSON → order_items rows; amount_paid > 0 → deposit transaction."""
    import json

    rows = conn.execute("SELECT * FROM orders").fetchall()
    for row in rows:
        order_id = row["id"]

        # Migrate items JSON -> order_items
        items_json = row["items"]
        if items_json:
            try:
                items = json.loads(items_json)
            except (json.JSONDecodeError, TypeError):
                items = []
            for position, item in enumerate(items):
                conn.execute(
                    """INSERT OR IGNORE INTO order_items
                       (order_id, product_id, product_name, quantity, unit_price, notes, position)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        order_id,
                        item.get("product_id", ""),
                        item.get("product", ""),
                        item.get("qty", 1),
                        item.get("price", 0),
                        item.get("notes", ""),
                        position,
                    ),
                )

        # Migrate amount_paid > 0 → deposit transaction
        amount_paid = row["amount_paid"] or 0
        if amount_paid > 0:
            conn.execute(
                """INSERT INTO payment_transactions
                   (order_id, amount, type, method, note)
                   VALUES (?, ?, 'deposit', 'cash', 'Migrated from amount_paid')""",
                (order_id, amount_paid),
            )
