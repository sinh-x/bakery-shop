"""Tests for blanks API — CRUD, BOM, stock, demand (DG-290 Phase 4.2)."""

import itertools

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.models.blank import Blank, BlankStock, BlankStockLog, ProductBlankBom


_product_counter = itertools.count(10000)


# --- helpers -----------------------------------------------------------------


def _create_product(client, name=None, category="banh_kem"):
    name = name or f"SP test {next(_product_counter)}"
    resp = client.post(
        "/api/products",
        json={"name": name, "category": category, "base_price": 200000},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_price_chip(client, product_id, label="Size S", price=200000):
    resp = client.post(
        f"/api/products/{product_id}/price-chips",
        json={"label": label, "price": price, "position": 0},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_blank(client, name="Cốt bánh", category="cot", unit="cai", notes=""):
    resp = client.post(
        "/api/blanks",
        json={"name": name, "category": category, "unit": unit, "notes": notes},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_order(client, items, status=None, customer="Test"):
    payload = {"customerName": customer, "items": items, "dueDate": "2026-08-01"}
    if status:
        payload["status"] = status
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


# --- model unit tests --------------------------------------------------------


def test_blank_dataclass_to_api_dict_camelcase():
    blank = Blank(id=1, name="Cốt", category="cot", unit="cai", notes="x", created_at="t")
    d = blank.to_api_dict()
    assert d == {
        "id": 1,
        "name": "Cốt",
        "category": "cot",
        "unit": "cai",
        "notes": "x",
        "createdAt": "t",
        "updatedAt": None,
    }


def test_blank_from_row_roundtrip(use_memory_db):
    with get_db() as conn:
        ensure_schema(conn)
        b = Blank(name="Kem", category="kem", unit="gram")
        b.save(conn)
        row = conn.execute("SELECT * FROM blanks WHERE id = ?", (b.id,)).fetchone()
        loaded = Blank.from_row(row)
        assert loaded.id == b.id
        assert loaded.name == "Kem"
        assert loaded.category == "kem"
        assert loaded.unit == "gram"


def test_product_blank_bom_to_api_dict_camelcase():
    bom = ProductBlankBom(id=1, product_id=2, price_chip_id=3, blank_id=4, quantity=2.5)
    d = bom.to_api_dict()
    assert d == {
        "id": 1,
        "productId": 2,
        "priceChipId": 3,
        "blankId": 4,
        "quantity": 2.5,
        "createdAt": None,
    }


def test_blank_stock_log_signs_usage_negative(use_memory_db):
    with get_db() as conn:
        ensure_schema(conn)
        b = Blank(name="Cốt", category="cot", unit="cai")
        b.save(conn)
        log = BlankStockLog(
            blank_id=b.id, quantity_change=-5, type="usage"
        )
        log.save(conn)
        assert log.id is not None


def test_blank_stock_save_and_from_row(use_memory_db):
    with get_db() as conn:
        ensure_schema(conn)
        b = Blank(name="Cốt", category="cot", unit="cai")
        b.save(conn)
        s = BlankStock(
            blank_id=b.id, quantity=10, produced_date="2026-07-24", type="production"
        )
        s.save(conn)
        row = conn.execute("SELECT * FROM blank_stock WHERE id = ?", (s.id,)).fetchone()
        loaded = BlankStock.from_row(row)
        assert loaded.quantity == 10
        assert loaded.type == "production"
        assert loaded.produced_date == "2026-07-24"


# --- API: Blank CRUD (AC2) ----------------------------------------------------


def test_create_blank_returns_camelcase(api_client):
    body = _create_blank(api_client, name="Cốt bánh", category="cot", unit="cai", notes="Ghi chú")
    assert body["id"] > 0
    assert body["name"] == "Cốt bánh"
    assert body["category"] == "cot"
    assert body["unit"] == "cai"
    assert body["notes"] == "Ghi chú"
    assert "createdAt" in body
    assert "updatedAt" in body


def test_list_blanks_empty(api_client):
    resp = api_client.get("/api/blanks")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_blanks_filtered_by_category(api_client):
    _create_blank(api_client, name="Cốt", category="cot")
    _create_blank(api_client, name="Kem", category="kem")
    resp = api_client.get("/api/blanks", params={"category": "cot"})
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) == 1
    assert items[0]["name"] == "Cốt"


def test_update_blank(api_client):
    blank = _create_blank(api_client, name="Cốt", category="cot", unit="cai")
    resp = api_client.patch(
        f"/api/blanks/{blank['id']}",
        json={"name": "Cốt revised", "unit": "vien"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "Cốt revised"
    assert body["unit"] == "vien"
    assert body["category"] == "cot"  # unchanged


def test_update_blank_empty_name_rejected(api_client):
    blank = _create_blank(api_client, name="Cốt")
    resp = api_client.patch(f"/api/blanks/{blank['id']}", json={"name": "  "})
    assert resp.status_code == 400


def test_delete_blank(api_client):
    blank = _create_blank(api_client, name="Cốt")
    resp = api_client.delete(f"/api/blanks/{blank['id']}")
    assert resp.status_code == 204
    resp = api_client.get("/api/blanks")
    assert resp.json() == []


def test_get_blank_not_found(api_client):
    resp = api_client.patch("/api/blanks/9999", json={"name": "x"})
    assert resp.status_code == 404


def test_create_blank_empty_name_rejected(api_client):
    resp = api_client.post("/api/blanks", json={"name": "", "category": "cot", "unit": "cai"})
    assert resp.status_code == 400


# --- API: BOM CRUD via price-chip (AC3) --------------------------------------


def test_create_bom_mapping(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    resp = api_client.post(
        f"/api/price-chips/{chip['id']}/blanks",
        json={"blankId": blank["id"], "quantity": 2},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["priceChipId"] == chip["id"]
    assert body["blankId"] == blank["id"]
    assert body["quantity"] == 2
    assert body["productId"] == product["id"]


def test_list_chip_bom(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank1 = _create_blank(api_client, name="Cốt")
    blank2 = _create_blank(api_client, name="Kem")
    api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank1["id"], "quantity": 1}
    )
    api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank2["id"], "quantity": 3}
    )
    resp = api_client.get(f"/api/price-chips/{chip['id']}/blanks")
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_update_bom_quantity(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    bom = api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank["id"], "quantity": 1}
    ).json()
    resp = api_client.patch(
        f"/api/price-chips/{chip['id']}/blanks/{bom['id']}", json={"quantity": 5}
    )
    assert resp.status_code == 200
    assert resp.json()["quantity"] == 5


def test_delete_bom_mapping(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    bom = api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank["id"], "quantity": 1}
    ).json()
    resp = api_client.delete(f"/api/price-chips/{chip['id']}/blanks/{bom['id']}")
    assert resp.status_code == 204
    assert api_client.get(f"/api/price-chips/{chip['id']}/blanks").json() == []


def test_bom_chip_not_found(api_client):
    blank = _create_blank(api_client)
    resp = api_client.post(
        "/api/price-chips/9999/blanks", json={"blankId": blank["id"], "quantity": 1}
    )
    assert resp.status_code == 404


def test_bom_blank_not_found(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    resp = api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": 9999, "quantity": 1}
    )
    assert resp.status_code == 404


# --- API: Stock (AC5) --------------------------------------------------------


def test_record_production_stock(api_client):
    blank = _create_blank(api_client)
    resp = api_client.post(
        "/api/blanks/stock",
        json={
            "blankId": blank["id"],
            "quantity": 10,
            "type": "production",
            "producedDate": "2026-07-24",
            "expiryDate": "2026-07-27",
        },
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["blankId"] == blank["id"]
    assert body["quantity"] == 10
    assert body["type"] == "production"
    assert body["producedDate"] == "2026-07-24"
    assert body["expiryDate"] == "2026-07-27"


def test_record_usage_stock_reduces_net(api_client):
    blank = _create_blank(api_client)
    api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 10, "type": "production", "producedDate": "2026-07-24"},
    )
    api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 4, "type": "usage"},
    )
    stock = api_client.get("/api/blanks/stock").json()
    assert stock[0]["stock"] == 6.0


def test_stock_invalid_type_rejected(api_client):
    blank = _create_blank(api_client)
    resp = api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 1, "type": "invalid"},
    )
    assert resp.status_code == 400


def test_stock_zero_quantity_rejected(api_client):
    blank = _create_blank(api_client)
    resp = api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 0, "type": "production"},
    )
    assert resp.status_code == 400


def test_stock_writes_audit_log(api_client):
    blank = _create_blank(api_client)
    api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 7, "type": "production", "producedDate": "2026-07-24"},
    )
    with get_db() as conn:
        ensure_schema(conn)
        rows = conn.execute(
            "SELECT * FROM blank_stock_log WHERE blank_id = ?", (blank["id"],)
        ).fetchall()
        assert len(rows) == 1
        log = BlankStockLog.from_row(rows[0])
        assert log.quantity_change == 7
        assert log.type == "production"
        assert log.produced_date == "2026-07-24"


def test_get_stock_lists_all_blanks(api_client):
    _create_blank(api_client, name="Cốt")
    _create_blank(api_client, name="Kem")
    stock = api_client.get("/api/blanks/stock").json()
    assert len(stock) == 2
    assert stock[0]["stock"] == 0
    assert stock[1]["stock"] == 0


# --- API: Demand (AC4, AC6) --------------------------------------------------


def test_demand_empty(api_client):
    resp = api_client.get("/api/blanks/demand")
    assert resp.status_code == 200
    assert resp.json() == []


def test_demand_aggregates_from_pending_orders(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    # BOM: 1 price_chip → 2 blanks per unit
    api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank["id"], "quantity": 2}
    )
    # Two pending orders, 3 units each → demand = 2 × 3 × 2 = 12
    _create_order(api_client, [
        {"productName": "Bánh", "unitPrice": 200000, "priceChipId": chip["id"], "quantity": 3},
    ])
    _create_order(api_client, [
        {"productName": "Bánh", "unitPrice": 200000, "priceChipId": chip["id"], "quantity": 3},
    ])
    demand = api_client.get("/api/blanks/demand").json()
    assert len(demand) == 1
    assert demand[0]["blankId"] == blank["id"]
    assert demand[0]["demand"] == 12
    assert demand[0]["stock"] == 0
    assert demand[0]["shortage"] == 12


def test_demand_excludes_delivered_and_cancelled(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank["id"], "quantity": 1}
    )
    order1 = _create_order(api_client, [
        {"productName": "B", "unitPrice": 1, "priceChipId": chip["id"], "quantity": 2},
    ])
    order2 = _create_order(api_client, [
        {"productName": "B", "unitPrice": 1, "priceChipId": chip["id"], "quantity": 5},
    ])
    # Transition to delivered / cancelled via the status endpoint.
    api_client.post(
        f"/api/orders/{order1['orderRef']}/status",
        json={"status": "delivered", "reason": "test"},
    )
    api_client.post(
        f"/api/orders/{order2['orderRef']}/status",
        json={"status": "cancelled", "reason": "test"},
    )
    demand = api_client.get("/api/blanks/demand").json()
    assert demand[0]["demand"] == 0


def test_demand_falls_back_to_product_id(api_client):
    """Order item without price_chip_id → BOM matched by product_id."""
    product = _create_product(api_client)
    blank = _create_blank(api_client)
    # BOM keyed on product_id only (no price_chip) — insert via DB helper.
    with get_db() as conn:
        ensure_schema(conn)
        bom = ProductBlankBom(
            product_id=product["id"], price_chip_id=None, blank_id=blank["id"], quantity=3
        )
        bom.save(conn)
    _create_order(api_client, [
        {"productName": "Bánh kem 16cm", "unitPrice": 200000, "productId": str(product["id"]), "quantity": 2},
    ])
    demand = api_client.get("/api/blanks/demand").json()
    assert demand[0]["demand"] == 6  # 3 × 2


def test_demand_shortage_when_stock_covers(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank["id"], "quantity": 1}
    )
    # demand = 5
    _create_order(api_client, [
        {"productName": "B", "unitPrice": 1, "priceChipId": chip["id"], "quantity": 5},
    ])
    # stock = 8 → shortage = 0
    api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 8, "type": "production", "producedDate": "2026-07-24"},
    )
    demand = api_client.get("/api/blanks/demand").json()
    assert demand[0]["demand"] == 5
    assert demand[0]["stock"] == 8
    assert demand[0]["shortage"] == 0


def test_demand_response_uses_camelcase_keys(api_client):
    _create_blank(api_client)
    demand = api_client.get("/api/blanks/demand").json()
    expected_keys = {"blankId", "name", "category", "unit", "demand", "stock", "shortage"}
    assert set(demand[0].keys()) == expected_keys


# --- AC7: camelCase consistency ----------------------------------------------


def test_stock_response_uses_camelcase_keys(api_client):
    blank = _create_blank(api_client)
    api_client.post(
        "/api/blanks/stock",
        json={"blankId": blank["id"], "quantity": 1, "type": "production", "producedDate": "2026-07-24"},
    )
    stock = api_client.get("/api/blanks/stock").json()
    expected_keys = {"blankId", "name", "category", "unit", "stock"}
    assert set(stock[0].keys()) == expected_keys


def test_bom_response_uses_camelcase_keys(api_client):
    product = _create_product(api_client)
    chip = _create_price_chip(api_client, product["id"])
    blank = _create_blank(api_client)
    bom = api_client.post(
        f"/api/price-chips/{chip['id']}/blanks", json={"blankId": blank["id"], "quantity": 1}
    ).json()
    expected_keys = {"id", "productId", "priceChipId", "blankId", "quantity", "createdAt"}
    assert set(bom.keys()) == expected_keys