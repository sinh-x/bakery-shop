"""Cost resolution service.

Resolves the effective cost of a product at the current time by consulting
``cost_history`` and applying the documented baseline fallback rule when no
historical cost record is in effect.

Baseline rule (mirrors ``baker.db.schema._baseline_cost_for_product``):
    - Phụ kiện category (``phu_kien``): 100% of ``base_price``
    - All other categories: 30% of ``base_price``

This module is the canonical query-time entry point for cost resolution used by
COGS journal entry generation (order delivery, waste/disposal) so that historical
costs can be tracked without seeding baseline rows into ``cost_history``.
"""

from baker.db.schema import PHU_KIEN_CATEGORY, _baseline_cost_for_product

# Return value when a product cannot be resolved (missing product or zero
# baseline). Downstream COGS logic treats 0 as "no cost" and skips journal
# entry creation for the corresponding line.
UNRESOLVED_COST = 0.0


def resolve_product_cost(conn, product_id: int) -> float:
    """Resolve the effective cost for ``product_id`` at the current time.

    Resolution order:
      1. Latest ``cost_history`` row whose ``effective_from`` is on or before
         the current localtime. Future-dated records are skipped.
      2. Baseline rule derived from ``products.base_price`` and ``category``:
         100% of ``base_price`` for phụ kiện, 30% otherwise.

    Args:
        conn: SQLite DB connection (row factory expected to support indexing).
        product_id: Product primary key.

    Returns:
        Resolved cost as a non-negative ``float``. Returns ``0.0`` when the
        product does not exist or when the baseline resolves to 0 (e.g. a
        zero ``base_price``). Downstream callers treat 0 as "no cost" and
        skip COGS journal entry creation for the line.

    Notes:
        - Query-time fallback only; no rows are inserted into ``cost_history``.
        - The baseline helper rounds non-phụ-kiện costs to 2 decimals.
    """
    latest_row = conn.execute(
        """
        SELECT cost
        FROM cost_history
        WHERE product_id = ?
          AND effective_from <= strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')
        ORDER BY effective_from DESC
        LIMIT 1
        """,
        (int(product_id),),
    ).fetchone()
    if latest_row is not None:
        return float(latest_row["cost"] or 0)

    product_row = conn.execute(
        "SELECT base_price, category FROM products WHERE id = ?",
        (int(product_id),),
    ).fetchone()
    if product_row is None:
        return UNRESOLVED_COST

    category = product_row["category"] if product_row["category"] is not None else ""
    base_price = float(product_row["base_price"] or 0)
    return _baseline_cost_for_product(category, base_price)


def is_phu_kien(category) -> bool:
    """Return True when ``category`` is the phụ kiện accessory slug.

    Provided as a convenience for callers (waste COGS, validation) that need
    to branch on the accessory category without importing the schema constant.
    """
    return category == PHU_KIEN_CATEGORY