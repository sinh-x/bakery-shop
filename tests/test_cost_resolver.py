"""Unit tests for ``baker.services.cost_resolver.resolve_product_cost``.

Covers the Phase 2 acceptance criteria:
- AC1: baseline rule (30% non-phụ-kiện, 100% phụ-kiện) when no cost_history
- AC2: latest effective cost_history record wins over baseline
- Edge cases: zero base_price, missing product, future-dated effective_from,
  multiple cost_history rows, negative/zero cost_history cost.
"""

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.cost_resolver import (
    UNRESOLVED_COST,
    is_phu_kien,
    resolve_product_cost,
)


def _insert_product(conn, *, category="banh_mi", base_price=10000, cost=5000):
    cursor = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (f"SP-{category}-{base_price}-{cost}", category, base_price, cost),
    )
    return int(cursor.lastrowid)


def _insert_cost_history(conn, product_id, cost, *, effective_from):
    conn.execute(
        "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
        (product_id, cost, effective_from),
    )
    conn.commit()


@pytest.fixture
def db():
    with get_db() as conn:
        ensure_schema(conn)
        yield conn


def test_baseline_non_phu_kien_30_percent(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    assert resolve_product_cost(db, pid) == pytest.approx(6000.0)


def test_baseline_phu_kien_100_percent(db):
    pid = _insert_product(db, category="phu_kien", base_price=15000)
    assert resolve_product_cost(db, pid) == pytest.approx(15000.0)


def test_baseline_zero_base_price(db):
    pid = _insert_product(db, category="banh_mi", base_price=0)
    assert resolve_product_cost(db, pid) == 0.0


def test_baseline_missing_product(db):
    assert resolve_product_cost(db, 999999) == UNRESOLVED_COST
    assert resolve_product_cost(db, 999999) == 0.0


def test_latest_cost_history_wins(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 4500.0, effective_from="2026-01-01T00:00:00Z")
    _insert_cost_history(db, pid, 5200.0, effective_from="2026-03-01T00:00:00Z")
    assert resolve_product_cost(db, pid) == pytest.approx(5200.0)


def test_future_effective_from_falls_back_to_baseline(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 9999.0, effective_from="9999-12-31T00:00:00Z")
    # No currently-effective cost_history → baseline (30% of 20000 = 6000)
    assert resolve_product_cost(db, pid) == pytest.approx(6000.0)


def test_past_then_future_returns_past(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 3000.0, effective_from="2020-01-01T00:00:00Z")
    _insert_cost_history(db, pid, 9999.0, effective_from="9999-12-31T00:00:00Z")
    assert resolve_product_cost(db, pid) == pytest.approx(3000.0)


def test_cost_history_zero_cost_returned(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 0.0, effective_from="2020-01-01T00:00:00Z")
    # Explicit 0 cost_history entry wins (0 returned), baseline not applied
    assert resolve_product_cost(db, pid) == 0.0


def test_cost_history_negative_cost_clamped_to_zero(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, -100.0, effective_from="2020-01-01T00:00:00Z")
    # Negative cost_history is clamped to 0 so downstream COGS never stores
    # negative cost_at_sale (review finding m-2).
    assert resolve_product_cost(db, pid) == pytest.approx(0.0)


def test_is_phu_kien_helper():
    assert is_phu_kien("phu_kien") is True
    assert is_phu_kien("banh_mi") is False
    assert is_phu_kien(None) is False


# --- DG-208 Phase 1: selling_price baseline anchor --------------------------
#
# FR1: resolve_product_cost() accepts an optional selling_price that replaces
# base_price as the 30% baseline anchor when no cost_history row is in effect.
# Callers without selling_price keep the historical base_price × 30% behaviour.


def test_baseline_uses_selling_price_when_provided(db):
    """AC1 (Phase 1): custom pricing → COGS = selling_price × 0.30."""
    pid = _insert_product(db, category="banh_mi", base_price=150000)
    # selling_price 800000 → 30% = 240000 (not 150000 × 0.30 = 45000)
    assert resolve_product_cost(db, pid, selling_price=800000.0) == pytest.approx(
        240000.0
    )


def test_baseline_falls_back_to_base_price_without_selling_price(db):
    """AC2 (Phase 1): no selling_price → unchanged base_price × 0.30."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    assert resolve_product_cost(db, pid) == pytest.approx(30000.0)
    # Explicit None is equivalent to omitting it.
    assert resolve_product_cost(db, pid, selling_price=None) == pytest.approx(30000.0)


def test_baseline_selling_price_zero_treated_as_not_provided(db):
    """A 0 selling_price is clamped to None so zero-priced orders do not
    accidentally zero out COGS — they fall back to the base_price anchor."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    assert resolve_product_cost(db, pid, selling_price=0.0) == pytest.approx(30000.0)


def test_baseline_phu_kien_ignores_selling_price(db):
    """FR3: phụ kiện baseline is always 100% of base_price regardless of
    selling_price — the 100% rule is intentional and unchanged (Non-Goal)."""
    pid = _insert_product(db, category="phu_kien", base_price=20000)
    # selling_price 50000 would be 30% = 15000 for non-phu-kien, but phu_kien
    # ignores it and returns base_price (20000).
    assert resolve_product_cost(db, pid, selling_price=50000.0) == pytest.approx(
        20000.0
    )


def test_cost_history_wins_over_selling_price(db):
    """AC3 (partial — Phase 1 verifies the precedence only): when a
    cost_history row is in effect, it wins over both selling_price and
    base_price; selling_price never overrides an explicit cost record."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    _insert_cost_history(db, pid, 28000.0, effective_from="2020-01-01T00:00:00Z")
    assert resolve_product_cost(db, pid, selling_price=800000.0) == pytest.approx(
        28000.0
    )


def test_future_cost_history_falls_back_to_selling_price(db):
    """When the only cost_history row is future-dated, the baseline runs with
    selling_price as the anchor (mirrors test_future_effective_from_falls_back_to_baseline
    but with the new selling_price parameter)."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    _insert_cost_history(db, pid, 9999.0, effective_from="9999-12-31T00:00:00Z")
    # No currently-effective cost_history → baseline = selling_price × 0.30
    assert resolve_product_cost(db, pid, selling_price=200000.0) == pytest.approx(
        60000.0
    )


# --- DG-296 Phase 2: assigned_price baseline anchor -------------------------
#
# FR5: For trưng bày products sold at a markup, COGS is anchored on the
# assigned price (base_price or selected price chip) rather than the marked-up
# selling price. NFR1: COGS(250k sale, 200k assigned) == COGS(200k sale, 200k
# assigned). FR8: callers without assigned_price keep the historical
# selling_price/base_price behaviour (regression-free).


def test_assigned_price_overrides_selling_price(db):
    """AC2 (Phase 2): trưng bày product base_price 200,000 sold at 250,000
    with assigned_price=200,000 → COGS = 30% × 200,000 = 60,000 (not
    30% × 250,000 = 75,000)."""
    pid = _insert_product(db, category="banh_mi", base_price=200000)
    assert resolve_product_cost(
        db, pid, selling_price=250000.0, assigned_price=200000.0
    ) == pytest.approx(60000.0)


def test_nfr1_cogs_equivalence_assigned_price(db):
    """NFR1: COGS(250k sale, 200k assigned) == COGS(200k sale, 200k assigned).
    The marked-up selling price must not affect COGS when assigned_price is
    provided."""
    pid = _insert_product(db, category="banh_mi", base_price=200000)
    cogs_marked_up = resolve_product_cost(
        db, pid, selling_price=250000.0, assigned_price=200000.0
    )
    cogs_flat = resolve_product_cost(
        db, pid, selling_price=200000.0, assigned_price=200000.0
    )
    assert cogs_marked_up == pytest.approx(cogs_flat)
    assert cogs_marked_up == pytest.approx(60000.0)


def test_ac5_chip_price_assigned_anchor(db):
    """AC5 (Phase 2 partial — resolver-level): trưng bày product with a price
    chip of 300,000 (assigned_price=300,000) marked up to 350,000 →
    COGS = 30% × 300,000 = 90,000."""
    pid = _insert_product(db, category="banh_mi", base_price=200000)
    assert resolve_product_cost(
        db, pid, selling_price=350000.0, assigned_price=300000.0
    ) == pytest.approx(90000.0)


def test_assigned_price_zero_treated_as_not_provided(db):
    """A 0 assigned_price falls back to selling_price (mirrors the
    selling_price=0 clamp) so zero-assigned orders do not zero out COGS."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    # assigned_price=0 → selling_price=200000 anchor → 30% = 60000
    assert resolve_product_cost(
        db, pid, selling_price=200000.0, assigned_price=0.0
    ) == pytest.approx(60000.0)


def test_assigned_price_none_falls_back_to_selling_price(db):
    """FR8: when assigned_price is None, selling_price is used as the anchor
    (DG-208 Phase 1 behaviour preserved — regression-free)."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    assert resolve_product_cost(
        db, pid, selling_price=200000.0, assigned_price=None
    ) == pytest.approx(60000.0)


def test_both_none_falls_back_to_base_price(db):
    """FR8: when neither assigned_price nor selling_price is provided, the
    historical base_price × 30% baseline runs (regression-free)."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    assert resolve_product_cost(db, pid) == pytest.approx(30000.0)
    assert resolve_product_cost(
        db, pid, selling_price=None, assigned_price=None
    ) == pytest.approx(30000.0)


def test_assigned_price_phu_kien_ignored(db):
    """phụ kiện baseline is always 100% of base_price regardless of
    assigned_price — the 100% rule is intentional and unchanged (Non-Goal,
    mirrors test_baseline_phu_kien_ignores_selling_price)."""
    pid = _insert_product(db, category="phu_kien", base_price=20000)
    assert resolve_product_cost(
        db, pid, selling_price=50000.0, assigned_price=40000.0
    ) == pytest.approx(20000.0)


def test_cost_history_wins_over_assigned_price(db):
    """cost_history precedence is unchanged: an in-effect cost_history row
    wins over both assigned_price and selling_price (mirrors
    test_cost_history_wins_over_selling_price)."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    _insert_cost_history(db, pid, 28000.0, effective_from="2020-01-01T00:00:00Z")
    assert resolve_product_cost(
        db, pid, selling_price=250000.0, assigned_price=200000.0
    ) == pytest.approx(28000.0)


def test_future_cost_history_falls_back_to_assigned_price(db):
    """When the only cost_history row is future-dated, the baseline runs with
    assigned_price as the anchor (precedence: assigned > selling > base)."""
    pid = _insert_product(db, category="banh_mi", base_price=100000)
    _insert_cost_history(db, pid, 9999.0, effective_from="9999-12-31T00:00:00Z")
    # assigned_price=200000 wins over selling_price=250000 → 30% × 200000
    assert resolve_product_cost(
        db, pid, selling_price=250000.0, assigned_price=200000.0
    ) == pytest.approx(60000.0)