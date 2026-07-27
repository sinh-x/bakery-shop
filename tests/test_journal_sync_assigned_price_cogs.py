"""Integration tests for COGS resolution with ``assigned_price`` — DG-296 Phase 2.

Covers FR5, FR8, NFR1, AC2 at the journal_sync layer:

- ``_compute_order_cogs_total`` passes ``assigned_price`` to
  ``resolve_product_cost`` for trưng bày items sold at a markup, so COGS is
  anchored on the assigned price rather than the marked-up selling price.
- NFR1: COGS(250k sale, 200k assigned) == COGS(200k sale, 200k assigned).
- FR8: items without ``assigned_price`` keep the historical unit_price anchor.
"""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.journal_sync import _compute_order_cogs_total


_PRODUCT_SEQ = {"n": 0}


def _insert_product(conn, *, category="banh_mi", base_price=200000):
    _PRODUCT_SEQ["n"] += 1
    cur = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (f"SP-DG296-{_PRODUCT_SEQ['n']}", category, base_price, base_price),
    )
    return int(cur.lastrowid)


def _insert_order(conn, *, order_ref, total_price=0, status="delivered"):
    cur = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, total_price, status, due_date) "
        "VALUES (?, 'Khách thử', ?, ?, '2026-07-26')",
        (order_ref, total_price, status),
    )
    return int(cur.lastrowid)


def _add_order_item(
    conn,
    *,
    order_id,
    product_id,
    unit_price,
    assigned_price=None,
    qty=1,
    cost_at_sale=0,
):
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, "
        " position, status, cost_at_sale, is_extra, is_gift, assigned_price) "
        "VALUES (?, ?, 'Bánh mì', ?, ?, 0, 'delivered', ?, 0, 0, ?)",
        (order_id, product_id, qty, unit_price, cost_at_sale, assigned_price),
    )


def _cogs(conn, order_id, *, force=True) -> float:
    """Compute COGS via the live journal_sync path (force=True so the
    baseline anchor runs even when cost_at_sale is 0)."""
    return _compute_order_cogs_total(
        conn, order_id, populate_cost_at_sale=False, force=force
    )


def test_cogs_uses_assigned_price_for_trung_bay_markup():
    """AC2: trưng bày product base_price 200,000 sold at 250,000 with
    assigned_price=200,000 → COGS = 30% × 200,000 = 60,000 (not 75,000)."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, base_price=200000)
        oid = _insert_order(conn, order_ref="ORD-DG296-AC2", total_price=250000)
        _add_order_item(
            conn,
            order_id=oid,
            product_id=pid,
            unit_price=250000,
            assigned_price=200000,
        )
        conn.commit()
        assert _cogs(conn, oid) == 60.0 * 1000


def test_nfr1_cogs_equivalence_at_journal_sync_layer():
    """NFR1: COGS(250k sale, 200k assigned) == COGS(200k sale, 200k assigned).
    The marked-up selling price must not affect COGS when assigned_price is
    set on the order item."""
    with get_db() as conn:
        ensure_schema(conn)
        pid_a = _insert_product(conn, base_price=200000)
        pid_b = _insert_product(conn, base_price=200000)
        oid_markup = _insert_order(conn, order_ref="ORD-DG296-MARKUP", total_price=250000)
        _add_order_item(
            conn,
            order_id=oid_markup,
            product_id=pid_a,
            unit_price=250000,
            assigned_price=200000,
        )
        oid_flat = _insert_order(conn, order_ref="ORD-DG296-FLAT", total_price=200000)
        _add_order_item(
            conn,
            order_id=oid_flat,
            product_id=pid_b,
            unit_price=200000,
            assigned_price=200000,
        )
        conn.commit()
        assert _cogs(conn, oid_markup) == _cogs(conn, oid_flat)


def test_fr8_no_assigned_price_uses_unit_price_anchor():
    """FR8: items without assigned_price keep the DG-208 Phase 1 behaviour
    (unit_price as the baseline anchor) — regression-free."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, base_price=100000)
        oid = _insert_order(conn, order_ref="ORD-DG296-FR8", total_price=200000)
        _add_order_item(
            conn,
            order_id=oid,
            product_id=pid,
            unit_price=200000,
            assigned_price=None,
        )
        conn.commit()
        # 30% of unit_price 200000 = 60000 (not 30% of base_price 100000)
        assert _cogs(conn, oid) == 60.0 * 1000


def test_ac5_chip_price_assigned_anchor_at_journal_sync_layer():
    """AC5 (Phase 2 partial): trưng bày product with a price chip of 300,000
    (assigned_price=300,000) marked up to 350,000 → COGS = 30% × 300,000 =
    90,000."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, base_price=200000)
        oid = _insert_order(conn, order_ref="ORD-DG296-AC5", total_price=350000)
        _add_order_item(
            conn,
            order_id=oid,
            product_id=pid,
            unit_price=350000,
            assigned_price=300000,
        )
        conn.commit()
        assert _cogs(conn, oid) == 90.0 * 1000
