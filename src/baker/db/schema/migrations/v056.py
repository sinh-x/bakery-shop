"""Migration v056: _migrate_v56_customers_and_order_link (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v56_customers_and_order_link(conn):
    """Create customers table, add customer_id FK to orders, auto-link existing
    orders to customers by phone match (DG-182 Phase 1).

    Phone is NOT unique — multiple customers may share a phone (NFR4). Auto-match
    links each existing order to the first customer (lowest id) sharing that
    phone. Orders with no phone or no matching customer remain customer_id=NULL.
    """
    # 1) Add customer_id column to orders (nullable FK)
    _guard_add_column(conn, "orders", "customer_id", "customer_id INTEGER REFERENCES customers(id)")

    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id)"
    )

    # 2) Auto-link existing orders to customers by phone match.
    #    For each distinct phone that matches at least one customer, link orders
    #    with that phone to the lowest-id customer sharing the phone. Only link
    #    non-empty phones to avoid matching all walk-in orders together.
    conn.execute(
        """
        UPDATE orders
        SET customer_id = (
            SELECT MIN(c.id) FROM customers c
            WHERE c.phone = orders.customer_phone
              AND c.phone != ''
              AND c.phone IS NOT NULL
        )
        WHERE customer_id IS NULL
          AND customer_phone != ''
          AND customer_phone IS NOT NULL
          AND EXISTS (
              SELECT 1 FROM customers c
              WHERE c.phone = orders.customer_phone
                AND c.phone != ''
                AND c.phone IS NOT NULL
          )
        """
    )
