"""Tests for product_attribute_options CRUD + enum_attributes in product response."""


# --- GET options ---


def test_list_seeded_nhan_banh_options(api_client):
    resp = api_client.get("/api/product-attributes/nhan_banh/options")
    assert resp.status_code == 200
    options = resp.json()
    assert len(options) == 5
    # Ordered by sort_order then id
    sort_orders = [o["sort_order"] for o in options]
    assert sort_orders == sorted(sort_orders)
    values = [o["value_vi"] for o in options]
    assert values == ["Sầu riêng", "Sô-cô-la", "Việt quất", "Chanh dây", "Dâu"]
    for o in options:
        assert o["active"] == 1
        assert "id" in o
        assert "attribute_id" in o


def test_list_options_unknown_attribute_404(api_client):
    resp = api_client.get("/api/product-attributes/does_not_exist/options")
    assert resp.status_code == 404


def test_list_options_non_enum_attribute_409(api_client):
    # cash_amount is value_type='number', not enum
    resp = api_client.get("/api/product-attributes/cash_amount/options")
    assert resp.status_code == 409


def test_list_options_filter_active(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    target = options[0]
    api_client.delete(f"/api/product-attribute-options/{target['id']}")

    active_only = api_client.get(
        "/api/product-attributes/nhan_banh/options?active=1"
    ).json()
    assert all(o["active"] == 1 for o in active_only)
    assert all(o["id"] != target["id"] for o in active_only)

    inactive = api_client.get(
        "/api/product-attributes/nhan_banh/options?active=0"
    ).json()
    assert any(o["id"] == target["id"] for o in inactive)


# --- POST create ---


def test_create_option(api_client):
    resp = api_client.post(
        "/api/product-attributes/nhan_banh/options",
        json={"value_vi": "Khoai môn"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["value_vi"] == "Khoai môn"
    assert body["active"] == 1
    assert isinstance(body["id"], int)


def test_create_option_explicit_sort_order(api_client):
    resp = api_client.post(
        "/api/product-attributes/nhan_banh/options",
        json={"value_vi": "Bơ", "sort_order": 99, "active": 1},
    )
    assert resp.status_code == 201
    assert resp.json()["sort_order"] == 99


def test_create_option_empty_value_400(api_client):
    resp = api_client.post(
        "/api/product-attributes/nhan_banh/options",
        json={"value_vi": "   "},
    )
    assert resp.status_code == 400


def test_create_option_non_enum_attribute_409(api_client):
    resp = api_client.post(
        "/api/product-attributes/cash_amount/options",
        json={"value_vi": "x"},
    )
    assert resp.status_code == 409


# --- PATCH update ---


def test_patch_option_value(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    target = options[0]
    resp = api_client.patch(
        f"/api/product-attribute-options/{target['id']}",
        json={"value_vi": "Sầu riêng Musang"},
    )
    assert resp.status_code == 200
    assert resp.json()["value_vi"] == "Sầu riêng Musang"


def test_patch_option_sort_order_and_active(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    target = options[1]
    resp = api_client.patch(
        f"/api/product-attribute-options/{target['id']}",
        json={"sort_order": 42, "active": 0},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["sort_order"] == 42
    assert body["active"] == 0


def test_patch_option_unknown_404(api_client):
    resp = api_client.patch(
        "/api/product-attribute-options/99999",
        json={"value_vi": "x"},
    )
    assert resp.status_code == 404


# --- DELETE (soft) ---


def test_delete_option_soft_excludes_from_active_list(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    target = options[2]

    resp = api_client.delete(f"/api/product-attribute-options/{target['id']}")
    assert resp.status_code == 204

    # Default GET returns all rows, but deleted row should be active=0
    after = api_client.get("/api/product-attributes/nhan_banh/options").json()
    deleted_row = next((o for o in after if o["id"] == target["id"]), None)
    assert deleted_row is not None
    assert deleted_row["active"] == 0

    active_only = api_client.get(
        "/api/product-attributes/nhan_banh/options?active=1"
    ).json()
    assert all(o["id"] != target["id"] for o in active_only)


# --- Reorder ---


def test_reorder_options(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    ids = [o["id"] for o in options]
    reversed_ids = list(reversed(ids))

    resp = api_client.post(
        "/api/product-attributes/nhan_banh/options/reorder",
        json={"ordered_ids": reversed_ids},
    )
    assert resp.status_code == 200
    after = resp.json()
    assert [o["id"] for o in after] == reversed_ids
    # sort_order should match list position 0..N-1
    for position, opt in enumerate(after):
        assert opt["sort_order"] == position


def test_reorder_rejects_foreign_id(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    ids = [o["id"] for o in options]
    resp = api_client.post(
        "/api/product-attributes/nhan_banh/options/reorder",
        json={"ordered_ids": ids + [99999]},
    )
    assert resp.status_code == 422


# --- default_value validation on product_attributes PATCH ---


def test_patch_attribute_default_value_valid(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    new_default = options[2]
    resp = api_client.patch(
        "/api/product-attributes/nhan_banh",
        json={"default_value": str(new_default["id"])},
    )
    assert resp.status_code == 200
    assert resp.json()["default_value"] == str(new_default["id"])


def test_patch_attribute_default_value_invalid_id_422(api_client):
    resp = api_client.patch(
        "/api/product-attributes/nhan_banh",
        json={"default_value": "999999"},
    )
    assert resp.status_code == 422


def test_patch_attribute_default_value_non_numeric_422(api_client):
    resp = api_client.patch(
        "/api/product-attributes/nhan_banh",
        json={"default_value": "Sầu riêng"},
    )
    assert resp.status_code == 422


def test_patch_attribute_default_value_other_attribute_option_422(api_client):
    # Create a second enum attribute with its own options
    api_client.post(
        "/api/product-attributes",
        json={
            "attribute_type": "mau_kem",
            "label_vi": "Màu kem",
            "value_type": "enum",
            "applicable_categories": ["banh_kem"],
        },
    )
    other_opt = api_client.post(
        "/api/product-attributes/mau_kem/options",
        json={"value_vi": "Hồng"},
    ).json()

    # Try assigning that option as default for nhan_banh — must fail
    resp = api_client.patch(
        "/api/product-attributes/nhan_banh",
        json={"default_value": str(other_opt["id"])},
    )
    assert resp.status_code == 422


def test_patch_attribute_default_value_inactive_option_422(api_client):
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    target = options[1]
    api_client.delete(f"/api/product-attribute-options/{target['id']}")

    resp = api_client.patch(
        "/api/product-attributes/nhan_banh",
        json={"default_value": str(target["id"])},
    )
    assert resp.status_code == 422


# --- Product GET response includes enum_attributes ---


def _find_product_by_code(api_client, code: str) -> dict:
    products = api_client.get("/api/products").json()
    return next(p for p in products if p.get("product_code") == code)


def test_product_response_includes_enum_attributes_for_banh_kem(api_client):
    cake = _find_product_by_code(api_client, "BKS-20")
    pid = cake["id"]
    resp = api_client.get(f"/api/products/{pid}")
    assert resp.status_code == 200
    body = resp.json()
    assert "enum_attributes" in body
    enum_attrs = body["enum_attributes"]
    nhan_banh = next((e for e in enum_attrs if e["attribute_type"] == "nhan_banh"), None)
    assert nhan_banh is not None
    assert nhan_banh["label_vi"] == "Nhân bánh"
    assert nhan_banh["default_option_id"] is not None
    # Only active options are embedded
    assert all(o["active"] == 1 for o in nhan_banh["options"])
    # Exactly one option marked is_default and matches default_option_id
    defaults = [o for o in nhan_banh["options"] if o["is_default"]]
    assert len(defaults) == 1
    assert defaults[0]["id"] == nhan_banh["default_option_id"]
    assert defaults[0]["value_vi"] == "Sầu riêng"


def test_product_response_no_enum_attributes_for_non_applicable(api_client):
    products = api_client.get("/api/products").json()
    # Pick a non-banh_kem product
    other = next(p for p in products if p.get("category") != "banh_kem")
    resp = api_client.get(f"/api/products/{other['id']}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["enum_attributes"] == []


def test_product_response_excludes_inactive_options(api_client):
    cake = _find_product_by_code(api_client, "BKS-20")
    pid = cake["id"]

    # Soft-delete one option
    options = api_client.get("/api/product-attributes/nhan_banh/options").json()
    drop = options[3]
    api_client.delete(f"/api/product-attribute-options/{drop['id']}")

    body = api_client.get(f"/api/products/{pid}").json()
    nhan_banh = next(e for e in body["enum_attributes"] if e["attribute_type"] == "nhan_banh")
    assert all(o["id"] != drop["id"] for o in nhan_banh["options"])
    assert len(nhan_banh["options"]) == 4


def test_product_list_response_includes_enum_attributes(api_client):
    products = api_client.get("/api/products").json()
    for p in products:
        assert "enum_attributes" in p
    cake = next(p for p in products if p.get("product_code") == "BKS-20")
    assert any(e["attribute_type"] == "nhan_banh" for e in cake["enum_attributes"])
