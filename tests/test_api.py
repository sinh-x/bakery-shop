"""Tests for Baker API — product endpoints + photo upload."""

import io

from PIL import Image


# --- Health ---


def test_health(api_client):
    resp = api_client.get("/api/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "version" in data


# --- List products ---


def test_list_products_returns_seeded(api_client):
    """Migrations seed 40 products (23 base + 12 cake variants + 5 su kem sets)."""
    resp = api_client.get("/api/products")
    assert resp.status_code == 200
    products = resp.json()
    assert len(products) == 40


def test_list_products_filter_by_category(api_client):
    resp = api_client.get("/api/products", params={"category": "cookie"})
    assert resp.status_code == 200
    products = resp.json()
    assert len(products) > 0
    assert all(p["category"] == "cookie" for p in products)


def test_list_products_filter_inactive(api_client):
    """active=0 should return nothing when all products are active."""
    resp = api_client.get("/api/products", params={"active": 0})
    assert resp.status_code == 200
    assert resp.json() == []


# --- Get product ---


def test_get_product(api_client):
    resp = api_client.get("/api/products/1")
    assert resp.status_code == 200
    product = resp.json()
    assert product["id"] == 1
    assert "name" in product


def test_get_product_not_found(api_client):
    resp = api_client.get("/api/products/9999")
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


# --- Create product ---


def test_create_product(api_client):
    resp = api_client.post("/api/products", json={
        "name": "Bánh test mới",
        "category": "other",
        "base_price": 50000,
        "cost": 20000,
        "recipe_notes": "Test product",
    })
    assert resp.status_code == 201
    product = resp.json()
    assert product["name"] == "Bánh test mới"
    assert product["category"] == "other"
    assert product["base_price"] == 50000
    assert product["active"] == 1


def test_create_product_defaults(api_client):
    resp = api_client.post("/api/products", json={"name": "Bánh đơn giản"})
    assert resp.status_code == 201
    product = resp.json()
    assert product["category"] == "bread"
    assert product["base_price"] == 0


def test_create_product_duplicate_name(api_client):
    """Seeded product name should conflict."""
    resp = api_client.post("/api/products", json={"name": "Bánh mì trắng"})
    assert resp.status_code == 409
    assert "đã tồn tại" in resp.json()["detail"]


# --- Update product ---


def test_update_product_price(api_client):
    resp = api_client.patch("/api/products/1", json={"base_price": 99000})
    assert resp.status_code == 200
    assert resp.json()["base_price"] == 99000


def test_update_product_name(api_client):
    resp = api_client.patch("/api/products/1", json={"name": "Bánh mì đặc biệt"})
    assert resp.status_code == 200
    assert resp.json()["name"] == "Bánh mì đặc biệt"


def test_update_product_duplicate_name(api_client):
    """Renaming to an existing product name should fail."""
    resp = api_client.patch("/api/products/1", json={"name": "Bánh mì ngọt"})
    assert resp.status_code == 409
    assert "đã tồn tại" in resp.json()["detail"]


def test_update_product_empty_body(api_client):
    resp = api_client.patch("/api/products/1", json={})
    assert resp.status_code == 400
    assert "Không có gì để cập nhật" in resp.json()["detail"]


def test_update_product_not_found(api_client):
    resp = api_client.patch("/api/products/9999", json={"base_price": 1000})
    assert resp.status_code == 404


# --- Delete (soft) product ---


def test_delete_product(api_client):
    resp = api_client.delete("/api/products/1")
    assert resp.status_code == 200
    assert "ngừng bán" in resp.json()["message"]

    # Verify it no longer shows in active list
    list_resp = api_client.get("/api/products")
    ids = [p["id"] for p in list_resp.json()]
    assert 1 not in ids

    # But shows in inactive list
    inactive_resp = api_client.get("/api/products", params={"active": 0})
    ids = [p["id"] for p in inactive_resp.json()]
    assert 1 in ids


def test_delete_product_not_found(api_client):
    resp = api_client.delete("/api/products/9999")
    assert resp.status_code == 404


# --- Photo upload ---


def _make_test_image(width=100, height=100) -> bytes:
    """Create a minimal JPEG image for testing."""
    img = Image.new("RGB", (width, height), color="red")
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf.read()


def test_upload_photo(api_client):
    image_data = _make_test_image()
    resp = api_client.post(
        "/api/products/1/photo",
        files={"file": ("test.jpg", image_data, "image/jpeg")},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "photo_path" in data
    assert "Đã tải lên" in data["message"]


def test_upload_photo_and_serve(api_client):
    image_data = _make_test_image()
    api_client.post(
        "/api/products/1/photo",
        files={"file": ("test.jpg", image_data, "image/jpeg")},
    )

    resp = api_client.get("/api/products/1/photo")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/jpeg"
    assert len(resp.content) > 0


def test_upload_photo_resizes_large_image(api_client):
    """Images larger than 1200px should be resized."""
    image_data = _make_test_image(width=2000, height=1500)
    api_client.post(
        "/api/products/1/photo",
        files={"file": ("big.jpg", image_data, "image/jpeg")},
    )

    # Verify the saved photo is resized
    import baker.config
    photo_path = baker.config.PHOTOS_DIR / "1.jpg"
    assert photo_path.exists()
    saved = Image.open(photo_path)
    assert max(saved.size) <= 1200


def test_upload_photo_product_not_found(api_client):
    image_data = _make_test_image()
    resp = api_client.post(
        "/api/products/9999/photo",
        files={"file": ("test.jpg", image_data, "image/jpeg")},
    )
    assert resp.status_code == 404


def test_upload_photo_empty_file(api_client):
    resp = api_client.post(
        "/api/products/1/photo",
        files={"file": ("empty.jpg", b"", "image/jpeg")},
    )
    assert resp.status_code == 400
    assert "rỗng" in resp.json()["detail"]


def test_get_photo_not_found(api_client):
    resp = api_client.get("/api/products/1/photo")
    assert resp.status_code == 404
    assert "Chưa có ảnh" in resp.json()["detail"]


# --- Photo path in product data ---


def test_upload_photo_updates_photo_path(api_client):
    image_data = _make_test_image()
    api_client.post(
        "/api/products/1/photo",
        files={"file": ("test.jpg", image_data, "image/jpeg")},
    )

    resp = api_client.get("/api/products/1")
    assert resp.status_code == 200
    assert resp.json()["photo_path"] == "photos/products/1.jpg"


# --- product_code field ---


def test_seeded_product_has_product_code(api_client):
    """Every seeded product must have a non-empty product_code."""
    resp = api_client.get("/api/products")
    assert resp.status_code == 200
    for product in resp.json():
        assert "product_code" in product
        assert product["product_code"] != "", (
            f"Product '{product['name']}' (id={product['id']}) has empty product_code"
        )


def test_product_code_matches_convention(api_client):
    """Product #1 ('Bánh mì trắng') should have code BMI-01."""
    resp = api_client.get("/api/products/1")
    assert resp.status_code == 200
    assert resp.json()["product_code"] == "BMI-01"


# --- Filter by code ---


def test_list_products_filter_by_code_partial(api_client):
    """?code=BMI returns all Bánh mì products."""
    resp = api_client.get("/api/products", params={"code": "BMI"})
    assert resp.status_code == 200
    products = resp.json()
    assert len(products) > 0
    assert all("BMI" in p["product_code"] for p in products)


def test_list_products_filter_by_code_exact(api_client):
    """?code=BMI-01 returns exactly one product."""
    resp = api_client.get("/api/products", params={"code": "BMI-01"})
    assert resp.status_code == 200
    products = resp.json()
    assert len(products) == 1
    assert products[0]["product_code"] == "BMI-01"


def test_list_products_filter_by_code_no_match(api_client):
    resp = api_client.get("/api/products", params={"code": "ZZZNOMATCH"})
    assert resp.status_code == 200
    assert resp.json() == []


# --- Get by code ---


def test_get_product_by_code(api_client):
    resp = api_client.get("/api/products/code/BMI-01")
    assert resp.status_code == 200
    product = resp.json()
    assert product["product_code"] == "BMI-01"
    assert product["name"] == "Bánh mì trắng"


def test_get_product_by_code_cake_variant(api_client):
    resp = api_client.get("/api/products/code/BKS-16")
    assert resp.status_code == 200
    assert resp.json()["product_code"] == "BKS-16"


def test_get_product_by_code_set(api_client):
    resp = api_client.get("/api/products/code/BNG-S06")
    assert resp.status_code == 200
    assert resp.json()["product_code"] == "BNG-S06"


def test_get_product_by_code_not_found(api_client):
    resp = api_client.get("/api/products/code/NOTREAL")
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


# --- Create with explicit code ---


def test_create_product_with_explicit_code(api_client):
    resp = api_client.post("/api/products", json={
        "name": "Bánh test mã tùy chỉnh",
        "category": "banh_mi",
        "product_code": "BMI-99",
    })
    assert resp.status_code == 201
    assert resp.json()["product_code"] == "BMI-99"


def test_create_product_auto_generates_code(api_client):
    """Creating without product_code should auto-generate one."""
    resp = api_client.post("/api/products", json={
        "name": "Bánh tự động mã",
        "category": "banh_mi",
    })
    assert resp.status_code == 201
    code = resp.json()["product_code"]
    assert code.startswith("BMI-")
    assert code != ""


def test_create_product_invalid_code_format(api_client):
    resp = api_client.post("/api/products", json={
        "name": "Bánh mã sai",
        "category": "banh_mi",
        "product_code": "invalid-code",
    })
    assert resp.status_code == 422
    assert "Mã sản phẩm không hợp lệ" in resp.json()["detail"]


def test_create_product_duplicate_code(api_client):
    """Attempting to use an already-assigned code should fail."""
    resp = api_client.post("/api/products", json={
        "name": "Bánh mã trùng",
        "category": "banh_mi",
        "product_code": "BMI-01",
    })
    assert resp.status_code == 409
    assert "đã tồn tại" in resp.json()["detail"]


# --- Update product_code ---


def test_update_product_code(api_client):
    resp = api_client.patch("/api/products/1", json={"product_code": "BMI-99"})
    assert resp.status_code == 200
    assert resp.json()["product_code"] == "BMI-99"


def test_update_product_code_duplicate(api_client):
    """PATCH with a code that belongs to another product should fail."""
    # Product 1 = BMI-01, product 2 = BMI-02
    resp = api_client.patch("/api/products/1", json={"product_code": "BMI-02"})
    assert resp.status_code == 409
    assert "đã tồn tại" in resp.json()["detail"]


# --- Categories API ---


def test_list_categories(api_client):
    resp = api_client.get("/api/categories")
    assert resp.status_code == 200
    categories = resp.json()
    assert len(categories) == 5


def test_list_categories_has_seeded_slugs(api_client):
    resp = api_client.get("/api/categories")
    slugs = {c["slug"] for c in resp.json()}
    assert slugs == {"banh_mi", "banh_kem", "banh_ngot", "cookie", "khac"}


def test_list_categories_has_code_prefixes(api_client):
    resp = api_client.get("/api/categories")
    prefix_map = {c["slug"]: c["code_prefix"] for c in resp.json()}
    assert prefix_map["banh_mi"] == "BMI"
    assert prefix_map["banh_kem"] == "BKS"
    assert prefix_map["banh_ngot"] == "BNG"
    assert prefix_map["cookie"] == "CKI"
    assert prefix_map["khac"] == "KHA"


def test_create_category(api_client):
    resp = api_client.post("/api/categories", json={
        "slug": "tra_sua",
        "name": "Trà sữa",
        "code_prefix": "TRS",
    })
    assert resp.status_code == 201
    cat = resp.json()
    assert cat["slug"] == "tra_sua"
    assert cat["name"] == "Trà sữa"
    assert cat["code_prefix"] == "TRS"


def test_create_category_appears_in_list(api_client):
    api_client.post("/api/categories", json={
        "slug": "che",
        "name": "Chè",
        "code_prefix": "CHE",
    })
    resp = api_client.get("/api/categories")
    slugs = [c["slug"] for c in resp.json()]
    assert "che" in slugs


def test_create_category_duplicate_slug(api_client):
    resp = api_client.post("/api/categories", json={
        "slug": "banh_mi",
        "name": "Duplicate",
        "code_prefix": "DUP",
    })
    assert resp.status_code == 409
    assert "đã tồn tại" in resp.json()["detail"]
