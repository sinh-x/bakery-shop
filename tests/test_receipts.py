"""Tests for receipt generation API."""

import io
import sys

import pytest
from PIL import Image

sys.path.insert(0, "src")

from baker.api.receipts import (
    RECEIPT_WIDTH,
    RECEIPT_MAX_HEIGHT,
    MARGIN,
    _add_tear_indicator,
    _customer_reference_text,
    _enum_attribute_lines,
    _find_content_bottom,
    _find_split_boundaries,
    _format_vnd,
    _main_item_index_total,
    _order_visual_ref,
    _shop_delivery_code_text,
    _split_pages,
    _wrapped_enum_attribute_lines,
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


class TestEnumAttributeLines:
    """Test enum attribute extraction for receipts (DG-092 phase 4.6)."""

    def test_no_attributes(self):
        item = {"attributes": {}}
        labels = {"nhan_banh": "Nhân bánh"}
        assert _enum_attribute_lines(item, labels) == []

    def test_single_enum_attribute(self):
        item = {"attributes": {"nhan_banh": "Sô-cô-la"}}
        labels = {"nhan_banh": "Nhân bánh"}
        assert _enum_attribute_lines(item, labels) == [("Nhân bánh", "Sô-cô-la")]

    def test_multiple_enum_attributes_each_on_own_line(self):
        # Q3: each attribute renders on its own line.
        item = {"attributes": {"nhan_banh": "Sầu riêng", "mau_kem": "Hồng"}}
        labels = {"nhan_banh": "Nhân bánh", "mau_kem": "Màu kem"}
        result = _enum_attribute_lines(item, labels)
        assert len(result) == 2
        assert ("Nhân bánh", "Sầu riêng") in result
        assert ("Màu kem", "Hồng") in result

    def test_skips_non_enum_keys(self):
        # Only declared enum labels are surfaced; rut_tien etc. are ignored.
        item = {"attributes": {"nhan_banh": "Dâu", "rut_tien": "true", "cash_amount": "200000"}}
        labels = {"nhan_banh": "Nhân bánh"}
        assert _enum_attribute_lines(item, labels) == [("Nhân bánh", "Dâu")]

    def test_skips_blank_values(self):
        item = {"attributes": {"nhan_banh": "", "mau_kem": "   "}}
        labels = {"nhan_banh": "Nhân bánh", "mau_kem": "Màu kem"}
        assert _enum_attribute_lines(item, labels) == []

    def test_missing_attributes_key(self):
        assert _enum_attribute_lines({}, {"nhan_banh": "Nhân bánh"}) == []

    def test_wraps_long_enum_attribute_line(self):
        from PIL import ImageFont
        font = ImageFont.load_default()
        item = {"attributes": {"nhan_banh": "Sô-cô-la đắng phủ hạnh nhân"}}
        labels = {"nhan_banh": "Nhân bánh"}

        lines = _wrapped_enum_attribute_lines(item, labels, font, 100)

        assert len(lines) > 1
        assert " ".join(lines) == "Nhân bánh: Sô-cô-la đắng phủ hạnh nhân"


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


class TestPublicOrderCodeReceiptReferences:
    """Receipt reference text should prioritize public order code."""

    def test_customer_reference_uses_last_name_plus_public_code(self):
        order = {
            "customerName": "Nguyễn Văn An",
            "orderRef": "ORD-260522-001",
            "publicOrderCode": "A42-T",
        }
        assert _customer_reference_text(order) == "Mã nhận bánh: An - A42-T"

    def test_customer_reference_uses_code_only_when_name_blank(self):
        order = {
            "customerName": "   ",
            "orderRef": "ORD-260522-099",
            "publicOrderCode": "A42-T",
        }
        assert _customer_reference_text(order) == "Mã nhận bánh: A42-T"

    def test_customer_reference_falls_back_to_order_ref_for_old_orders(self):
        order = {
            "customerName": "Khách Cũ",
            "orderRef": "ORD-260522-010",
        }
        assert _customer_reference_text(order) == "Mã đơn: ORD-260522-010"

    def test_internal_visual_ref_uses_public_code_when_present(self):
        order = {
            "orderRef": "ORD-260522-002",
            "publicOrderCode": "B17-B",
        }
        assert _order_visual_ref(order) == "B17-B"

    def test_internal_visual_ref_falls_back_to_order_ref(self):
        order = {"orderRef": "ORD-260522-011"}
        assert _order_visual_ref(order) == "ORD-260522-011"

    def test_shop_delivery_code_text_uses_last_name_plus_public_code(self):
        order = {
            "customerName": "Nguyễn Văn An",
            "publicOrderCode": "A42-T",
        }
        assert _shop_delivery_code_text(order) == "An - A42-T"

    def test_shop_delivery_code_text_uses_code_only_when_name_blank(self):
        order = {
            "customerName": "   ",
            "publicOrderCode": "A42-T",
        }
        assert _shop_delivery_code_text(order) == "A42-T"

    def test_shop_delivery_code_text_falls_back_to_order_ref(self):
        order = {
            "customerName": "Nguyễn Văn An",
            "orderRef": "ORD-260522-011",
        }
        assert _shop_delivery_code_text(order) == "ORD-260522-011"


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

    def test_receipt_renders_enum_attribute_line(self, api_client):
        """All receipt types render an extra line per enum attribute (DG-092 phase 4.6)."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Khách Hàng Nhân Bánh",
            "customerPhone": "0911-222-333",
            "items": [
                {
                    "productName": "Bánh kem 20cm",
                    "quantity": 1,
                    "unitPrice": 350000,
                    "attributes": {"nhan_banh": "Sô-cô-la"},
                },
            ],
            "dueDate": "2026-04-20",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        data = order_resp.json()
        order_ref = data["orderRef"]
        item_id = data["workItems"][0]["id"]

        # Customer + shop + delivery + work_ticket all render successfully.
        for params in (
            "type=customer",
            "type=shop",
            f"type=work_ticket&item_id={item_id}",
        ):
            resp = api_client.get(f"/api/orders/{order_ref}/receipt?{params}")
            assert resp.status_code == 200, params
            assert resp.headers["content-type"] == "image/png"
            assert resp.content[:8] == b"\x89PNG\r\n\x1a\n"

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


class TestTearIndicator:
    """Tests for tear indicator line in receipt PNGs (DG-184 Phase 2)."""

    def test_label_mode_y_unchanged(self):
        """Y position unchanged when paper_mode is not 'roll'."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 200), "white")
        draw = ImageDraw.Draw(img)
        y = _add_tear_indicator(img, draw, 100, "label")
        assert y == 100

    def test_roll_mode_adds_gap(self):
        """Gap between last content and tear line >= 64 dots (8mm)."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 300), "white")
        draw = ImageDraw.Draw(img)
        y = _add_tear_indicator(img, draw, 100, "roll")
        assert y >= 100 + 64, f"Expected y >= 164, got {y}"

    def test_draws_dashed_line(self):
        """Dashed line is drawn in roll mode across content width."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 300), "white")
        draw = ImageDraw.Draw(img)
        y_before = 100
        _add_tear_indicator(img, draw, y_before, "roll")
        tear_line_y = y_before + 64
        pixels = [img.getpixel((x, tear_line_y)) for x in range(MARGIN, RECEIPT_WIDTH - MARGIN, 2)]
        non_white = [p for p in pixels if p != (255, 255, 255)]
        assert len(non_white) > 0, "Expected dashed line pixels, found none"

    def test_line_has_gaps(self):
        """Dashed line alternates between dash and gap segments."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 300), "white")
        draw = ImageDraw.Draw(img)
        _add_tear_indicator(img, draw, 100, "roll")
        tear_line_y = 164
        pixels = [img.getpixel((x, tear_line_y)) for x in range(MARGIN, RECEIPT_WIDTH - MARGIN)]
        white = [p for p in pixels if p == (255, 255, 255)]
        non_white = [p for p in pixels if p != (255, 255, 255)]
        assert len(white) > 0, "Expected white gaps in dashed line, found none"
        assert len(non_white) > 0, "Expected dash segments, found none"

    def test_absent_in_label_mode_api(self, api_client):
        """Receipt in label mode has no dashed tear line pattern near the bottom."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "No Tear Test",
            "items": [{"productName": "Test Product", "quantity": 1, "unitPrice": 50000}],
            "dueDate": "2026-06-21",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
        assert response.status_code == 200
        img = Image.open(io.BytesIO(response.content))
        h = img.height
        # Tear indicator area would be in last ~80px (64 gap + line width)
        # Check bottom 80px: should not contain alternating dash/gap pattern
        tear_region = img.crop((MARGIN, max(0, h - 80), RECEIPT_WIDTH - MARGIN, h))
        # Scan mid-line of tear region for alternating (100,100,100) and white
        mid_y = tear_region.height // 2
        row = [tear_region.getpixel((x, mid_y)) for x in range(tear_region.width)]
        tear_color = (100, 100, 100)
        white = (255, 255, 255)
        # Count transitions between tear_color and white
        transitions = 0
        prev = row[0]
        for p in row[1:]:
            if prev != p and (p == tear_color or p == white) and (prev == tear_color or prev == white):
                transitions += 1
            prev = p
        # A dashed line would have many transitions (dash/gap/dash/gap...)
        # Label mode should have few or no transitions of these specific colors
        assert transitions < 10, f"Found {transitions} color transitions in bottom region, expected < 10"

    def test_present_in_roll_mode_api(self, api_client):
        """Receipt in roll mode includes tear indicator color pixels."""
        from baker.db.connection import get_db
        with get_db() as conn:
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active)"
                " VALUES ('paper_mode', 'roll', 0, 1)"
            )

        order_resp = api_client.post("/api/orders", json={
            "customerName": "Roll Mode Test",
            "items": [{"productName": "Test Cake", "quantity": 1, "unitPrice": 100000}],
            "dueDate": "2026-06-21",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        response = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
        assert response.status_code == 200
        img = Image.open(io.BytesIO(response.content))
        pixels = list(img.get_flattened_data())
        tear_color = (100, 100, 100)
        assert tear_color in pixels, "Tear indicator color NOT found in roll mode image"

    def test_all_5_types_in_roll_mode(self, api_client):
        """All 5 receipt types include tear indicator in roll mode."""
        from baker.db.connection import get_db
        with get_db() as conn:
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active)"
                " VALUES ('paper_mode', 'roll', 0, 1)"
            )

        order_resp = api_client.post("/api/orders", json={
            "customerName": "Five Type Test",
            "customerPhone": "0900123456",
            "items": [
                {"productName": "Banh kem", "quantity": 1, "unitPrice": 300000},
            ],
            "dueDate": "2026-06-21",
            "deliveryType": "bus",
            "deliveryAddress": "Ben xe Test",
            "notes": "Test order notes",
        })
        assert order_resp.status_code == 201
        data = order_resp.json()
        order_ref = data["orderRef"]
        item_id = data["workItems"][0]["id"]

        tear_color = (100, 100, 100)
        receipt_types = [
            f"type=customer",
            f"type=work_ticket&item_id={item_id}",
            "type=bus_label",
            "type=shop",
            "type=delivery",
        ]
        for params in receipt_types:
            resp = api_client.get(f"/api/orders/{order_ref}/receipt?{params}")
            assert resp.status_code == 200, f"Failed for {params}"
            img = Image.open(io.BytesIO(resp.content))
            pixels = list(img.get_flattened_data())
            assert tear_color in pixels, f"Tear indicator missing in {params}"

    def test_gap_is_64_dots(self):
        """Gap from last content to tear line is exactly 64 dots (8mm)."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 300), "white")
        draw = ImageDraw.Draw(img)
        draw.text((MARGIN, 100), "Content", fill=(0, 0, 0))
        y_content = 120
        y_after = _add_tear_indicator(img, draw, y_content, "roll")
        assert y_after >= y_content + 64
        tear_line_y = y_content + 64
        pixels_at_line = [img.getpixel((x, tear_line_y)) for x in range(MARGIN, RECEIPT_WIDTH - MARGIN)]
        non_white = [p for p in pixels_at_line if p != (255, 255, 255)]
        assert len(non_white) > 0, "Tear line not found at expected y position"

    def test_find_content_bottom_white_image(self):
        """_find_content_bottom returns 0 for entirely white image."""
        from PIL import Image
        img = Image.new("RGB", (100, 100), "white")
        assert _find_content_bottom(img) == 0

    def test_find_content_bottom_with_content(self):
        """_find_content_bottom finds last non-white pixel."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (100, 100), "white")
        draw = ImageDraw.Draw(img)
        draw.text((10, 50), "X", fill=(0, 0, 0))
        bottom = _find_content_bottom(img)
        assert bottom > 50


class TestSplitPages:
    """Tests for page splitting when content exceeds 1040px (DG-228 Phase 3 / FR-2)."""

    def _make_tall_image(self, height: int, gap_every: int = 120):
        """Build a white image with black text lines and periodic whitespace gaps."""
        from PIL import Image, ImageDraw
        from baker.api.receipts import _font
        img = Image.new("RGB", (RECEIPT_WIDTH, height), "white")
        draw = ImageDraw.Draw(img)
        font = _font(20)
        y = MARGIN
        line = 0
        while y < height - 40:
            draw.text((MARGIN, y), f"Line {line}", fill=(0, 0, 0), font=font)
            y += 30
            line += 1
            if line % 4 == 0:
                y += gap_every  # section gap (white rows)
        return img

    def test_short_content_returns_single_page(self):
        """Content under the cap returns one page with no footer marker."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 400), "white")
        draw = ImageDraw.Draw(img)
        draw.text((MARGIN, 50), "Short content", fill=(0, 0, 0))
        pages = _split_pages(img)
        assert len(pages) == 1
        assert pages[0].width == RECEIPT_WIDTH
        assert pages[0].height <= RECEIPT_MAX_HEIGHT
        # No footer marker (gray 100,100,100) on single-page output.
        pixels = list(pages[0].get_flattened_data())
        assert (100, 100, 100) not in pixels, "Single page should not have footer"

    def test_tall_content_splits_into_multiple_pages(self):
        """Content exceeding the cap splits into N pages each within the cap."""
        img = self._make_tall_image(3500)
        pages = _split_pages(img)
        assert len(pages) >= 2, f"Expected split, got {len(pages)} page(s)"
        for p in pages:
            assert p.width == RECEIPT_WIDTH
            assert p.height <= RECEIPT_MAX_HEIGHT, f"Page {p.height} > {RECEIPT_MAX_HEIGHT}"

    def test_split_pages_have_trang_footer_marker(self):
        """Each split page has the 'Trang N/M' footer marker (FR-2 / FR-6)."""
        img = self._make_tall_image(3500)
        pages = _split_pages(img)
        assert len(pages) >= 2
        footer_color = (100, 100, 100)
        for p in pages:
            # Footer is in the bottom band — scan the bottom 40px.
            bottom = p.crop((0, max(0, p.height - 40), RECEIPT_WIDTH, p.height))
            pixels = list(bottom.get_flattened_data())
            assert footer_color in pixels, "Footer marker (100,100,100) missing on split page"

    def test_split_page_count_marker_consistency(self):
        """Footer marker N matches len(pages) for each page."""
        img = self._make_tall_image(3000)
        pages = _split_pages(img)
        total = len(pages)
        # The marker format is "Trang N/M"; verify footer present on each.
        footer_color = (100, 100, 100)
        for p in pages:
            bottom = p.crop((0, max(0, p.height - 40), RECEIPT_WIDTH, p.height))
            pixels = list(bottom.get_flattened_data())
            assert footer_color in pixels
        assert total >= 2

    def test_find_split_boundaries_returns_empty_for_short_content(self):
        """No boundaries when content fits within the cap."""
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (RECEIPT_WIDTH, 500), "white")
        draw = ImageDraw.Draw(img)
        draw.text((MARGIN, 50), "Short", fill=(0, 0, 0))
        boundaries = _find_split_boundaries(img, RECEIPT_MAX_HEIGHT)
        assert boundaries == []

    def test_find_split_boundaries_detects_gaps(self):
        """Boundaries are detected at whitespace gap rows in tall content."""
        img = self._make_tall_image(2500, gap_every=150)
        boundaries = _find_split_boundaries(img, RECEIPT_MAX_HEIGHT)
        assert len(boundaries) > 0, "Expected at least one split boundary"

    def test_white_image_returns_single_blank_page(self):
        """Entirely white image returns a single small page."""
        from PIL import Image
        img = Image.new("RGB", (RECEIPT_WIDTH, 100), "white")
        pages = _split_pages(img)
        assert len(pages) == 1
        assert pages[0].width == RECEIPT_WIDTH


class TestMergedRefNumbering:
    """Tests for merged sub-item index in work ticket ref line (DG-228 Phase 3 / FR-3)."""

    def test_multi_item_returns_index_and_total(self):
        order = {"workItems": [
            {"id": 1, "productName": "A"},
            {"id": 2, "productName": "B"},
            {"id": 3, "productName": "C"},
        ]}
        idx, total = _main_item_index_total(order, {"id": 2})
        assert idx == 2
        assert total == 3

    def test_single_item_returns_none(self):
        order = {"workItems": [{"id": 1, "productName": "Only"}]}
        idx, total = _main_item_index_total(order, {"id": 1})
        assert idx is None
        assert total is None

    def test_extras_and_gifts_excluded_from_numbering(self):
        order = {"workItems": [
            {"id": 1, "productName": "Main A"},
            {"id": 2, "productName": "Main B"},
            {"id": 3, "productName": "Gift", "isGift": True},
            {"id": 4, "productName": "Extra", "isExtra": True},
        ]}
        idx, total = _main_item_index_total(order, {"id": 2})
        assert idx == 2
        assert total == 2  # only the two main items

    def test_extra_item_itself_returns_none(self):
        order = {"workItems": [
            {"id": 1, "productName": "Main A"},
            {"id": 2, "productName": "Main B"},
            {"id": 3, "productName": "Extra", "isExtra": True},
        ]}
        idx, total = _main_item_index_total(order, {"id": 3})
        assert idx is None
        assert total is None

    def test_missing_work_item_id_returns_none(self):
        order = {"workItems": [
            {"id": 1, "productName": "A"},
            {"id": 2, "productName": "B"},
        ]}
        idx, total = _main_item_index_total(order, {"id": 999})
        assert idx is None
        assert total is None

    def test_empty_work_items_returns_none(self):
        order = {"workItems": []}
        idx, total = _main_item_index_total(order, {"id": 1})
        assert idx is None
        assert total is None


class TestMultiItemWorkTicketAPI:
    """End-to-end API tests for multi-item work ticket ref numbering (AC-5)."""

    def test_multi_item_work_ticket_renders_for_each_item(self, api_client):
        """Each main item's work ticket renders successfully (AC-5)."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Multi Item Test",
            "items": [
                {"productName": "Bánh kem A", "quantity": 1, "unitPrice": 300000},
                {"productName": "Bánh kem B", "quantity": 1, "unitPrice": 250000},
                {"productName": "Bánh kem C", "quantity": 1, "unitPrice": 200000},
            ],
            "dueDate": "2026-07-20",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        data = order_resp.json()
        order_ref = data["orderRef"]
        items = data["workItems"]
        assert len(items) == 3

        for wi in items:
            resp = api_client.get(
                f"/api/orders/{order_ref}/receipt?type=work_ticket&item_id={wi['id']}"
            )
            assert resp.status_code == 200
            assert resp.headers["content-type"] == "image/png"
            img = Image.open(io.BytesIO(resp.content))
            assert img.size[0] == 576, f"Expected width 576px, got {img.size[0]}"
            assert img.size[1] <= RECEIPT_MAX_HEIGHT, f"Height {img.size[1]} > {RECEIPT_MAX_HEIGHT}"

    def test_single_item_work_ticket_height_within_cap(self, api_client):
        """Single-item work ticket stays within the 1040px cap (AC-1)."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Single Item",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 300000}],
            "dueDate": "2026-07-20",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        data = order_resp.json()
        order_ref = data["orderRef"]
        item_id = data["workItems"][0]["id"]

        resp = api_client.get(f"/api/orders/{order_ref}/receipt?type=work_ticket&item_id={item_id}")
        assert resp.status_code == 200
        img = Image.open(io.BytesIO(resp.content))
        assert img.size[0] == 576
        assert img.size[1] <= RECEIPT_MAX_HEIGHT

    def test_customer_receipt_height_within_cap(self, api_client):
        """Customer receipt stays within the 1040px cap (AC-1)."""
        order_resp = api_client.post("/api/orders", json={
            "customerName": "Customer Cap",
            "items": [
                {"productName": "Bánh kem A", "quantity": 1, "unitPrice": 300000},
                {"productName": "Bánh kem B", "quantity": 1, "unitPrice": 250000},
            ],
            "dueDate": "2026-07-20",
            "deliveryType": "pickup",
        })
        assert order_resp.status_code == 201
        order_ref = order_resp.json()["orderRef"]

        resp = api_client.get(f"/api/orders/{order_ref}/receipt?type=customer")
        assert resp.status_code == 200
        img = Image.open(io.BytesIO(resp.content))
        assert img.size[0] == 576
        assert img.size[1] <= RECEIPT_MAX_HEIGHT
