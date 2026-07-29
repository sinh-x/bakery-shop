"""Shared test helpers for DG-297 (extras COGS) phase tests.

Used by:
- tests/test_dg297_phase2_extras_cogs.py
- tests/test_dg297_phase3_cancellation.py
- tests/test_dg297_phase4_validation.py

These helpers were extracted from the per-phase test modules to remove
duplicated scaffolding (CQ-2 re-review finding).
"""

_PRODUCT_SEQ = {"n": 0}


def reset_product_seq() -> None:
    """Reset the shared product-name counter.

    Each test module uses its own name prefix so the counter is shared across
    modules but the generated names remain unique. Tests that need a
    deterministic counter can call this explicitly.
    """
    _PRODUCT_SEQ["n"] = 0


def _insert_product(
    conn,
    *,
    name=None,
    category="banh_mi",
    base_price=100000,
    name_prefix="SP-DG297",
):
    _PRODUCT_SEQ["n"] += 1
    if name is None:
        name = f"{name_prefix}-{_PRODUCT_SEQ['n']}"
    cur = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (name, category, base_price, base_price),
    )
    return int(cur.lastrowid)


def _insert_order(
    conn,
    *,
    order_ref,
    total_price=0,
    status="delivered",
    customer_name="Khách thử",
):
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, ?, ?, ?, '2026-07-29')",
        (order_ref, customer_name, total_price, status),
    )
    return int(cur.lastrowid)


def _add_item(
    conn,
    *,
    order_id,
    product_id,
    product_name="Bánh mì",
    qty=1,
    unit_price=100000,
    cost_at_sale=0,
    is_extra=0,
    is_gift=0,
):
    cur = conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift) "
        "VALUES (?, ?, ?, ?, ?, 0, 'delivered', ?, ?, ?)",
        (order_id, product_id, product_name, qty, unit_price,
         cost_at_sale, is_extra, is_gift),
    )
    return int(cur.lastrowid)