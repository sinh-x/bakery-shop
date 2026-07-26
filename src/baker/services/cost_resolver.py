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

from typing import Optional

from baker.db.schema import PHU_KIEN_CATEGORY, _baseline_cost_for_product
from baker.utils.time import now_utc

# Return value when a product cannot be resolved (missing product or zero
# baseline). Downstream COGS logic treats 0 as "no cost" and skips journal
# entry creation for the corresponding line.
UNRESOLVED_COST = 0.0


def resolve_product_cost(
    conn,
    product_id: int,
    *,
    selling_price: Optional[float] = None,
    assigned_price: Optional[float] = None,
) -> float:
    """Resolve the effective cost for ``product_id`` at the current time.

    Resolution order:
      1. Latest ``cost_history`` row whose ``effective_from`` is on or before
         the current localtime. Future-dated records are skipped.
      2. Baseline rule derived from ``products.base_price`` and ``category``:
         100% of ``base_price`` for phụ kiện (unchanged), 30% of the anchor
         price otherwise. The anchor is selected with the following precedence
         (DG-296 Phase 2, FR5):

           a. ``assigned_price`` — when provided (> 0). Used for trưng bày
              products sold at a markup so COGS is anchored on the assigned
              price (base_price or selected price chip) rather than the
              marked-up ``selling_price`` (NFR1:
              COGS(250k sale, 200k assigned) == COGS(200k sale, 200k assigned)).
           b. ``selling_price`` — when provided (> 0) and no assigned_price.
              Preserves the DG-208 Phase 1 behaviour for custom-priced orders
              without an explicit assigned price.
           c. ``base_price`` — when neither is provided. Preserves the
              historical behaviour for callers that supply neither anchor
              (FR8 backward-compatibility).

    Args:
        conn: SQLite DB connection (row factory expected to support indexing).
        product_id: Product primary key.
        selling_price: Optional actual selling price used as the baseline anchor
            when no ``cost_history`` row is in effect and ``assigned_price`` is
            not provided. When ``None`` (the default) the baseline falls back
            to ``base_price × 30%`` (or ``assigned_price`` when given),
            preserving the historical behaviour for callers that do not supply
            it (FR1/FR8 backward-compatibility requirement).
        assigned_price: Optional assigned price (base_price or selected price
            chip) for trưng bày products sold at a markup. When provided (> 0)
            it takes precedence over ``selling_price`` as the baseline anchor so
            COGS reflects the assigned price rather than the marked-up selling
            price (FR5, NFR1). When ``None`` (the default) behaviour is
            unchanged — ``selling_price``/``base_price`` are used as before
            (FR8).

    Returns:
        Resolved cost as a non-negative ``float``. Returns ``0.0`` when the
        product does not exist or when the baseline resolves to 0 (e.g. a
        zero ``base_price``). Downstream callers treat 0 as "no cost" and
        skip COGS journal entry creation for the line.

    Notes:
        - Query-time fallback only; no rows are inserted into ``cost_history``.
        - The baseline helper rounds non-phụ-kiện costs to 2 decimals.
        - ``assigned_price`` is only consulted for non-phụ-kiện products; the
          phụ kiện 100% rule is intentional and unchanged (Non-Goal).
    """
    latest_row = conn.execute(
        """
        SELECT cost
        FROM cost_history
        WHERE product_id = ?
          AND effective_from <= ?
        ORDER BY effective_from DESC
        LIMIT 1
        """,
        (int(product_id), now_utc()),
    ).fetchone()
    if latest_row is not None:
        # Negative cost_history values are clamped to 0 so downstream cost_at_sale
        # and COGS journal logic never store negative costs (review finding m-2).
        return max(0.0, float(latest_row["cost"] or 0))

    product_row = conn.execute(
        "SELECT base_price, category FROM products WHERE id = ?",
        (int(product_id),),
    ).fetchone()
    if product_row is None:
        return UNRESOLVED_COST

    category = product_row["category"] if product_row["category"] is not None else ""
    base_price = float(product_row["base_price"] or 0)
    # Anchor precedence (DG-296 Phase 2, FR5):
    #   1. assigned_price — trưng bày markup → COGS from assigned price (NFR1)
    #   2. selling_price  — DG-208 Phase 1 custom-price anchor (FR1)
    #   3. base_price     — historical fallback (FR8)
    # A zero/negative value is treated as "not provided" so zero-priced orders
    # fall back to the next anchor rather than zeroing out COGS.
    if assigned_price is not None and assigned_price > 0:
        anchor = assigned_price
    elif selling_price is not None and selling_price > 0:
        anchor = selling_price
    else:
        anchor = None
    return _baseline_cost_for_product(category, base_price, price_override=anchor)


def is_phu_kien(category) -> bool:
    """Return True when ``category`` is the phụ kiện accessory slug.

    Provided as a convenience for callers (waste COGS, validation) that need
    to branch on the accessory category without importing the schema constant.
    """
    return category == PHU_KIEN_CATEGORY