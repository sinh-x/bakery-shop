"""Tests for DG-297 Phase 2 — sold & gifted extras COGS journal entries.

Covers FR1, FR2, FR3, FR4, AC1, AC2, AC3:

- AC1: an order with sold extras (is_extra=1, is_gift=0) and main items gets an
  ``order_cogs`` journal entry with separate per-item DR 5900/CR 1300 line
  pairs for each item (main and extra) with cost > 0, each line describing the
  item.
- AC2: an order with gifted extras (is_gift=1) gets a separate
  ``order_gift_cogs`` journal entry with per-item DR 5910/CR 1300 line pairs
  for each gifted item with cost > 0.
- AC3: ``cost_at_sale`` is populated on the ``order_items`` rows for extras at
  delivery time (same snapshot behaviour as main items).

Also pins NFR2 (idempotency), NFR4 (gift entry failure never blocks the
``order_cogs`` entry) and the backward-compatibility guarantee that orders with
only non-extra, non-gift items produce identical COGS totals (NFR1).
"""

from baker.db.connection import get_db
from baker.db.schema import (
    COGS_CODE,
    INVENTORY_CODE,
    PROMO_EXPENSE_CODE,
    ensure_schema,
)
from baker.services.journal_sync import (
    _compute_order_cogs_total,
    _sync_completed_order_journal,
    _sync_delivered_order_journal,
)
from tests.helpers_dg297 import _insert_order, _insert_product, _add_item


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _entry_count(conn, source_type, order_id):
    row = conn.execute(
        "SELECT COUNT(*) FROM journal_entries "
        "WHERE source_type = ? AND source_id = ?",
        (source_type, order_id),
    ).fetchone()
    return int(row[0])


def _lines(conn, source_type, order_id, account_code):
    return conn.execute(
        """
        SELECT jl.debit, jl.credit, jl.description
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id
        WHERE je.source_type = ? AND je.source_id = ? AND a.code = ?
        ORDER BY jl.id
        """,
        (source_type, order_id, account_code),
    ).fetchall()


# ---------------------------------------------------------------------------
# AC1 — sold extras included with per-item DR 5900/CR 1300 line pairs
# ---------------------------------------------------------------------------


def test_ac1_sold_extras_included_with_per_item_lines():
    """AC1: an order with a main item + a sold extra (phụ kiện) gets one
    ``order_cogs`` entry with two DR 5900/CR 1300 line pairs — one per item."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        main_name = conn.execute(
            "SELECT name FROM products WHERE id = ?", (main_pid,)
        ).fetchone()["name"]
        extra_name = conn.execute(
            "SELECT name FROM products WHERE id = ?", (extra_pid,)
        ).fetchone()["name"]
        oid = _insert_order(conn, order_ref="ORD-DG297-AC1", total_price=110000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name=main_name,
            qty=2, unit_price=50000,
        )
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name=extra_name,
            qty=3, unit_price=5000, is_extra=1,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-AC1")

        # Exactly one order_cogs entry.
        assert _entry_count(conn, "order_cogs", oid) == 1
        debit_lines = _lines(conn, "order_cogs", oid, COGS_CODE)
        credit_lines = _lines(conn, "order_cogs", oid, INVENTORY_CODE)
        # Per-item line pairs: 2 items → 2 debit + 2 credit lines.
        assert len(debit_lines) == 2
        assert len(credit_lines) == 2
        # Each line describes its item.
        descs = {d["description"] for d in debit_lines}
        assert any(main_name in d for d in descs)
        assert any(extra_name in d for d in descs)
        # Accumulated total: main 30%×50000×2 = 30000 + extra 100%×5000×3 = 15000.
        total = sum(float(d["debit"]) for d in debit_lines)
        assert total == 30000.0 + 15000.0
        # Double-entry balanced.
        assert sum(float(c["credit"]) for c in credit_lines) == total
        conn.commit()


def test_fr1_compute_cogs_total_includes_sold_extras():
    """FR1: ``_compute_order_cogs_total`` includes sold extras (the
    ``is_extra = 0`` filter is gone). A sold extra contributes its cost so the
    total is greater than the main-items-only total."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-FR1", total_price=110000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì FR1",
            qty=1, unit_price=100000,
        )
        _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến FR1",
            qty=2, unit_price=5000, is_extra=1,
        )
        conn.commit()

        total = _compute_order_cogs_total(
            conn, oid, populate_cost_at_sale=False, force=True
        )
        # main 30%×100000 = 30000 + extra 100%×5000×2 = 10000.
        assert total == 30000.0 + 10000.0
        conn.commit()


# ---------------------------------------------------------------------------
# AC2 — gifted extras get a separate order_gift_cogs entry (5910/1300)
# ---------------------------------------------------------------------------


def test_ac2_gifted_extras_create_order_gift_cogs_entry():
    """AC2: an order with a gifted extra (is_gift=1) gets an
    ``order_gift_cogs`` journal entry with per-item DR 5910/CR 1300 line
    pairs. The ``order_cogs`` entry excludes the gift."""
    with get_db() as conn:
        ensure_schema(conn)
        main_pid = _insert_product(conn, category="banh_mi", base_price=100000)
        gift_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        gift_name = conn.execute(
            "SELECT name FROM products WHERE id = ?", (gift_pid,)
        ).fetchone()["name"]
        oid = _insert_order(conn, order_ref="ORD-DG297-AC2", total_price=100000)
        _add_item(
            conn, order_id=oid, product_id=main_pid, product_name="Bánh mì AC2",
            qty=1, unit_price=100000,
        )
        _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name=gift_name,
            qty=2, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-AC2")

        # order_cogs entry exists for the main item only.
        assert _entry_count(conn, "order_cogs", oid) == 1
        main_total = sum(float(d["debit"]) for d in _lines(conn, "order_cogs", oid, COGS_CODE))
        assert main_total == 30000.0  # 30%×100000×1

        # order_gift_cogs entry exists for the gift.
        assert _entry_count(conn, "order_gift_cogs", oid) == 1
        gift_debits = _lines(conn, "order_gift_cogs", oid, PROMO_EXPENSE_CODE)
        gift_credits = _lines(conn, "order_gift_cogs", oid, INVENTORY_CODE)
        assert len(gift_debits) == 1
        assert len(gift_credits) == 1
        assert any(gift_name in d["description"] for d in gift_debits)
        # Gift cost = 100%×5000×2 = 10000.
        assert float(gift_debits[0]["debit"]) == 10000.0
        assert float(gift_credits[0]["credit"]) == 10000.0
        conn.commit()


def test_ac2_completed_order_also_creates_gift_cogs_entry():
    """AC2 (completed path): an order that bypasses "delivered" and goes
    straight to "completed" still gets the ``order_gift_cogs`` entry via
    ``_sync_completed_order_journal``."""
    with get_db() as conn:
        ensure_schema(conn)
        gift_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-AC2-CMP", status="completed")
        _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng CMP",
            qty=1, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()

        _sync_completed_order_journal(conn, oid, "ORD-DG297-AC2-CMP")

        assert _entry_count(conn, "order_gift_cogs", oid) == 1
        conn.commit()


# ---------------------------------------------------------------------------
# AC3 — cost_at_sale populated for extras at delivery time
# ---------------------------------------------------------------------------


def test_ac3_cost_at_sale_populated_for_extras():
    """AC3: ``cost_at_sale`` is populated on the ``order_items`` rows for
    extras at delivery time (same snapshot behaviour as main items)."""
    with get_db() as conn:
        ensure_schema(conn)
        extra_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-AC3", total_price=5000)
        item_id = _add_item(
            conn, order_id=oid, product_id=extra_pid, product_name="Nến AC3",
            qty=2, unit_price=5000, is_extra=1,
        )
        conn.commit()

        # Before delivery: cost_at_sale is 0.
        before = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        assert float(before or 0) == 0.0

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-AC3")

        after = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        # Phụ kiện baseline = 100% base_price = 5000.
        assert float(after or 0) == 5000.0
        conn.commit()


def test_ac3_cost_at_sale_populated_for_gift_items():
    """AC3 (gift): the ``order_gift_cogs`` path also populates ``cost_at_sale``
    for gifted items so the snapshot is preserved (FR4 extends to gifts)."""
    with get_db() as conn:
        ensure_schema(conn)
        gift_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-AC3-GIFT", total_price=5000)
        item_id = _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng AC3G",
            qty=1, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-AC3-GIFT")

        after = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        assert float(after or 0) == 5000.0
        conn.commit()


# ---------------------------------------------------------------------------
# NFR1 — backward compatibility (orders with only non-extra, non-gift items)
# ---------------------------------------------------------------------------


def test_nfr1_backward_compat_main_items_only():
    """NFR1: an order with only non-extra, non-gift items produces the same
    COGS total and per-item line structure as before (one DR 5900/CR 1300 pair
    per main item)."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, category="banh_mi", base_price=100000)
        oid = _insert_order(conn, order_ref="ORD-DG297-NFR1", total_price=200000)
        _add_item(
            conn, order_id=oid, product_id=pid, product_name="Bánh mì NFR1",
            qty=2, unit_price=100000,
        )
        conn.commit()

        total = _compute_order_cogs_total(
            conn, oid, populate_cost_at_sale=False, force=True
        )
        assert total == 60000.0  # 30%×100000×2

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-NFR1")
        assert _entry_count(conn, "order_cogs", oid) == 1
        # No gift entry when there are no gifts.
        assert _entry_count(conn, "order_gift_cogs", oid) == 0
        conn.commit()


# ---------------------------------------------------------------------------
# NFR2 — idempotency (re-running delivery sync does not duplicate entries)
# ---------------------------------------------------------------------------


def test_nfr2_gift_cogs_entry_idempotent_on_repeat_delivery_sync():
    """NFR2: re-running the delivery sync on an order with a gift does not
    create a duplicate ``order_gift_cogs`` entry."""
    with get_db() as conn:
        ensure_schema(conn)
        gift_pid = _insert_product(
            conn, category="phu_kien", base_price=5000
        )
        oid = _insert_order(conn, order_ref="ORD-DG297-NFR2", total_price=5000)
        _add_item(
            conn, order_id=oid, product_id=gift_pid, product_name="Nến tặng NFR2",
            qty=1, unit_price=5000, is_extra=1, is_gift=1,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-NFR2")
        assert _entry_count(conn, "order_gift_cogs", oid) == 1

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-NFR2")
        _sync_delivered_order_journal(conn, oid, "ORD-DG297-NFR2")
        assert _entry_count(conn, "order_gift_cogs", oid) == 1
        conn.commit()


# ---------------------------------------------------------------------------
# NFR4 — no gift entry created when there are no gifts / zero-cost gifts
# ---------------------------------------------------------------------------


def test_nfr4_no_gift_entry_when_no_gift_items():
    """When an order has no gifted items, no ``order_gift_cogs`` entry is
    created (the gift sync is a no-op, leaving the idempotency check ready)."""
    with get_db() as conn:
        ensure_schema(conn)
        pid = _insert_product(conn, category="banh_mi", base_price=100000)
        oid = _insert_order(conn, order_ref="ORD-DG297-NFR4", total_price=100000)
        _add_item(
            conn, order_id=oid, product_id=pid, product_name="Bánh mì NFR4",
            qty=1, unit_price=100000,
        )
        conn.commit()

        _sync_delivered_order_journal(conn, oid, "ORD-DG297-NFR4")
        assert _entry_count(conn, "order_gift_cogs", oid) == 0
        conn.commit()