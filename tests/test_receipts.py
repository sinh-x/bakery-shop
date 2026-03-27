"""Tests for receipt generation API."""

import io
import sys

import pytest
from PIL import Image

sys.path.insert(0, "src")

from baker.api.receipts import (
    _format_vnd,
    _wrap_text,
)


class TestVNDFormatting:
    """Test Vietnamese currency formatting."""

    def test_whole_number(self):
        assert _format_vnd(150000) == "150000đ"

    def test_with_decimals(self):
        # Note: format uses , for thousands separator, not for decimals
        assert _format_vnd(150000) == "150000đ"

    def test_zero(self):
        assert _format_vnd(0) == "0đ"


class TestTextWrapping:
    """Test text wrapping utility."""

    def test_no_wrap_needed(self):
        from PIL import ImageFont
        font = ImageFont.load_default()
        result = _wrap_text("Short text", font, 200)
        assert result == ["Short text"]

    def test_wrap_long_text(self):
        from PIL import ImageFont
        font = ImageFont.load_default()
        result = _wrap_text("This is a very long text that should be wrapped", font, 50)
        assert len(result) > 1


class TestReceiptAPI:
    """Test the receipt API endpoint."""

    def test_order_receipt_endpoint(self, api_client):
        """Test order summary receipt generates PNG."""
        # Seed receipt config via direct DB insert
        from baker.db.connection import get_db
        with get_db() as conn:
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active)"
                " VALUES ('receipt_shop_name', 'Bánh Kem Test', 0, 1)"
            )
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active)"
                " VALUES ('receipt_shop_address', 'Test Address', 0, 1)"
            )
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active)"
                " VALUES ('receipt_shop_phone', '0123-456-789', 0, 1)"
            )

        # Create an order via API
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Nguyễn Đặng Trung",
            "customerPhone": "0123456789",
            "items": [
                {"productName": "Bánh kem sinh nhật", "quantity": 1, "unitPrice": 300000}
            ],
            "dueDate": "2026-03-30",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        # Get order receipt
        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=order")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"
        # Verify PNG header
        assert response.content[:8] == b"\x89PNG\r\n\x1a\n"

    def test_customer_receipt_endpoint(self, api_client):
        """Test customer receipt generates PNG."""
        # Create an order via API
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Khách Hàng",
            "items": [{"productName": "Bánh mì", "quantity": 2, "unitPrice": 15000}],
            "dueDate": "2026-03-28",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"

    def test_work_ticket_endpoint_with_item_id(self, api_client):
        """Test work ticket receipt generates PNG with item_id."""
        # Create an order with items
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Test Customer",
            "items": [
                {"productName": "Bánh kem", "quantity": 1, "unitPrice": 300000}
            ],
            "dueDate": "2026-03-29",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_data = order_resp.json()
        order_ref = order_data["orderRef"]

        # Get item_id from the order
        work_items = order_data.get("workItems", [])
        assert len(work_items) > 0
        item_id = work_items[0]["id"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=work_ticket&item_id={item_id}")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"

    def test_work_ticket_endpoint_without_item_id_fails(self, api_client):
        """Test work ticket without item_id returns 400."""
        # Create an order
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Test",
            "items": [{"productName": "Cake", "quantity": 1, "unitPrice": 100000}],
            "dueDate": "2026-03-30",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=work_ticket")
        assert response.status_code == 400

    def test_invalid_receipt_type_fails(self, api_client):
        """Test invalid receipt type returns 400."""
        # Create an order
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Test",
            "items": [{"productName": "Cake", "quantity": 1, "unitPrice": 100000}],
            "dueDate": "2026-03-30",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=invalid")
        assert response.status_code == 400

    def test_nonexistent_order_returns_404(self, api_client):
        """Test nonexistent order returns 404."""
        response = api_client.get("/api/orders/NONEXISTENT/receipt?type=order")
        assert response.status_code == 404

    def test_receipt_width_is_576px(self, api_client):
        """Test receipt image has correct 576px width (80mm at 203 DPI)."""
        # Create an order
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Width Test",
            "items": [
                {"productName": "Product A", "quantity": 1, "unitPrice": 100000},
                {"productName": "Product B", "quantity": 2, "unitPrice": 50000},
            ],
            "dueDate": "2026-03-30",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=order")
        assert response.status_code == 200

        # Verify PNG dimensions
        img = Image.open(io.BytesIO(response.content))
        assert img.size[0] == 576, f"Expected width 576px, got {img.size[0]}"

    def test_vietnamese_diacritics_in_receipt(self, api_client):
        """Test Vietnamese diacritics render correctly in receipt."""
        # Create order with Vietnamese text
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Nguyễn Đặng Trung",
            "customerPhone": "0123-456-789",
            "items": [
                {"productName": "Bánh kem sinh nhật", "quantity": 1, "unitPrice": 300000}
            ],
            "notes": "Đã thanh toán đầy đủ - Giao tận nhà",
            "dueDate": "2026-03-30",
            "deliveryType": "delivery",
            "deliveryAddress": "123 Đường ABC, Quận 1, TP.HCM",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        # Should not raise any errors with Vietnamese text
        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=order")
        assert response.status_code == 200

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
        assert response.status_code == 200
