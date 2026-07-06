"""Tests for cost_history CRUD — DG-208 Phase 4 (FR5/FR6/FR7, AC5).

Covers:
- CLI ``baker product set-cost <identifier> <cost> [--effective-from DATE]``
  - creates a cost_history row (FR5)
  - idempotent upsert on same (product_id, effective_from) (FR5)
  - resolves by id, product_code, or name
  - rejects negative cost
  - rejects invalid --effective-from
  - AC5: after set-cost, resolve_product_cost() returns the set cost
- API ``GET /api/products/{id}/cost`` returns current cost + history (FR6)
- API ``POST /api/products/{id}/cost`` creates/updates cost_history (FR7)
  - idempotent on same effective_from
  - 404 on missing product
  - 422 on negative cost / invalid effective_from
"""

import click
import click.testing
import pytest

from baker.cli import app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.services.cost_resolver import resolve_product_cost


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _insert_product(conn, *, name="Bánh mì test", category="banh_mi", base_price=100000):
    cur = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes, product_code) "
        "VALUES (?, ?, ?, 0, '', ?)",
        (name, category, base_price, "BMI-T1"),
    )
    return int(cur.lastrowid)


def _cost_history_count(conn, product_id):
    return int(
        conn.execute(
            "SELECT COUNT(*) FROM cost_history WHERE product_id = ?", (product_id,)
        ).fetchone()[0]
    )


def _run(*args):
    return click.testing.CliRunner().invoke(app, list(args))


# ---------------------------------------------------------------------------
# CLI: baker product set-cost
#
# The CLI opens its own DB connection, so each test seeds data in a `with
# get_db()` block (auto-commits on exit), invokes the CLI, then reopens the
# DB to assert.
# ---------------------------------------------------------------------------


def _seed_product(*, name="Bánh mì test", category="banh_mi", base_price=100000,
                  product_code="BMI-T1"):
    """Insert a product and commit. Returns the product id."""
    with get_db() as conn:
        ensure_schema(conn)
        cur = conn.execute(
            "INSERT INTO products (name, category, base_price, cost, recipe_notes, product_code) "
            "VALUES (?, ?, ?, 0, '', ?)",
            (name, category, base_price, product_code),
        )
        return int(cur.lastrowid)


def test_set_cost_creates_row_by_id():
    pid = _seed_product()
    result = _run("product", "set-cost", str(pid), "45000")
    assert result.exit_code == 0, result.output
    assert "Created" in result.output
    with get_db() as conn:
        row = conn.execute(
            "SELECT cost, effective_from FROM cost_history WHERE product_id = ?", (pid,)
        ).fetchone()
    assert row["cost"] == pytest.approx(45000.0)
    assert row["effective_from"]


def test_set_cost_creates_row_by_product_code():
    pid = _seed_product()
    result = _run("product", "set-cost", "BMI-T1", "30000")
    assert result.exit_code == 0, result.output
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 1


def test_set_cost_creates_row_by_name():
    pid = _seed_product(name="Bánh mì test")
    result = _run("product", "set-cost", "Bánh mì test", "30000")
    assert result.exit_code == 0, result.output
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 1


def test_set_cost_idempotent_same_effective_from():
    pid = _seed_product()
    r1 = _run("product", "set-cost", str(pid), "40000", "--effective-from", "2026-07-01")
    assert r1.exit_code == 0, r1.output
    assert "Created" in r1.output
    r2 = _run("product", "set-cost", str(pid), "55000", "--effective-from", "2026-07-01")
    assert r2.exit_code == 0, r2.output
    assert "Updated" in r2.output
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 1
        row = conn.execute(
            "SELECT cost FROM cost_history WHERE product_id = ?", (pid,)
        ).fetchone()
    assert row["cost"] == pytest.approx(55000.0)


def test_set_cost_different_effective_from_creates_new_row():
    pid = _seed_product()
    _run("product", "set-cost", str(pid), "40000", "--effective-from", "2026-07-01")
    _run("product", "set-cost", str(pid), "50000", "--effective-from", "2026-08-01")
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 2


def test_set_cost_negative_rejected():
    pid = _seed_product()
    result = _run("product", "set-cost", str(pid), "-100")
    assert result.exit_code != 0
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 0


def test_set_cost_invalid_effective_from_rejected():
    pid = _seed_product()
    result = _run(
        "product", "set-cost", str(pid), "1000", "--effective-from", "not-a-date"
    )
    assert result.exit_code != 0
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 0


def test_set_cost_missing_product_aborts():
    result = _run("product", "set-cost", "999999", "1000")
    assert result.exit_code != 0
    assert "Không tìm thấy" in result.output


def test_set_cost_ac5_resolver_returns_set_cost():
    """AC5: after set-cost, resolve_product_cost() returns the set cost
    (not the baseline 30% of base_price)."""
    pid = _seed_product(base_price=100000)  # baseline would be 30000
    result = _run(
        "product", "set-cost", str(pid), "42000", "--effective-from", "2020-01-01"
    )
    assert result.exit_code == 0, result.output
    with get_db() as conn:
        resolved = resolve_product_cost(conn, pid)
    assert resolved == pytest.approx(42000.0)


# ---------------------------------------------------------------------------
# API: GET /api/products/{id}/cost
# ---------------------------------------------------------------------------


def test_api_get_cost_empty_history(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
    resp = api_client.get(f"/api/products/{pid}/cost")
    assert resp.status_code == 200
    data = resp.json()
    assert data["product_id"] == pid
    # No cost_history → current_cost falls back to baseline (30% of 100000 = 30000).
    assert data["current_cost"] == pytest.approx(30000.0)
    assert data["cost_history"] == []


def test_api_get_cost_with_history(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) "
            "VALUES (?, ?, ?)",
            (pid, 47000.0, "2020-01-01T00:00:00Z"),
        )
    resp = api_client.get(f"/api/products/{pid}/cost")
    assert resp.status_code == 200
    data = resp.json()
    assert data["current_cost"] == pytest.approx(47000.0)
    assert len(data["cost_history"]) == 1
    assert data["cost_history"][0]["cost"] == pytest.approx(47000.0)


def test_api_get_cost_missing_product_404(api_client):
    resp = api_client.get("/api/products/999999/cost")
    assert resp.status_code == 404


# ---------------------------------------------------------------------------
# API: POST /api/products/{id}/cost
# ---------------------------------------------------------------------------


def test_api_post_cost_creates_row(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
    resp = api_client.post(
        f"/api/products/{pid}/cost",
        json={"cost": 48000, "effective_from": "2020-01-01"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["cost"] == pytest.approx(48000.0)
    assert data["effective_from"] == "2020-01-01T00:00:00Z"
    assert data["status"] == "created"

    with get_db() as conn:
        rows = conn.execute(
            "SELECT cost FROM cost_history WHERE product_id = ?", (pid,)
        ).fetchall()
    assert len(rows) == 1
    assert rows[0]["cost"] == pytest.approx(48000.0)


def test_api_post_cost_idempotent(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
    payload = {"cost": 50000, "effective_from": "2026-07-01"}
    r1 = api_client.post(f"/api/products/{pid}/cost", json=payload)
    assert r1.status_code == 201
    r2 = api_client.post(f"/api/products/{pid}/cost", json=payload)
    assert r2.status_code == 200
    assert r2.json()["status"] == "updated"
    # Still only one row.
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 1
    # And the cost reflects the latest update.
    r3 = api_client.post(
        f"/api/products/{pid}/cost",
        json={"cost": 52000, "effective_from": "2026-07-01"},
    )
    assert r3.status_code == 200
    assert r3.json()["cost"] == pytest.approx(52000.0)
    with get_db() as conn:
        assert _cost_history_count(conn, pid) == 1


def test_api_post_cost_defaults_effective_from(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
    resp = api_client.post(f"/api/products/{pid}/cost", json={"cost": 12345})
    assert resp.status_code == 201
    assert resp.json()["effective_from"]  # non-empty timestamp


def test_api_post_cost_missing_product_404(api_client):
    resp = api_client.post(
        "/api/products/999999/cost", json={"cost": 1000, "effective_from": "2020-01-01"}
    )
    assert resp.status_code == 404


def test_api_post_cost_negative_422(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
    resp = api_client.post(
        f"/api/products/{pid}/cost", json={"cost": -50, "effective_from": "2020-01-01"}
    )
    assert resp.status_code == 422


def test_api_post_cost_invalid_effective_from_422(api_client):
    with get_db() as conn:
        pid = _insert_product(conn)
    resp = api_client.post(
        f"/api/products/{pid}/cost", json={"cost": 100, "effective_from": "garbage"}
    )
    assert resp.status_code == 422


def test_api_post_then_get_round_trip(api_client):
    """End-to-end: POST a cost, then GET confirms it appears in history and
    as current_cost."""
    with get_db() as conn:
        pid = _insert_product(conn, base_price=100000)
    api_client.post(
        f"/api/products/{pid}/cost",
        json={"cost": 60000, "effective_from": "2020-01-01"},
    )
    resp = api_client.get(f"/api/products/{pid}/cost")
    data = resp.json()
    assert data["current_cost"] == pytest.approx(60000.0)
    assert len(data["cost_history"]) == 1
    assert data["cost_history"][0]["cost"] == pytest.approx(60000.0)