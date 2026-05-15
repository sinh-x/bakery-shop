"""Tests for product price chip API CRUD and product enrichment."""

from baker.db.connection import get_db


def _create_chip(client, product_id: int, label: str, price: float, position: int = 0):
    resp = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price, "position": position},
    )
    assert resp.status_code == 201
    return resp.json()


def test_list_price_chips_empty(api_client):
    resp = api_client.get("/api/products/1/price-chips")
    assert resp.status_code == 200
    assert resp.json() == []


def test_create_and_reorder_price_chips(api_client):
    first = _create_chip(api_client, 1, "Cao", 400000, position=2)
    second = _create_chip(api_client, 1, "Thường", 350000, position=1)

    resp = api_client.get("/api/products/1/price-chips")
    assert resp.status_code == 200
    chips = resp.json()
    assert len(chips) == 2
    assert chips[0]["label"] == "Thường"
    assert chips[0]["position"] == 1
    assert chips[1]["label"] == "Cao"
    assert chips[1]["position"] == 2

    # Clean up to keep next tests deterministic.
    api_client.delete(f"/api/products/1/price-chips/{first['id']}")
    api_client.delete(f"/api/products/1/price-chips/{second['id']}")


def test_price_chip_path_params_validation(api_client):
    assert api_client.get("/api/products/-1/price-chips").status_code == 422

    create_negative_product = api_client.post(
        "/api/products/-1/price-chips",
        json={"label": "Negative", "price": 1000, "position": 0},
    )
    assert create_negative_product.status_code == 422

    chip = _create_chip(api_client, 1, "Check", 150000, position=0)

    assert api_client.patch(
        "/api/products/1/price-chips/-1",
        json={"label": "x"},
    ).status_code == 422

    assert api_client.delete("/api/products/1/price-chips/-1").status_code == 422

    cleanup = api_client.delete(f"/api/products/1/price-chips/{chip['id']}")
    assert cleanup.status_code == 204


def test_update_price_chip(api_client):
    chip = _create_chip(api_client, 1, "Thường", 350000, position=0)
    chip_id = chip["id"]

    resp = api_client.patch(
        f"/api/products/1/price-chips/{chip_id}",
        json={"label": "Cỡ thường", "price": 360000, "position": 3},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["label"] == "Cỡ thường"
    assert updated["price"] == 360000
    assert updated["position"] == 3

    del_resp = api_client.delete(f"/api/products/1/price-chips/{chip_id}")
    assert del_resp.status_code == 204


def test_delete_price_chip(api_client):
    chip = _create_chip(api_client, 1, "Tạm", 500000, position=0)
    del_resp = api_client.delete(f"/api/products/1/price-chips/{chip['id']}")
    assert del_resp.status_code == 204

    resp = api_client.get("/api/products/1/price-chips")
    assert resp.status_code == 200
    assert all(c["id"] != chip["id"] for c in resp.json())


def test_create_price_chip_validations(api_client):
    # Empty labels are rejected
    resp = api_client.post(
        "/api/products/1/price-chips",
        json={"label": "   ", "price": 350000},
    )
    assert resp.status_code == 400

    # Negative prices are rejected
    resp = api_client.post(
        "/api/products/1/price-chips",
        json={"label": "Free", "price": -1000},
    )
    assert resp.status_code == 400


def test_product_payload_includes_price_chips(api_client):
    product = api_client.get("/api/products/1").json()
    assert "price_chips" in product
    assert product["price_chips"] == []

    chip = _create_chip(api_client, 1, "Nhiều tầng", 600000, position=1)

    products = api_client.get("/api/products").json()
    target = next(item for item in products if item["id"] == 1)
    assert isinstance(target["price_chips"], list)
    assert target["price_chips"][0]["label"] == "Nhiều tầng"

    cleanup = api_client.delete(f"/api/products/1/price-chips/{chip['id']}")
    assert cleanup.status_code == 204


def test_reorder_position_via_patch(api_client):
    low = _create_chip(api_client, 1, "Lo", 250000, position=0)
    high = _create_chip(api_client, 1, "Hi", 450000, position=2)

    resp = api_client.patch(
        f"/api/products/1/price-chips/{high['id']}",
        json={"position": -1},
    )
    assert resp.status_code == 200

    list_resp = api_client.get("/api/products/1/price-chips")
    assert list_resp.status_code == 200
    chips = list_resp.json()
    assert [item["label"] for item in chips] == ["Hi", "Lo"]

    api_client.delete(f"/api/products/1/price-chips/{low['id']}")
    api_client.delete(f"/api/products/1/price-chips/{high['id']}")


def test_price_chips_cascade_on_product_delete():
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        cursor = conn.execute("INSERT INTO products (name) VALUES (?)", ("Temp",))
        product_id = cursor.lastrowid

        conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) "
            "VALUES (?, ?, ?, ?)",
            (product_id, "Test chip", 1000, 0),
        )
        conn.commit()

        count = conn.execute(
            "SELECT COUNT(*) FROM product_price_chips WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        assert count[0] == 1

        conn.execute("DELETE FROM products WHERE id = ?", (product_id,))
        remaining = conn.execute(
            "SELECT COUNT(*) FROM product_price_chips WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        assert remaining[0] == 0


def test_product_price_chips_include_per_chip_stock_qty(api_client):
    chip_id = _create_chip(api_client, 1, "Nhỏ", 150000, position=0)["id"]

    assert chip_id is not None

    product = api_client.get("/api/products/1").json()
    chips = product["price_chips"]
    assert len(chips) == 1
    assert chips[0]["stock_qty"] == 0

    from baker.db.connection import get_db
    from baker.models.event import Event
    with get_db() as conn:
        conn.execute(
            "INSERT INTO product_attribute_values (product_id, attribute_type, value) "
            "VALUES (?, 'trung_bay', 'true')",
            (1,),
        )

    api_client.post(
        "/api/products/1/stock/restock",
        json={"quantity": 5, "price_chip_id": chip_id},
    )

    product = api_client.get("/api/products/1").json()
    chips = product["price_chips"]
    assert len(chips) == 1
    assert chips[0]["stock_qty"] == 5
