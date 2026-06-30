"""Tests for chip-aware stock APIs and FIFO behavior."""

from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS


def _create_chip(client, product_id: int, label: str, price: float, position: int = 0) -> int:
    resp = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price, "position": position},
    )
    assert resp.status_code == 201
    return resp.json()["id"]


def _ensure_trung_bay(product_id: int) -> None:
    with get_db() as conn:
        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, 'trung_bay', 'true')
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id,),
        )


def test_restock_creates_lot_and_uuid_items_for_chip(api_client):
    chip_id = _create_chip(api_client, 1, "Nhỏ", 12000)

    resp = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "note": "restock", "price_chip_id": chip_id},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["price_chip_id"] == chip_id
    assert body["option_quantity"] == 3

    with get_db() as conn:
        lot = conn.execute(
            "SELECT id, product_id, price_chip_id, quantity, remaining_qty FROM stock_lots"
        ).fetchone()
        assert lot["product_id"] == 1
        assert lot["price_chip_id"] == chip_id
        assert lot["quantity"] == 3
        assert lot["remaining_qty"] == 3

        count = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE lot_id = ?",
            (lot["id"],),
        ).fetchone()["c"]
        assert count == 3

        distinct = conn.execute(
            "SELECT COUNT(DISTINCT uuid) AS c FROM inventory_items WHERE lot_id = ?",
            (lot["id"],),
        ).fetchone()["c"]
        assert distinct == 3


def test_waste_consumes_fifo_by_lot_then_item_age(api_client):
    chip_id = _create_chip(api_client, 1, "Lớn", 15000)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 1, "price_chip_id": chip_id},
    )

    waste = api_client.post(
        "/api/products/1/stock/waste",
        json={"quantity": 2, "reason": "expired", "price_chip_id": chip_id},
    )
    assert waste.status_code == 200
    assert waste.json()["quantity"] == 1

    with get_db() as conn:
        lots = conn.execute(
            "SELECT id, remaining_qty FROM stock_lots WHERE product_id = 1 AND price_chip_id = ? ORDER BY id",
            (chip_id,),
        ).fetchall()
        assert lots[0]["remaining_qty"] == 0
        assert lots[1]["remaining_qty"] == 1

        movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        consumed = conn.execute(
            "SELECT COUNT(*) AS c FROM inventory_items WHERE consumed_by_movement_id = ?",
            (movement["id"],),
        ).fetchone()["c"]
        assert consumed == 2


def test_stock_overview_returns_per_chip_aggregates_without_uuids(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "VIP", 20000)
    api_client.post("/api/products/1/stock/restock", json={"quantity": 2})
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )

    resp = api_client.get("/api/stock/overview")
    assert resp.status_code == 200
    item = next(row for row in resp.json() if row["product_id"] == 1)

    assert item["quantity"] == 5
    assert isinstance(item["per_chip"], list)
    assert {entry["price_chip_id"] for entry in item["per_chip"]} == {None, chip_id}
    assert all("uuid" not in entry for entry in item["per_chip"])


def test_stock_overview_groups_base_and_same_price_chip_into_one_bucket(api_client):
    _ensure_trung_bay(1)
    chip_id = _create_chip(api_client, 1, "chip 130", 10000)
    api_client.post("/api/products/1/stock/restock", json={"quantity": 2})
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )

    resp = api_client.get("/api/stock/overview")
    assert resp.status_code == 200
    item = next(row for row in resp.json() if row["product_id"] == 1)
    same_price_buckets = [b for b in item["per_chip"] if b["normalized_price"] == 10000]
    assert len(same_price_buckets) == 1
    assert same_price_buckets[0]["quantity"] == 5


def test_delete_chip_blocked_when_stock_exists(api_client):
    chip_id = _create_chip(api_client, 1, "Guard", 18000)
    restock = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 1, "price_chip_id": chip_id},
    )
    assert restock.status_code == 200

    delete_resp = api_client.delete(f"/api/products/1/price-chips/{chip_id}")
    assert delete_resp.status_code == 422


def test_restock_accepts_normalized_price_and_targets_price_bucket(api_client):
    chip_id = _create_chip(api_client, 1, "130", 13000)

    resp = api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 4, "normalized_price": 13000},
    )
    assert resp.status_code == 200
    assert resp.json()["normalized_price"] == 13000

    with get_db() as conn:
        lot = conn.execute(
            "SELECT price_chip_id, quantity FROM stock_lots WHERE product_id = 1 ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert lot["price_chip_id"] in {None, chip_id}
        assert lot["quantity"] == 4


def test_stock_overview_includes_migrated_accessories_when_display_and_stock_eligible(api_client):
    accessory_id = None
    with get_db() as conn:
        MIGRATIONS[38]["callable"](conn)
        accessory = conn.execute(
            "SELECT id FROM products WHERE category = 'phu_kien' AND name = 'Nến'"
        ).fetchone()
        assert accessory is not None
        accessory_id = accessory["id"]

    api_client.post(
        f"/api/products/{accessory_id}/stock/restock",
        json={"quantity": 2},
    )

    resp = api_client.get("/api/stock/overview")
    assert resp.status_code == 200
    overview = resp.json()
    nen = next(item for item in overview if item["product_name"] == "Nến")
    assert nen["category"] == "phu_kien"
    assert nen["quantity"] == 2


# ---------------------------------------------------------------------------
# Waste COGS journal entry (Phase 4.4 / DG-187 / FR5, AC5)
# ---------------------------------------------------------------------------


def _waste_cogs_entries(conn, movement_id: int):
    return conn.execute(
        "SELECT * FROM journal_entries WHERE source_type = 'waste_cogs' AND source_id = ? ORDER BY id",
        (movement_id,),
    ).fetchall()


def _entry_lines(conn, entry_id: int):
    return conn.execute(
        "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
        (entry_id,),
    ).fetchall()


def test_waste_stock_creates_cogs_journal_entry_with_baseline(api_client):
    """AC5: standalone waste with no cost_history → baseline cost →
    waste_cogs journal entry debiting 5900 and crediting 1300."""
    chip_id = _create_chip(api_client, 1, "Lớn", 15000)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 3, "price_chip_id": chip_id},
    )

    waste = api_client.post(
        "/api/products/1/stock/waste",
        json={"quantity": 2, "reason": "expired", "price_chip_id": chip_id},
    )
    assert waste.status_code == 200

    with get_db() as conn:
        movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        entries = _waste_cogs_entries(conn, movement["id"])
        assert len(entries) == 1

        lines = _entry_lines(conn, entries[0]["id"])
        debit_line = next(l for l in lines if l["debit"] > 0)
        credit_line = next(l for l in lines if l["credit"] > 0)
        cogs_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (debit_line["account_id"],)
        ).fetchone()
        inv_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()
        assert cogs_acc["code"] == "5900"
        assert inv_acc["code"] == "1300"
        # Product 1 base_price=10000 → baseline 30% = 3000 × 2 = 6000
        assert debit_line["debit"] == 6000.0
        assert credit_line["credit"] == 6000.0


def test_waste_stock_cogs_uses_cost_history_when_present(api_client):
    """AC5: when cost_history row exists, it overrides the baseline."""
    chip_id = _create_chip(api_client, 1, "Lớn", 15000)
    with get_db() as conn:
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 25000, "2020-01-01T00:00:00Z"),
        )
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )

    waste = api_client.post(
        "/api/products/1/stock/waste",
        json={"quantity": 1, "reason": "spoiled", "price_chip_id": chip_id},
    )
    assert waste.status_code == 200

    with get_db() as conn:
        movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        entries = _waste_cogs_entries(conn, movement["id"])
        assert len(entries) == 1
        lines = _entry_lines(conn, entries[0]["id"])
        debit_line = next(l for l in lines if l["debit"] > 0)
        # cost_history cost 25000 × qty 1 = 25000
        assert debit_line["debit"] == 25000.0


def test_waste_stock_cogs_idempotent(api_client):
    """Repeated waste on the same movement should not create duplicate entries."""
    chip_id = _create_chip(api_client, 1, "Lớn", 15000)
    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 4, "price_chip_id": chip_id},
    )

    api_client.post(
        "/api/products/1/stock/waste",
        json={"quantity": 1, "reason": "expired", "price_chip_id": chip_id},
    )
    with get_db() as conn:
        movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        # Re-invoke the sync helper directly to verify idempotency.
        from baker.services.journal_sync import _sync_waste_cogs_journal

        _sync_waste_cogs_journal(conn, 1, movement["id"], 1)
        entries = _waste_cogs_entries(conn, movement["id"])
        assert len(entries) == 1


def test_waste_stock_no_cogs_when_cost_zero(api_client):
    """AC5 edge case: product with zero base_price and no cost_history →
    baseline cost is 0 → no waste_cogs entry."""
    prod = api_client.post(
        "/api/products",
        json={"name": "Mẫu 0", "category": "cake", "base_price": 0, "cost": 0},
    )
    assert prod.status_code == 201
    pid = prod.json()["id"]
    chip_id = _create_chip(api_client, pid, "Mặc định", 0)
    api_client.post(
        f"/api/products/{pid}/stock/restock",
        json={"quantity": 2, "price_chip_id": chip_id},
    )
    waste = api_client.post(
        f"/api/products/{pid}/stock/waste",
        json={"quantity": 1, "reason": "hỏng", "price_chip_id": chip_id},
    )
    assert waste.status_code == 200
    with get_db() as conn:
        movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' AND product_id = ? ORDER BY id DESC LIMIT 1",
            (pid,),
        ).fetchone()
        entries = _waste_cogs_entries(conn, movement["id"])
        assert len(entries) == 0
