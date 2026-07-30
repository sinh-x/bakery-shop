"""Dedicated tests for baker.services.inventory_fifo (FR-PY-6).

Covers the FIFO helper functions: normalize_price_chip,
normalize_price_value, product_base_normalized_price,
normalized_price_for_chip, resolve_price_bucket_chip_id,
resolve_price_bucket_option, create_lot_with_items, consume_fifo_items,
available_quantity, net_available_quantity, upsert_negative_balance.

Uses the api_client fixture so the schema (products, stock_lots,
inventory_items, product_price_chips, negative_balance) is initialized.
The default seed product (id=1) is used for most tests.
"""

import pytest
from fastapi import HTTPException

from baker.db.connection import get_db
from baker.services.inventory_fifo import (
    available_quantity,
    consume_fifo_items,
    create_lot_with_items,
    net_available_quantity,
    normalize_price_chip,
    normalize_price_value,
    normalized_price_for_chip,
    product_base_normalized_price,
    resolve_price_bucket_chip_id,
    resolve_price_bucket_option,
    upsert_negative_balance,
)


def _create_chip(client, product_id: int, label: str, price: float) -> int:
    resp = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price},
    )
    assert resp.status_code == 201
    return int(resp.json()["id"])


def test_normalize_price_value_handles_none():
    assert normalize_price_value(None) == 0


def test_normalize_price_value_rounds_float():
    assert normalize_price_value(100.4) == 100
    assert normalize_price_value(100.6) == 101


def test_normalize_price_value_accepts_int():
    assert normalize_price_value(50) == 50


def test_product_base_normalized_price(api_client):
    with get_db() as conn:
        price = product_base_normalized_price(conn, 1)
    # The seed product (id=1) has a base price; verify it's an int.
    assert isinstance(price, int)
    assert price >= 0


def test_product_base_normalized_price_not_found(api_client):
    with get_db() as conn:
        with pytest.raises(HTTPException) as exc_info:
            product_base_normalized_price(conn, 999999)
    assert exc_info.value.status_code == 404


def test_normalize_price_chip_none_passes_through(api_client):
    with get_db() as conn:
        assert normalize_price_chip(conn, 1, None) is None


def test_normalize_price_chip_valid(api_client):
    chip_id = _create_chip(api_client, 1, "Test chip", 15000)
    with get_db() as conn:
        result = normalize_price_chip(conn, 1, chip_id)
    assert result == chip_id


def test_normalize_price_chip_wrong_product(api_client):
    chip_id = _create_chip(api_client, 1, "Wrong chip", 20000)
    with get_db() as conn:
        with pytest.raises(HTTPException) as exc_info:
            normalize_price_chip(conn, 2, chip_id)
    assert exc_info.value.status_code == 422


def test_normalized_price_for_chip_base(api_client):
    with get_db() as conn:
        base = product_base_normalized_price(conn, 1)
        result = normalized_price_for_chip(conn, 1, None)
    assert result == base


def test_normalized_price_for_chip(api_client):
    chip_id = _create_chip(api_client, 1, "Chip price", 18000)
    with get_db() as conn:
        result = normalized_price_for_chip(conn, 1, chip_id)
    assert result == 18000


def test_resolve_price_bucket_chip_id_base_match(api_client):
    with get_db() as conn:
        base = product_base_normalized_price(conn, 1)
        result = resolve_price_bucket_chip_id(conn, 1, base)
    assert result is None


def test_resolve_price_bucket_chip_id_chip_match(api_client):
    chip_id = _create_chip(api_client, 1, "Bucket chip", 25000)
    with get_db() as conn:
        result = resolve_price_bucket_chip_id(conn, 1, 25000)
    assert result == chip_id


def test_resolve_price_bucket_chip_id_no_match(api_client):
    with get_db() as conn:
        with pytest.raises(HTTPException) as exc_info:
            resolve_price_bucket_chip_id(conn, 1, 999999)
    assert exc_info.value.status_code == 422


def test_resolve_price_bucket_option_with_chip_id(api_client):
    chip_id = _create_chip(api_client, 1, "Option chip", 30000)
    with get_db() as conn:
        chip, price = resolve_price_bucket_option(conn, 1, None, chip_id)
    assert chip == chip_id
    assert price == 30000


def test_resolve_price_bucket_option_with_price_only(api_client):
    chip_id = _create_chip(api_client, 1, "Price chip", 40000)
    with get_db() as conn:
        chip, price = resolve_price_bucket_option(conn, 1, 40000, None)
    assert chip == chip_id
    assert price == 40000


def test_resolve_price_bucket_option_chip_price_mismatch(api_client):
    chip_id = _create_chip(api_client, 1, "Mismatch chip", 50000)
    with get_db() as conn:
        with pytest.raises(HTTPException) as exc_info:
            resolve_price_bucket_option(conn, 1, 99999, chip_id)
    assert exc_info.value.status_code == 422


def test_resolve_price_bucket_option_defaults_to_base(api_client):
    with get_db() as conn:
        base = product_base_normalized_price(conn, 1)
        chip, price = resolve_price_bucket_option(conn, 1, None, None)
    assert chip is None
    assert price == base


def test_create_lot_with_items(api_client):
    with get_db() as conn:
        lot_id = create_lot_with_items(conn, 1, None, 5)
        items = conn.execute(
            "SELECT status FROM inventory_items WHERE lot_id = ?", (lot_id,)
        ).fetchall()
        lot = conn.execute(
            "SELECT quantity, remaining_qty FROM stock_lots WHERE id = ?", (lot_id,)
        ).fetchone()
    assert len(items) == 5
    assert all(r["status"] == "available" for r in items)
    assert lot["quantity"] == 5
    assert lot["remaining_qty"] == 5


def test_available_quantity_zero_when_no_stock(api_client):
    chip_id = _create_chip(api_client, 1, "Empty chip", 10000)
    with get_db() as conn:
        qty = available_quantity(conn, 1, chip_id)
    assert qty == 0


def test_available_quantity_after_restock(api_client):
    chip_id = _create_chip(api_client, 1, "Avail chip", 12000)
    with get_db() as conn:
        create_lot_with_items(conn, 1, chip_id, 3)
        qty = available_quantity(conn, 1, chip_id)
    assert qty == 3


def _create_stock_movement(conn, product_id: int, qty: int, ref: str = "TEST") -> int:
    """Insert a stock_movement row and return its id (FK target for consume)."""
    cursor = conn.execute(
        "INSERT INTO stock_movements (product_id, movement_type, quantity, reference_id) "
        "VALUES (?, 'sale', ?, ?)",
        (product_id, qty, ref),
    )
    return cursor.lastrowid


def test_consume_fifo_items_insufficient_raises(api_client):
    chip_id = _create_chip(api_client, 1, "Insuff chip", 13000)
    with get_db() as conn:
        create_lot_with_items(conn, 1, chip_id, 2)
        movement_id = _create_stock_movement(conn, 1, 5)
        with pytest.raises(HTTPException) as exc_info:
            consume_fifo_items(conn, 1, chip_id, 5, movement_id)
    assert exc_info.value.status_code == 422
    assert "Không đủ tồn kho" in str(exc_info.value.detail)


def test_consume_fifo_items_allow_negative_returns_deficit(api_client):
    chip_id = _create_chip(api_client, 1, "Neg chip", 14000)
    with get_db() as conn:
        create_lot_with_items(conn, 1, chip_id, 2)
        movement_id = _create_stock_movement(conn, 1, 5)
        deficit = consume_fifo_items(
            conn, 1, chip_id, 5, movement_id, allow_negative=True
        )
    assert deficit == 3


def test_consume_fifo_items_consumes_oldest_first(api_client):
    chip_id = _create_chip(api_client, 1, "FIFO chip", 16000)
    with get_db() as conn:
        lot1 = create_lot_with_items(conn, 1, chip_id, 2)
        lot2 = create_lot_with_items(conn, 1, chip_id, 3)
        movement_id = _create_stock_movement(conn, 1, 4)
        consume_fifo_items(conn, 1, chip_id, 4, movement_id)
        lot1_remaining = conn.execute(
            "SELECT remaining_qty FROM stock_lots WHERE id = ?", (lot1,)
        ).fetchone()["remaining_qty"]
        lot2_remaining = conn.execute(
            "SELECT remaining_qty FROM stock_lots WHERE id = ?", (lot2,)
        ).fetchone()["remaining_qty"]
    # lot1 (older) fully consumed (2 items), lot2 provides 2 of 3.
    assert lot1_remaining == 0
    assert lot2_remaining == 1


def test_net_available_quantity_positive(api_client):
    chip_id = _create_chip(api_client, 1, "Net chip", 17000)
    with get_db() as conn:
        create_lot_with_items(conn, 1, chip_id, 5)
        net = net_available_quantity(conn, 1, chip_id)
    assert net == 5


def test_net_available_quantity_negative_with_balance(api_client):
    chip_id = _create_chip(api_client, 1, "Net neg chip", 19000)
    with get_db() as conn:
        upsert_negative_balance(conn, 1, chip_id, 4)
        net = net_available_quantity(conn, 1, chip_id)
    assert net == -4


def test_upsert_negative_balance_noop_on_zero(api_client):
    chip_id = _create_chip(api_client, 1, "Noop chip", 11000)
    with get_db() as conn:
        upsert_negative_balance(conn, 1, chip_id, 0)
        row = conn.execute(
            "SELECT qty FROM negative_balance WHERE product_id = 1 AND price_chip_id = ?",
            (chip_id,),
        ).fetchone()
    assert row is None


def test_upsert_negative_balance_increments(api_client):
    chip_id = _create_chip(api_client, 1, "Incr chip", 22000)
    with get_db() as conn:
        upsert_negative_balance(conn, 1, chip_id, 3)
        upsert_negative_balance(conn, 1, chip_id, 2)
        row = conn.execute(
            "SELECT qty FROM negative_balance WHERE product_id = 1 AND price_chip_id = ?",
            (chip_id,),
        ).fetchone()
    assert row["qty"] == 5