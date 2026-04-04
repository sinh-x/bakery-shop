"""Tests for receipt generation API."""

import io
import sys

import pytest
from PIL import Image

sys.path.insert(0, "src")

from baker.api.receipts import (
    _format_vnd,
    _wrap,
)


class TestVNDFormatting:
    """Test Vietnamese currency formatting (shortened: divide by 1000, no suffix)."""

    def test_whole_number(self):
        assert _format_vnd(150000) == "150"

    def test_large_number(self):
        assert _format_vnd(1500000) == "1500"

    def test_zero(self):
        assert _format_vnd(0) == "0"

    def test_small_number(self):
        assert _format_vnd(5000) == "5"


class TestTextWrapping:
    """Test text wrapping utility."""

    def test_no_wrap_needed(self):
        from PIL import ImageFont
        font = ImageFont.load_default()
        result = _wrap("Short text", font, 200)
        assert result == ["Short text"]

    def test_wrap_long_text(self):
        from PIL import ImageFont
        font = ImageFont.load_default()
        result = _wrap("This is a very long text that should be wrapped", font, 50)
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
        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
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
        response = api_client.get("/api/orders/NONEXISTENT/receipt?type=customer")
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

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
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
        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
        assert response.status_code == 200

    def test_shop_receipt_endpoint(self, api_client):
        """Test shop receipt (Phiếu giao hàng) generates PNG."""
        # Create an order with multiple items
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Trần Văn Minh",
            "customerPhone": "0987-654-321",
            "items": [
                {"productName": "Bánh kem sinh nhật", "quantity": 1, "unitPrice": 300000},
                {"productName": "Bánh bông lan", "quantity": 2, "unitPrice": 50000},
            ],
            "dueDate": "2026-04-05",
            "deliveryType": "pickup",
            "notes": "Khách lấy vào buổi sáng",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=shop")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"
        # Verify PNG header
        assert response.content[:8] == b"\x89PNG\r\n\x1a\n"

    def test_shop_receipt_width_is_576px(self, api_client):
        """Test shop receipt image has correct 576px width (80mm at 203 DPI)."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Lê Hoàng",
            "items": [
                {"productName": "Bánh mì", "quantity": 1, "unitPrice": 15000},
            ],
            "dueDate": "2026-04-06",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=shop")
        assert response.status_code == 200

        img = Image.open(io.BytesIO(response.content))
        assert img.size[0] == 576, f"Expected width 576px, got {img.size[0]}"

    def test_delivery_receipt_endpoint(self, api_client):
        """Test delivery receipt (Phiếu giao tận nơi) generates PNG."""
        # Create a door-to-door delivery order with all fields
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Phạm Thị Hương",
            "customerPhone": "0901-234-567",
            "items": [
                {"productName": "Bánh kem dâu", "quantity": 1, "unitPrice": 250000},
                {"productName": "Bánh cookies", "quantity": 3, "unitPrice": 35000},
            ],
            "dueDate": "2026-04-07",
            "dueTime": "14:00",
            "deliveryType": "door",
            "deliveryAddress": "456 Đường XYZ, Quận 3, TP.HCM",
            "deliveryNotes": "Gọi điện trước khi giao",
            "notes": "Khách yêu cầu giao giờ hành chính",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=delivery")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"
        # Verify PNG header
        assert response.content[:8] == b"\x89PNG\r\n\x1a\n"

    def test_delivery_receipt_width_is_576px(self, api_client):
        """Test delivery receipt image has correct 576px width."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Ngô Đình",
            "items": [
                {"productName": "Bánh flan", "quantity": 1, "unitPrice": 80000},
            ],
            "dueDate": "2026-04-08",
            "deliveryType": "door",
            "deliveryAddress": "789 Đường QRS, Quận 5, TP.HCM",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=delivery")
        assert response.status_code == 200

        img = Image.open(io.BytesIO(response.content))
        assert img.size[0] == 576, f"Expected width 576px, got {img.size[0]}"

    def test_delivery_receipt_with_gift_and_extra_items(self, api_client):
        """Test delivery receipt renders gift items with (Tặng) suffix and extra items."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Hoàng Thanh",
            "customerPhone": "0932-111-222",
            "items": [
                {"productName": "Bánh sinh nhật", "quantity": 1, "unitPrice": 350000},
                {"productName": "Khăn trải bàn", "quantity": 1, "unitPrice": 0, "isGift": True},
                {"productName": "Nến sinh nhật", "quantity": 2, "unitPrice": 15000, "isExtra": True},
            ],
            "dueDate": "2026-04-10",
            "deliveryType": "door",
            "deliveryAddress": "111 Đường ABC, Quận 7, TP.HCM",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        # Should render without errors for mixed gift/extra items
        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=delivery")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"

    def test_shop_receipt_with_gift_and_extra_items(self, api_client):
        """Test shop receipt renders gift items with (Tặng) suffix and extra items."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Trần Văn Minh",
            "customerPhone": "0944-555-666",
            "items": [
                {"productName": "Bánh sinh nhật", "quantity": 1, "unitPrice": 350000},
                {"productName": "Khăn trải bàn", "quantity": 1, "unitPrice": 0, "isGift": True},
                {"productName": "Nến sinh nhật", "quantity": 2, "unitPrice": 15000, "isExtra": True},
            ],
            "dueDate": "2026-04-10",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        # Should render without errors for mixed gift/extra items
        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=shop")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"

    def test_bus_label_includes_order_ref_and_customer_name(self, api_client):
        """Test bus label now includes order ref and customer name (AC7, AC8)."""
        # Create a bus delivery order
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Đỗ Minh Quân",
            "customerPhone": "0977-888-999",
            "items": [
                {"productName": "Bánh gấu", "quantity": 1, "unitPrice": 180000},
            ],
            "dueDate": "2026-04-12",
            "deliveryType": "bus",
            "deliveryAddress": "Bến xe Ninh Hòa - Khánh Hòa",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=bus_label")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"

        # Bus label is rotated 90° CCW so width=576, height=1024
        img = Image.open(io.BytesIO(response.content))
        assert img.size[0] == 576, f"Expected width 576px, got {img.size[0]}"
        # Height should be around 1024 (landscape rotated) — allow some tolerance
        assert img.size[1] >= 900, f"Expected height >= 900px, got {img.size[1]}"
        # Verify PNG header
        assert response.content[:8] == b"\x89PNG\r\n\x1a\n"

    def test_bus_label_renders_for_all_delivery_types(self, api_client):
        """Test bus label renders for bus delivery type orders."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Võ Thị Lan",
            "customerPhone": "0955-333-444",
            "items": [
                {"productName": "Bánh pía", "quantity": 2, "unitPrice": 45000},
            ],
            "dueDate": "2026-04-15",
            "deliveryType": "bus",
            "deliveryAddress": "Bến xe Phú Yên",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=bus_label")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"
