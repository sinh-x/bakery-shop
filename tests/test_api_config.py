"""Tests for app config API endpoints."""

import pytest
from fastapi.testclient import TestClient

from baker.api.app import create_app
from baker.db.connection import get_db
from baker.db.schema import ensure_schema

app = create_app()
client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_db():
    """Reset and migrate DB before each test."""
    with get_db() as conn:
        ensure_schema(conn)
        # Delete in correct order to avoid foreign key constraints
        conn.execute("DELETE FROM catalog_photo_tags")
        conn.execute("DELETE FROM product_catalog_photos")
        conn.execute("DELETE FROM cost_history")
        conn.execute("DELETE FROM negative_balance")
        conn.execute("DELETE FROM product_attribute_values")
        conn.execute("DELETE FROM product_price_chips")
        conn.execute("DELETE FROM reconciliation_lines")
        conn.execute("DELETE FROM stock_lots")
        conn.execute("DELETE FROM stock_movements")
        conn.execute("DELETE FROM product_attribute_options")
        conn.execute("DELETE FROM product_attributes")
        conn.execute("DELETE FROM products")
        conn.execute("DELETE FROM photos")
        conn.execute("DELETE FROM app_config")
    yield


def test_server_config():
    """Test server timezone config endpoint."""
    response = client.get("/api/config")
    assert response.status_code == 200
    data = response.json()
    assert "timezone" in data
    assert "timezone_offset" in data


def test_get_config_values():
    """Test getting config values by key."""
    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            ("test_key", "test_value", 0),
        )

    response = client.get("/api/config/test_key")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["value"] == "test_value"


def test_create_config_value():
    """Test creating a new config value."""
    response = client.post(
        "/api/config/test_key",
        json={"value": "new_value", "sort_order": 1}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["value"] == "new_value"
    assert data["sort_order"] == 1


def test_create_config_value_duplicate():
    """Test creating a duplicate config value raises 409."""
    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("test_key", "existing_value"),
        )

    response = client.post(
        "/api/config/test_key",
        json={"value": "existing_value"}
    )
    assert response.status_code == 409


def test_update_config_value():
    """Test updating a config value."""
    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            ("test_key", "old_value", 0),
        )

    response = client.put(
        "/api/config/test_key",
        json={"old_value": "old_value", "new_value": "updated_value", "sort_order": 2}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["old_value"] == "old_value"
    assert data["new_value"] == "updated_value"

    # Verify in DB
    with get_db() as conn:
        row = conn.execute(
            "SELECT config_value, sort_order FROM app_config WHERE config_key = ? AND config_value = ?",
            ("test_key", "updated_value")
        ).fetchone()
        assert row is not None
        assert row["config_value"] == "updated_value"
        assert row["sort_order"] == 2


def test_delete_config_value():
    """Test deleting a config value."""
    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("test_key", "value_to_delete"),
        )

    response = client.delete("/api/config/test_key?value=value_to_delete")
    assert response.status_code == 200

    # Verify deleted
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM app_config WHERE config_key = ? AND config_value = ?",
            ("test_key", "value_to_delete")
        ).fetchone()
        assert row is None


def test_get_catalog_tag_usage():
    """Test getting usage information for a catalog tag key."""
    with get_db() as conn:
        # Add a catalog tag
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nam:Nam"),
        )
        
        # Add a product and catalog photo
        conn.execute(
            "INSERT INTO products (name, category) VALUES (?, ?)",
            ("Test Product", "banh_mi"),
        )
        product_id = conn.execute("SELECT id FROM products WHERE name = ?", ("Test Product",)).fetchone()["id"]
        
        # Add a catalog photo
        conn.execute(
            "INSERT INTO product_catalog_photos (product_id, file_path) VALUES (?, ?)",
            (product_id, "test.jpg"),
        )
        photo_id = conn.execute("SELECT id FROM product_catalog_photos WHERE product_id = ?", (product_id,)).fetchone()["id"]
        
        # Add tag to photo
        conn.execute(
            "INSERT INTO catalog_photo_tags (photo_id, tag_key) VALUES (?, ?)",
            (photo_id, "nam"),
        )

    # Test getting usage for existing key
    response = client.get("/api/config/catalog_tag/usage?key=nam")
    assert response.status_code == 200
    data = response.json()
    assert data["key"] == "nam"
    assert data["count"] == 1
    assert product_id in data["product_ids"]

    # Test getting usage for non-existent key
    response = client.get("/api/config/catalog_tag/usage?key=nonexistent")
    assert response.status_code == 404

    # Test getting usage for non-catalog_tag config_key
    response = client.get("/api/config/order_source/usage?key=test")
    assert response.status_code == 404


def test_update_catalog_tag_key_change():
    """Test updating a catalog tag with key change triggers remap."""
    with get_db() as conn:
        # Add catalog tags
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nam:Nam"),
        )
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nu:Nữ"),
        )
        
        # Add a product and catalog photo
        conn.execute(
            "INSERT INTO products (name, category) VALUES (?, ?)",
            ("Test Product", "banh_mi"),
        )
        product_id = conn.execute("SELECT id FROM products WHERE name = ?", ("Test Product",)).fetchone()["id"]
        
        # Add a catalog photo
        conn.execute(
            "INSERT INTO product_catalog_photos (product_id, file_path) VALUES (?, ?)",
            (product_id, "test.jpg"),
        )
        photo_id = conn.execute("SELECT id FROM product_catalog_photos WHERE product_id = ?", (product_id,)).fetchone()["id"]
        
        # Add tag to photo
        conn.execute(
            "INSERT INTO catalog_photo_tags (photo_id, tag_key) VALUES (?, ?)",
            (photo_id, "nam"),
        )

    # Test updating tag with key change
    response = client.put(
        "/api/config/catalog_tag",
        json={"old_value": "audience:nam:Nam", "new_value": "audience:nam-moi:Nam Mới"}
    )
    assert response.status_code == 200
    
    # Verify app_config updated
    with get_db() as conn:
        row = conn.execute(
            "SELECT config_value FROM app_config WHERE config_key = 'catalog_tag' AND config_value = ?",
            ("audience:nam-moi:Nam Mới",)
        ).fetchone()
        assert row is not None
        
        # Verify catalog_photo_tags updated
        tag_row = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ?", (photo_id,)
        ).fetchone()
        assert tag_row["tag_key"] == "nam-moi"


def test_update_catalog_tag_label_only():
    """Test updating a catalog tag label only doesn't change tag_key."""
    with get_db() as conn:
        # Add catalog tag
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nam:Nam"),
        )
        
        # Add a product and catalog photo
        conn.execute(
            "INSERT INTO products (name, category) VALUES (?, ?)",
            ("Test Product", "banh_mi"),
        )
        product_id = conn.execute("SELECT id FROM products WHERE name = ?", ("Test Product",)).fetchone()["id"]
        
        # Add a catalog photo
        conn.execute(
            "INSERT INTO product_catalog_photos (product_id, file_path) VALUES (?, ?)",
            (product_id, "test.jpg"),
        )
        photo_id = conn.execute("SELECT id FROM product_catalog_photos WHERE product_id = ?", (product_id,)).fetchone()["id"]
        
        # Add tag to photo
        conn.execute(
            "INSERT INTO catalog_photo_tags (photo_id, tag_key) VALUES (?, ?)",
            (photo_id, "nam"),
        )

    # Test updating tag with label change only
    response = client.put(
        "/api/config/catalog_tag",
        json={"old_value": "audience:nam:Nam", "new_value": "audience:nam:Name"}
    )
    assert response.status_code == 200
    
    # Verify app_config updated
    with get_db() as conn:
        row = conn.execute(
            "SELECT config_value FROM app_config WHERE config_key = 'catalog_tag' AND config_value = ?",
            ("audience:nam:Name",)
        ).fetchone()
        assert row is not None
        
        # Verify catalog_photo_tags unchanged
        tag_row = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ?", (photo_id,)
        ).fetchone()
        assert tag_row["tag_key"] == "nam"


def test_update_catalog_tag_key_collision():
    """Test updating a catalog tag with key that already exists returns 409."""
    with get_db() as conn:
        # Add catalog tags
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nam:Nam"),
        )
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nu:Nữ"),
        )

    # Test updating tag with key that already exists
    response = client.put(
        "/api/config/catalog_tag",
        json={"old_value": "audience:nam:Nam", "new_value": "audience:nu:Nam"}
    )
    assert response.status_code == 409
    assert "Khoá 'nu' đã tồn tại" in response.json()["detail"]


def test_delete_catalog_tag_in_use():
    """Test deleting a catalog tag that is in use returns 409."""
    with get_db() as conn:
        # Add catalog tag
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nam:Nam"),
        )
        
        # Add a product and catalog photo
        conn.execute(
            "INSERT INTO products (name, category) VALUES (?, ?)",
            ("Test Product", "banh_mi"),
        )
        product_id = conn.execute("SELECT id FROM products WHERE name = ?", ("Test Product",)).fetchone()["id"]
        
        # Add a catalog photo
        conn.execute(
            "INSERT INTO product_catalog_photos (product_id, file_path) VALUES (?, ?)",
            (product_id, "test.jpg"),
        )
        photo_id = conn.execute("SELECT id FROM product_catalog_photos WHERE product_id = ?", (product_id,)).fetchone()["id"]
        
        # Add tag to photo
        conn.execute(
            "INSERT INTO catalog_photo_tags (photo_id, tag_key) VALUES (?, ?)",
            (photo_id, "nam"),
        )

    # Test deleting tag that is in use
    response = client.delete("/api/config/catalog_tag?value=audience:nam:Nam")
    assert response.status_code == 409
    assert "Tag đang được sử dụng" in response.json()["detail"]


def test_delete_catalog_tag_not_in_use():
    """Test deleting a catalog tag that is not in use succeeds."""
    with get_db() as conn:
        # Add catalog tag
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "audience:nam:Nam"),
        )

    # Test deleting tag that is not in use
    response = client.delete("/api/config/catalog_tag?value=audience:nam:Nam")
    assert response.status_code == 200
    
    # Verify deleted
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM app_config WHERE config_key = 'catalog_tag' AND config_value = ?",
            ("audience:nam:Nam",)
        ).fetchone()
        assert row is None


def test_non_catalog_config_unchanged():
    """Test that non-catalog config operations work as before."""
    # Test creating non-catalog config
    response = client.post(
        "/api/config/order_source",
        json={"value": "Facebook", "sort_order": 1}
    )
    assert response.status_code == 200
    
    # Test updating non-catalog config
    response = client.put(
        "/api/config/order_source",
        json={"old_value": "Facebook", "new_value": "Facebook Page"}
    )
    assert response.status_code == 200
    
    # Test deleting non-catalog config
    response = client.delete("/api/config/order_source?value=Facebook Page")
    assert response.status_code == 200


def test_catalog_tag_label_with_colon():
    """Test that tags with colons in labels work correctly (BUG-2 regression)."""
    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value) VALUES (?, ?)",
            ("catalog_tag", "occasion:gio-tan:Gìơ tần: 12:00"),
        )

    # Usage check works despite colon in label (split(':', 2) fix)
    response = client.get("/api/config/catalog_tag/usage?key=gio-tan")
    assert response.status_code == 200
    data = response.json()
    assert data["count"] == 0

    # Delete succeeds when tag not in use
    response = client.delete(
        "/api/config/catalog_tag?value=occasion:gio-tan:Gìơ tần: 12:00"
    )
    assert response.status_code == 200

    # Verify deleted
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM app_config WHERE config_key = 'catalog_tag'"
            " AND config_value = ?",
            ("occasion:gio-tan:Gìơ tần: 12:00",)
        ).fetchone()
        assert row is None
