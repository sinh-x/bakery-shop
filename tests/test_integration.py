"""Integration tests: API ↔ CLI round-trip.

Verify that products created/edited/deleted via the API are visible
through direct DB queries (the same path the CLI uses).
"""

import io

from PIL import Image


def _make_test_image(width=100, height=100) -> bytes:
    """Create a minimal JPEG image for testing."""
    img = Image.new("RGB", (width, height), color="blue")
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf.read()


def _db_query(query, params=()):
    """Direct DB query — same path as CLI commands."""
    from baker.db.connection import get_db

    with get_db() as conn:
        rows = conn.execute(query, params).fetchall()
        return [dict(r) for r in rows]


def _db_query_one(query, params=()):
    """Direct DB query returning one row."""
    rows = _db_query(query, params)
    return rows[0] if rows else None


# --- Create via API, read via CLI DB ---


def test_create_product_visible_in_cli_db(api_client):
    """Create a product via API → verify it exists via direct DB query (CLI path)."""
    resp = api_client.post("/api/products", json={
        "name": "Bánh tích hợp",
        "category": "cake",
        "base_price": 120000,
        "cost": 45000,
        "recipe_notes": "Test integration",
    })
    assert resp.status_code == 201
    product_id = resp.json()["id"]

    # CLI reads DB directly — same query as `baker product list`
    row = _db_query_one(
        "SELECT * FROM products WHERE id = ?", (product_id,)
    )
    assert row is not None
    assert row["name"] == "Bánh tích hợp"
    assert row["category"] == "cake"
    assert row["base_price"] == 120000
    assert row["cost"] == 45000
    assert row["active"] == 1


def test_create_product_appears_in_active_list(api_client):
    """Create via API → appears in CLI's active product list query."""
    api_client.post("/api/products", json={
        "name": "Bánh kiểm tra danh sách",
        "category": "pastry",
        "base_price": 80000,
    })

    # Same query as `baker product list`
    rows = _db_query(
        "SELECT * FROM products WHERE active = 1 ORDER BY category, name"
    )
    names = [r["name"] for r in rows]
    assert "Bánh kiểm tra danh sách" in names


# --- Edit via API, read via CLI DB ---


def test_edit_product_price_visible_in_cli_db(api_client):
    """Edit product price via API → CLI sees updated price."""
    # Get a seeded product
    resp = api_client.get("/api/products/1")
    original_name = resp.json()["name"]

    # Update price via API
    api_client.patch("/api/products/1", json={"base_price": 75000})

    # CLI reads DB directly
    row = _db_query_one("SELECT * FROM products WHERE id = 1")
    assert row["base_price"] == 75000
    assert row["name"] == original_name  # name unchanged


def test_edit_product_name_visible_in_cli_db(api_client):
    """Edit product name via API → CLI sees updated name."""
    api_client.patch("/api/products/1", json={"name": "Bánh mì đặc biệt v2"})

    # CLI uses name-based lookup: `baker product edit "Bánh mì đặc biệt v2"`
    row = _db_query_one(
        "SELECT * FROM products WHERE name = ?", ("Bánh mì đặc biệt v2",)
    )
    assert row is not None
    assert row["id"] == 1


# --- Delete via API, read via CLI DB ---


def test_delete_product_hidden_from_cli_active_list(api_client):
    """Soft-delete via API → product hidden from CLI's active list."""
    resp = api_client.delete("/api/products/1")
    assert resp.status_code == 200

    # CLI's active list query excludes soft-deleted
    rows = _db_query(
        "SELECT * FROM products WHERE active = 1 ORDER BY category, name"
    )
    ids = [r["id"] for r in rows]
    assert 1 not in ids

    # But the row still exists in DB (soft-delete)
    row = _db_query_one("SELECT * FROM products WHERE id = 1")
    assert row is not None
    assert row["active"] == 0


# --- Photo upload via API, verify on disk ---


def test_upload_photo_creates_file_on_disk(api_client):
    """Upload photo via API → file exists on disk where CLI/API can access it."""
    import baker.config

    image_data = _make_test_image()
    resp = api_client.post(
        "/api/products/1/photo",
        files={"file": ("product.jpg", image_data, "image/jpeg")},
    )
    assert resp.status_code == 200

    # Photo file is on disk at the expected path
    photo_path = baker.config.PHOTOS_DIR / "1.jpg"
    assert photo_path.exists()

    # DB has the photo_path (accessible by CLI)
    row = _db_query_one("SELECT photo_path FROM products WHERE id = 1")
    assert row["photo_path"] == "photos/products/1.jpg"


def test_upload_photo_then_serve_matches(api_client):
    """Upload photo → GET photo returns valid JPEG content."""
    image_data = _make_test_image(200, 150)
    api_client.post(
        "/api/products/1/photo",
        files={"file": ("photo.jpg", image_data, "image/jpeg")},
    )

    resp = api_client.get("/api/products/1/photo")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/jpeg"

    # Verify it's a valid image
    img = Image.open(io.BytesIO(resp.content))
    assert img.format == "JPEG"


# --- Full round-trip: create + photo + edit + verify ---


def test_full_product_lifecycle(api_client):
    """Full round-trip: create → upload photo → edit → verify all in DB."""
    import baker.config

    # 1. Create product via API
    resp = api_client.post("/api/products", json={
        "name": "Bánh vòng đời",
        "category": "cookie",
        "base_price": 35000,
        "cost": 12000,
    })
    assert resp.status_code == 201
    pid = resp.json()["id"]

    # 2. Upload photo
    image_data = _make_test_image(300, 300)
    resp = api_client.post(
        f"/api/products/{pid}/photo",
        files={"file": ("lifecycle.jpg", image_data, "image/jpeg")},
    )
    assert resp.status_code == 200

    # 3. Edit price and notes
    api_client.patch(f"/api/products/{pid}", json={
        "base_price": 40000,
        "recipe_notes": "Công thức đã cập nhật",
    })

    # 4. Verify everything via direct DB (CLI path)
    row = _db_query_one("SELECT * FROM products WHERE id = ?", (pid,))
    assert row["name"] == "Bánh vòng đời"
    assert row["category"] == "cookie"
    assert row["base_price"] == 40000  # updated
    assert row["cost"] == 12000
    assert row["recipe_notes"] == "Công thức đã cập nhật"
    assert row["photo_path"] == f"photos/products/{pid}.jpg"
    assert row["active"] == 1

    # 5. Photo file exists on disk
    assert (baker.config.PHOTOS_DIR / f"{pid}.jpg").exists()

    # 6. Photo served via API
    resp = api_client.get(f"/api/products/{pid}/photo")
    assert resp.status_code == 200


# --- product_code integration ---


def test_create_product_code_visible_in_db(api_client):
    """Auto-generated product_code is stored in DB (accessible by CLI)."""
    resp = api_client.post("/api/products", json={
        "name": "Bánh tích hợp có mã",
        "category": "banh_mi",
        "base_price": 15000,
    })
    assert resp.status_code == 201
    api_code = resp.json()["product_code"]
    assert api_code.startswith("BMI-")

    # CLI reads DB directly — verify code is persisted
    pid = resp.json()["id"]
    row = _db_query_one("SELECT product_code FROM products WHERE id = ?", (pid,))
    assert row is not None
    assert row["product_code"] == api_code


def test_update_product_code_visible_in_db(api_client):
    """Updating product_code via API is reflected in DB."""
    api_client.patch("/api/products/1", json={"product_code": "BMI-99"})

    row = _db_query_one("SELECT product_code FROM products WHERE id = 1")
    assert row["product_code"] == "BMI-99"


def test_find_product_by_code_in_db(api_client):
    """Seeded products can be looked up by code directly in DB — same as CLI code lookup."""
    row = _db_query_one(
        "SELECT * FROM products WHERE product_code = ?", ("BMI-01",)
    )
    assert row is not None
    assert row["name"] == "Bánh mì trắng"


def test_categories_table_seeded_in_db(api_client):
    """Categories table has 5 seeded rows, queryable by CLI."""
    rows = _db_query("SELECT slug FROM categories WHERE active = 1 ORDER BY slug")
    slugs = [r["slug"] for r in rows]
    assert slugs == ["banh_kem", "banh_mi", "banh_ngot", "cookie", "khac"]
