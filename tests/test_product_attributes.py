"""Tests for product attribute system — cash-in-cake total calculations."""

import json


# --- Helpers ---

def _create_order(client, customer="Nguyễn Văn A", items=None, **kwargs):
    if items is None:
        items = [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}]
    payload = {"customerName": customer, "items": items, "dueDate": "2026-03-25", **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _make_cake_item(unit_price=200000, rut_tien=True, cash_amount="500000", cash_fee="20000"):
    """Create a banh_kem item with cash-in-cake attributes."""
    attrs = {}
    if rut_tien:
        attrs = {"rut_tien": "true", "cash_amount": cash_amount, "cash_fee": cash_fee}
    return {
        "productName": "Bánh kem",
        "quantity": 1,
        "unitPrice": unit_price,
        "productId": "BKS-16",
        "attributes": attrs,
    }


# --- Order total with cash attributes ---


def test_order_total_with_cash_fee(api_client):
    """Cash fee should be included in total when rut_tien is active."""
    item = _make_cake_item(unit_price=200000, cash_fee="20000")
    order = _create_order(api_client, items=[item])
    assert order["totalPrice"] == 220000  # 200k + 20k fee


def test_order_total_without_rut_tien(api_client):
    """Cash fee should NOT be included when rut_tien is not set."""
    item = _make_cake_item(unit_price=200000, rut_tien=False)
    order = _create_order(api_client, items=[item])
    assert order["totalPrice"] == 200000  # No cash fee


def test_order_total_with_rut_tien_false_string(api_client):
    """Cash fee should NOT be included when rut_tien is explicitly 'false'."""
    item = {
        "productName": "Bánh kem",
        "quantity": 1,
        "unitPrice": 200000,
        "productId": "BKS-16",
        "attributes": {"rut_tien": "false", "cash_amount": "500000", "cash_fee": "20000"},
    }
    order = _create_order(api_client, items=[item])
    assert order["totalPrice"] == 200000  # rut_tien=false, no cash fee


def test_order_total_multiple_cash_items(api_client):
    """Multiple items with cash-in-cake should each contribute cash_fee."""
    items = [
        _make_cake_item(unit_price=200000, cash_fee="20000"),
        _make_cake_item(unit_price=300000, cash_fee="30000"),
    ]
    order = _create_order(api_client, items=items)
    assert order["totalPrice"] == 550000  # (200k + 20k) + (300k + 30k)


def test_order_total_with_shipping_and_cash_fee(api_client):
    """Total should include item subtotal + cash_fee + shipping_fee."""
    item = _make_cake_item(unit_price=200000, cash_fee="20000")
    order = _create_order(api_client, items=[item], shippingFee=25000)
    assert order["totalPrice"] == 245000  # 200k + 20k fee + 25k shipping


def test_order_total_gift_items_excluded(api_client):
    """Gift items should not contribute to total, even with attributes."""
    items = [
        _make_cake_item(unit_price=200000, cash_fee="20000"),
        {
            "productName": "Nến",
            "quantity": 1,
            "unitPrice": 5000,
            "isGift": True,
            "attributes": {},
        },
    ]
    order = _create_order(api_client, items=items)
    assert order["totalPrice"] == 220000  # 200k + 20k fee, gift excluded


# --- Edit order total recalculation ---


def test_edit_order_shipping_preserves_cash_fee(api_client):
    """Changing shipping fee should preserve cash_fee in total recalculation."""
    item = _make_cake_item(unit_price=200000, cash_fee="20000")
    order = _create_order(api_client, items=[item], shippingFee=0)
    assert order["totalPrice"] == 220000  # 200k + 20k fee

    # Update shipping fee
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}", json={"shippingFee": 25000})
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["totalPrice"] == 245000  # 200k + 20k fee + 25k shipping


def test_edit_order_items_with_cash_fee(api_client):
    """Replacing items should correctly recalculate total with new cash_fee."""
    item = _make_cake_item(unit_price=200000, cash_fee="20000")
    order = _create_order(api_client, items=[item])
    assert order["totalPrice"] == 220000

    # Replace items with a different cash_fee
    new_items = [_make_cake_item(unit_price=300000, cash_fee="30000")]
    ref = order["orderRef"]
    resp = api_client.patch(f"/api/orders/{ref}", json={"items": new_items})
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["totalPrice"] == 330000  # 300k + 30k fee


# --- Work item sync recalculates total ---


def test_work_item_update_attributes_recalculates_total(api_client):
    """Updating a work item's attributes should recalculate order total."""
    item = _make_cake_item(unit_price=200000, rut_tien=False)
    order = _create_order(api_client, items=[item])
    assert order["totalPrice"] == 200000

    ref = order["orderRef"]
    work_items = api_client.get(f"/api/orders/{ref}/items").json()
    wi_id = work_items[0]["id"]

    # Enable rut_tien with cash_fee
    resp = api_client.patch(
        f"/api/orders/{ref}/items/{wi_id}",
        json={"attributes": {"rut_tien": "true", "cash_amount": "500000", "cash_fee": "20000"}},
    )
    assert resp.status_code == 200

    # Check order total was recalculated
    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["totalPrice"] == 220000  # 200k + 20k fee


def test_work_item_disable_rut_tien_removes_cash_fee(api_client):
    """Removing rut_tien from work item attributes should exclude cash_fee from total."""
    item = _make_cake_item(unit_price=200000, cash_fee="20000")
    order = _create_order(api_client, items=[item])
    assert order["totalPrice"] == 220000

    ref = order["orderRef"]
    work_items = api_client.get(f"/api/orders/{ref}/items").json()
    wi_id = work_items[0]["id"]

    # Disable rut_tien
    resp = api_client.patch(
        f"/api/orders/{ref}/items/{wi_id}",
        json={"attributes": {}},
    )
    assert resp.status_code == 200

    order_resp = api_client.get(f"/api/orders/{ref}")
    assert order_resp.json()["totalPrice"] == 200000  # No cash fee


# --- Attribute type CRUD API ---


def test_list_attribute_types(api_client):
    """GET /api/product-attributes should return seeded attribute types."""
    resp = api_client.get("/api/product-attributes")
    assert resp.status_code == 200
    types = resp.json()
    # Migration v23 seeds cash_amount, cash_fee
    type_names = [t["attribute_type"] for t in types]
    assert "cash_amount" in type_names
    assert "cash_fee" in type_names


def test_create_attribute_type(api_client):
    """POST /api/product-attributes should create a new attribute type."""
    resp = api_client.post("/api/product-attributes", json={
        "attribute_type": "test_attr",
        "label_vi": "Thuoc tinh thu",
        "value_type": "text",
        "applicable_categories": ["banh_kem"],
    })
    assert resp.status_code == 201
    data = resp.json()
    assert data["attribute_type"] == "test_attr"
    assert data["value_type"] == "text"


def test_get_product_attributes(api_client):
    """GET /api/products/{id}/attributes should return product attribute values as dict."""
    products_resp = api_client.get("/api/products")
    assert products_resp.status_code == 200
    products = products_resp.json()
    if products:
        # Find a banh_kem product
        cake = next((p for p in products if p.get("category") == "banh_kem"), products[0])
        pid = cake["id"]
        resp = api_client.get(f"/api/products/{pid}/attributes")
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, dict)
        # banh_kem products should have cash_amount and cash_fee attributes
        if cake.get("category") == "banh_kem":
            assert "cash_amount" in data
            assert "cash_fee" in data
