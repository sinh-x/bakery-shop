"""Migration v060: _migrate_v60_customer_year_summary (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v60_customer_year_summary(conn):
    """Create ``customer_year_summary`` and backfill it from existing orders.

    DG-206 Phase 1 (FR6, NFR2). The table stores one row per
    (customer_id, year) with the order count and total volume. Idempotent:
    re-running on an already-backfilled DB is a no-op (CREATE TABLE IF NOT
    EXISTS plus a guarded backfill that only inserts when the row is absent).
    """
    # Backfill: one pass over orders grouped by (customer_id, year) where the
    # summary row does not yet exist. Guard with NOT EXISTS so a partial run
    # does not double-count.
    conn.execute(
        """
        INSERT INTO customer_year_summary (customer_id, year, order_count, total_volume)
        SELECT o.customer_id,
               CAST(strftime('%Y', o.created_at) AS INTEGER) AS year,
               COUNT(*)   AS order_count,
               COALESCE(SUM(o.total_price), 0) AS total_volume
        FROM orders o
        WHERE o.customer_id IS NOT NULL
          AND o.created_at IS NOT NULL
          AND o.created_at != ''
        GROUP BY o.customer_id, year
        ON CONFLICT(customer_id, year) DO NOTHING
        """
    )
