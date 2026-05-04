from baker.db.connection import get_db


def _mark_product_display(conn, product_id: int, value: str = "true"):
    conn.execute(
        """INSERT INTO product_attribute_values (product_id, attribute_type, value)
           VALUES (?, 'trung_bay', ?)
           ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
        (product_id, value),
    )


def _set_stock(conn, product_id: int, quantity: int):
    conn.execute(
        """INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)
           ON CONFLICT(product_id) DO UPDATE SET quantity = excluded.quantity""",
        (product_id, quantity),
    )


def test_draft_returns_active_trung_bay_products_with_price_chips(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _mark_product_display(conn, 2, "true")
        _mark_product_display(conn, 3, "false")
        _set_stock(conn, 1, 7)
        _set_stock(conn, 2, 3)
        conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, ?, ?, ?)",
            (1, "Lẻ", 12000, 1),
        )

    resp = api_client.get("/api/reconciliations/draft")
    assert resp.status_code == 200
    data = resp.json()
    assert "date" in data
    products = data["products"]
    ids = [p["product_id"] for p in products]
    assert 1 in ids
    assert 2 in ids
    assert 3 not in ids

    p1 = next(p for p in products if p["product_id"] == 1)
    assert p1["expected_qty"] == 7
    assert p1["price_chips"][0]["label"] == "Lẻ"
    assert p1["price_chips"][0]["price"] == 12000


def test_submit_valid_creates_order_payment_waste_and_links(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 9)

    payload = {
        "staff_name": "An",
        "payment_method": "cash",
        "waste_reason": "Bị hỏng",
        "lines": [
            {
                "product_id": 1,
                "expected_qty": 9,
                "counted_qty": 7,
                "sale_qty": 1,
                "waste_qty": 1,
                "manual_unit_price": 15000,
            }
        ],
    }

    resp = api_client.post("/api/reconciliations/submit", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["id"] > 0

    with get_db() as conn:
        session = conn.execute("SELECT * FROM reconciliation_sessions").fetchone()
        assert session is not None
        assert session["staff_name"] == "An"
        assert session["payment_method"] == "cash"
        assert session["linked_order_ref"]
        assert session["linked_payment_ref"]

        order = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ?",
            (session["linked_order_ref"],),
        ).fetchone()
        assert order is not None
        assert order["status"] == "delivered"

        order_item = conn.execute(
            "SELECT * FROM order_items WHERE order_id = ?",
            (order["id"],),
        ).fetchone()
        assert order_item is not None
        assert order_item["quantity"] == 1
        assert order_item["unit_price"] == 15000

        payment = conn.execute(
            "SELECT * FROM payment_transactions WHERE order_id = ?",
            (order["id"],),
        ).fetchone()
        assert payment is not None
        assert payment["method"] == "cash"
        assert payment["type"] == "payment"

        stock = conn.execute(
            "SELECT quantity FROM product_stock WHERE product_id = ?",
            (1,),
        ).fetchone()
        assert stock["quantity"] == 7

        sale_movement = conn.execute(
            "SELECT * FROM stock_movements WHERE movement_type = 'sale' AND reference_id = ?",
            (order["order_ref"],),
        ).fetchone()
        assert sale_movement is not None
        assert sale_movement["quantity"] == -1

        waste_movement = conn.execute(
            "SELECT * FROM stock_movements WHERE movement_type = 'waste' AND reference_id = ?",
            (f"reconciliation:{session['id']}",),
        ).fetchone()
        assert waste_movement is not None
        assert waste_movement["quantity"] == -1
        assert waste_movement["reason"] == "Bị hỏng"

        inventory_events = conn.execute(
            "SELECT COUNT(*) FROM events WHERE type = 'inventory'",
        ).fetchone()[0]
        assert inventory_events >= 2

        line = conn.execute("SELECT * FROM reconciliation_lines").fetchone()
        assert line is not None
        assert line["expected_qty"] == 9
        assert line["counted_qty"] == 7
        assert line["sale_qty"] == 1
        assert line["waste_qty"] == 1
        assert line["manual_unit_price"] == 15000
        assert line["linked_order_item_id"] == order_item["id"]
        assert line["linked_stock_movement_sale_id"] == sale_movement["id"]
        assert line["linked_stock_movement_waste_id"] == waste_movement["id"]


def test_submit_sale_only_creates_one_order_and_one_payment(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 6)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "transfer",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 6,
                    "counted_qty": 4,
                    "sale_qty": 2,
                    "waste_qty": 0,
                    "manual_unit_price": 12000,
                }
            ],
        },
    )
    assert resp.status_code == 201

    with get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM payment_transactions").fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM stock_movements WHERE movement_type = 'sale'").fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM stock_movements WHERE movement_type = 'waste'").fetchone()[0] == 0


def test_submit_stale_stock_creates_zero_side_effect_rows(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 8)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "cash",
            "waste_reason": "Bị hỏng",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 7,
                    "counted_qty": 5,
                    "sale_qty": 1,
                    "waste_qty": 1,
                    "manual_unit_price": 10000,
                }
            ],
        },
    )
    assert resp.status_code == 409

    with get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_sessions").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_lines").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM payment_transactions").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM stock_movements").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] == 0


def test_submit_invalid_split_no_partial_writes(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 10)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "cash",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 10,
                    "counted_qty": 7,
                    "sale_qty": 1,
                    "waste_qty": 1,
                    "manual_unit_price": 12000,
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "bán + hao hụt" in resp.json()["detail"]

    with get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_sessions").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_lines").fetchone()[0] == 0


def test_submit_negative_count_no_partial_writes(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 10)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 10,
                    "counted_qty": -1,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "không được âm" in resp.json()["detail"]

    with get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_sessions").fetchone()[0] == 0


def test_submit_requires_payment_method_for_sales(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 5,
                    "counted_qty": 4,
                    "sale_qty": 1,
                    "waste_qty": 0,
                    "manual_unit_price": 10000,
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "phương thức thanh toán" in resp.json()["detail"]


def test_submit_requires_manual_price_for_sale_line(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "cash",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 5,
                    "counted_qty": 4,
                    "sale_qty": 1,
                    "waste_qty": 0,
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "đơn giá nhập tay" in resp.json()["detail"]


def test_submit_requires_waste_reason(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 5,
                    "counted_qty": 4,
                    "sale_qty": 0,
                    "waste_qty": 1,
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "hao hụt" in resp.json()["detail"] and "lý do" in resp.json()["detail"]


def test_submit_per_line_waste_reason(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "cash",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 5,
                    "counted_qty": 4,
                    "sale_qty": 0,
                    "waste_qty": 1,
                    "waste_reason": "Bị rụng",
                }
            ],
        },
    )
    assert resp.status_code == 201

    with get_db() as conn:
        waste_movement = conn.execute(
            "SELECT * FROM stock_movements WHERE movement_type = 'waste' AND reference_id LIKE 'reconciliation:%'",
        ).fetchone()
        assert waste_movement is not None
        assert waste_movement["reason"] == "Bị rụng"


def test_submit_per_line_waste_reason_overrides_session_reason(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "cash",
            "waste_reason": "Session-level reason",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 5,
                    "counted_qty": 4,
                    "sale_qty": 0,
                    "waste_qty": 1,
                    "waste_reason": "Line-level reason",
                }
            ],
        },
    )
    assert resp.status_code == 201

    with get_db() as conn:
        waste_movement = conn.execute(
            "SELECT * FROM stock_movements WHERE movement_type = 'waste' AND reference_id LIKE 'reconciliation:%'",
        ).fetchone()
        assert waste_movement is not None
        assert waste_movement["reason"] == "Line-level reason"


def test_submit_waste_qty_over_missing_qty_rejects(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 5,
                    "counted_qty": 4,
                    "sale_qty": 0,
                    "waste_qty": 2,
                    "waste_reason": "Bị hỏng",
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "hao hụt vượt quá số thiếu" in resp.json()["detail"]
    assert "Nhập hàng" in resp.json()["detail"]


def test_submit_rejects_stale_stock_no_partial_writes(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 8)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 7,
                    "counted_qty": 7,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )
    assert resp.status_code == 409
    assert "vui lòng tải lại" in resp.json()["detail"]

    with get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_sessions").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_lines").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM payment_transactions").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM stock_movements").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] == 0


def test_history_detail_exposes_per_line_waste_reason(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 9)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "payment_method": "cash",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 9,
                    "counted_qty": 7,
                    "sale_qty": 1,
                    "waste_qty": 1,
                    "waste_reason": "Bị hỏng",
                    "manual_unit_price": 15000,
                }
            ],
        },
    )
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    hist_resp = api_client.get(f"/api/reconciliations/history/{session_id}")
    assert hist_resp.status_code == 200
    detail = hist_resp.json()

    assert len(detail["lines"]) == 1
    line = detail["lines"][0]
    assert line["waste_qty"] == 1
    assert line["waste_reason"] == "Bị hỏng"
