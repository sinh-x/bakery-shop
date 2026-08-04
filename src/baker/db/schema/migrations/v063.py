"""Migration v063: _migrate_v63_repair_zero_cogs_and_missing_entries (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v63_repair_zero_cogs_and_missing_entries(conn):
    """Repair zero-cost order_items and missing order_cogs journal entries.

    DG-208 Phase 2. After Phase 1 changed the baseline anchor from base_price
    to unit_price, historical order_items with cost_at_sale=0 needed repair:
    - 117 delivered/completed order_items had cost_at_sale=0 (some because the
      product code like 'BKS-DG-01' has no products row, others because v45
      backfill ran before unit_price was used as the anchor).
    - 95 delivered/completed orders had no order_cogs journal entry (including
      Order #1091) — these items were never populated because the old resolver
      returned 0 and _sync_delivered_order_journal skipped journal insertion
      when total_cogs was 0.

    This migration:
      1. Re-runs _backfill_order_items_cost_at_sale() — now unit_price-anchored
         — to repair the 117 zero-cost order_items (FR2, NFR2).
      2. Re-runs _sync_delivered_order_journal() for every delivered/completed
         order to create the missing order_cogs entries (AC4 — Order #1091).

    Idempotent: the backfill only updates rows where cost_at_sale is still 0;
    _sync_delivered_order_journal skips orders that already have an order_cogs
    entry.
    """
    _seed_chart_of_accounts(conn)
    from baker.services.journal_sync import _sync_delivered_order_journal

    _backfill_order_items_cost_at_sale(conn)

    orders = conn.execute(
        """
        SELECT id, order_ref
        FROM orders
        WHERE status IN ('delivered', 'completed')
        ORDER BY id
        """
    ).fetchall()
    for o in orders:
        _sync_delivered_order_journal(conn, int(o["id"]), o["order_ref"])
