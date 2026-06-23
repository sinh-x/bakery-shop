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
    _insert_cost_history(db, pid, 4500.0, effective_from="2026-01-01T00:00:00")
    _insert_cost_history(db, pid, 5200.0, effective_from="2026-03-01T00:00:00")
    assert resolve_product_cost(db, pid) == pytest.approx(5200.0)


def test_future_effective_from_falls_back_to_baseline(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 9999.0, effective_from="9999-12-31T00:00:00")
    # No currently-effective cost_history → baseline (30% of 20000 = 6000)
    assert resolve_product_cost(db, pid) == pytest.approx(6000.0)


def test_past_then_future_returns_past(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 3000.0, effective_from="2020-01-01T00:00:00")
    _insert_cost_history(db, pid, 9999.0, effective_from="9999-12-31T00:00:00")
    assert resolve_product_cost(db, pid) == pytest.approx(3000.0)


def test_cost_history_zero_cost_returned(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, 0.0, effective_from="2020-01-01T00:00:00")
    # Explicit 0 cost_history entry wins (0 returned), baseline not applied
    assert resolve_product_cost(db, pid) == 0.0


def test_cost_history_negative_cost_clamped_to_zero(db):
    pid = _insert_product(db, category="banh_mi", base_price=20000)
    _insert_cost_history(db, pid, -100.0, effective_from="2020-01-01T00:00:00")
    # Negative cost_history is clamped to 0 so downstream COGS never stores
    # negative cost_at_sale (review finding m-2).
    assert resolve_product_cost(db, pid) == pytest.approx(0.0)


def test_is_phu_kien_helper():
    assert is_phu_kien("phu_kien") is True
    assert is_phu_kien("banh_mi") is False
    assert is_phu_kien(None) is False