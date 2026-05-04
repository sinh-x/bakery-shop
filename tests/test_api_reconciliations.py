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


def test_submit_valid_persists_session_and_lines(api_client):
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

        line = conn.execute("SELECT * FROM reconciliation_lines").fetchone()
        assert line is not None
        assert line["expected_qty"] == 9
        assert line["counted_qty"] == 7
        assert line["sale_qty"] == 1
        assert line["waste_qty"] == 1
        assert line["manual_unit_price"] == 15000


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
    assert "lý do hao hụt" in resp.json()["detail"]


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
