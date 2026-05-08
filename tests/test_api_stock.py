"""Tests for chip-aware stock APIs and FIFO behavior."""

from baker.db.connection import get_db


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
