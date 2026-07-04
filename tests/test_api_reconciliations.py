from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS
from baker.api.inventory_fifo import create_lot_with_items


def _mark_product_display(conn, product_id: int, value: str = "true"):
    conn.execute(
        """INSERT INTO product_attribute_values (product_id, attribute_type, value)
           VALUES (?, 'trung_bay', ?)
           ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
        (product_id, value),
    )


def _set_stock(conn, product_id: int, quantity: int):
    conn.execute(
        "DELETE FROM inventory_items WHERE lot_id IN (SELECT id FROM stock_lots WHERE product_id = ?)",
        (product_id,),
    )
    conn.execute("DELETE FROM stock_lots WHERE product_id = ?", (product_id,))
    if quantity > 0:
        create_lot_with_items(conn, product_id, None, quantity)


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
            """SELECT COUNT(*) AS qty
               FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = ? AND ii.status = 'available'""",
            (1,),
        ).fetchone()
        assert stock["qty"] == 7

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


def test_submit_stale_display_product_names_product(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "false")
        product = conn.execute(
            "SELECT name FROM products WHERE id = ?",
            (1,),
        ).fetchone()
        product_name = product["name"]

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "expected_qty": 0,
                    "counted_qty": 0,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )

    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert "không còn trong danh sách trưng bày" in detail
    assert product_name in detail
    assert "ID 1" in detail


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


def test_draft_includes_migrated_accessories_when_eligible(api_client):
    with get_db() as conn:
        MIGRATIONS[38]["callable"](conn)
        accessory = conn.execute(
            "SELECT id FROM products WHERE category = 'phu_kien' AND name = 'Nến'"
        ).fetchone()
        assert accessory is not None
        _set_stock(conn, accessory["id"], 3)

    resp = api_client.get("/api/reconciliations/draft")
    assert resp.status_code == 200
    products = resp.json()["products"]
    accessory_row = next(p for p in products if p["product_id"] == accessory["id"])
    assert accessory_row["category"] == "phu_kien"
    assert accessory_row["expected_qty"] == 3


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


def test_submit_accepts_grouped_sale_rows_and_persists_row_details(api_client):
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
                    "expected_qty": 8,
                    "counted_qty": 5,
                    "waste_qty": 0,
                    "sale_rows": [
                        {"quantity": 1, "unit_price": 12000, "payment_method": "cash"},
                        {"quantity": 2, "unit_price": 15000, "payment_method": "transfer"},
                    ],
                }
            ],
        },
    )
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        line = conn.execute("SELECT * FROM reconciliation_lines").fetchone()
        assert line is not None
        assert line["sale_qty"] == 3

        orders = conn.execute("SELECT order_ref, total_price FROM orders ORDER BY id").fetchall()
        assert len(orders) == 2

        payments = conn.execute(
            "SELECT method, amount FROM payment_transactions ORDER BY id"
        ).fetchall()
        assert len(payments) == 2
        assert payments[0]["method"] == "cash"
        assert payments[0]["amount"] == 12000
        assert payments[1]["method"] == "transfer"
        assert payments[1]["amount"] == 30000

        sale_rows = conn.execute(
            "SELECT quantity, unit_price, payment_method, linked_order_ref, linked_payment_ref "
            "FROM reconciliation_sale_rows ORDER BY id"
        ).fetchall()
        assert len(sale_rows) == 2
        assert sale_rows[0]["quantity"] == 1
        assert sale_rows[0]["unit_price"] == 12000
        assert sale_rows[0]["payment_method"] == "cash"
        assert sale_rows[0]["linked_order_ref"] == orders[0]["order_ref"]
        assert sale_rows[0]["linked_payment_ref"]
        assert sale_rows[1]["quantity"] == 2
        assert sale_rows[1]["unit_price"] == 15000
        assert sale_rows[1]["payment_method"] == "transfer"
        assert sale_rows[1]["linked_order_ref"] == orders[1]["order_ref"]
        assert sale_rows[1]["linked_payment_ref"]

    history_resp = api_client.get(f"/api/reconciliations/history/{session_id}")
    assert history_resp.status_code == 200
    line = history_resp.json()["lines"][0]
    assert len(line["sale_rows"]) == 2
    row1 = line["sale_rows"][0]
    row2 = line["sale_rows"][1]
    assert row1["quantity"] == 1
    assert row1["unit_price"] == 12000
    assert row1["payment_method"] == "cash"
    assert row1["linked_order_ref"]
    assert row1["linked_payment_ref"]
    assert row1["is_legacy"] is False
    assert row2["quantity"] == 2
    assert row2["unit_price"] == 15000
    assert row2["payment_method"] == "transfer"
    assert row2["linked_order_ref"]
    assert row2["linked_payment_ref"]
    assert row2["is_legacy"] is False


def test_submit_grouped_rows_rejects_invalid_rows_with_zero_partial_writes(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 8)

    invalid_cases = [
        (
            {
                "staff_name": "An",
                "lines": [
                    {
                        "product_id": 1,
                        "expected_qty": 8,
                        "counted_qty": 5,
                        "waste_qty": 0,
                        "sale_rows": [{"quantity": -1, "unit_price": 12000, "payment_method": "cash"}],
                    }
                ],
            },
            "số lượng",
        ),
        (
            {
                "staff_name": "An",
                "lines": [
                    {
                        "product_id": 1,
                        "expected_qty": 8,
                        "counted_qty": 5,
                        "waste_qty": 0,
                        "sale_rows": [{"quantity": 1, "unit_price": 0, "payment_method": "cash"}],
                    }
                ],
            },
            "đơn giá",
        ),
        (
            {
                "staff_name": "An",
                "lines": [
                    {
                        "product_id": 1,
                        "expected_qty": 8,
                        "counted_qty": 5,
                        "waste_qty": 0,
                        "sale_rows": [{"quantity": 1, "unit_price": 12000, "payment_method": ""}],
                    }
                ],
            },
            "phương thức thanh toán",
        ),
    ]

    for payload, expected_error in invalid_cases:
        resp = api_client.post("/api/reconciliations/submit", json=payload)
        assert resp.status_code == 422
        assert expected_error in resp.json()["detail"]

        with get_db() as conn:
            assert conn.execute("SELECT COUNT(*) FROM reconciliation_sessions").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM reconciliation_lines").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM reconciliation_sale_rows").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM payment_transactions").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM stock_movements").fetchone()[0] == 0
            assert conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] == 0


def test_history_detail_exposes_legacy_sale_row_adapter(api_client):
    with get_db() as conn:
        session_id = conn.execute(
            """INSERT INTO reconciliation_sessions
               (reconciliation_date, staff_name, payment_method, linked_order_ref, linked_payment_ref)
               VALUES (date('now'), 'An', 'cash', 'ORD-LEGACY', '9')"""
        ).lastrowid
        conn.execute(
            """INSERT INTO reconciliation_lines
               (session_id, product_id, expected_qty, counted_qty, sale_qty, waste_qty, manual_unit_price)
               VALUES (?, 1, 10, 8, 2, 0, 13000)""",
            (session_id,),
        )

    resp = api_client.get(f"/api/reconciliations/history/{session_id}")
    assert resp.status_code == 200
    detail = resp.json()
    line = detail["lines"][0]
    assert len(line["sale_rows"]) == 1
    sale_row = line["sale_rows"][0]
    assert sale_row["is_legacy"] is True
    assert sale_row["quantity"] == 2
    assert sale_row["unit_price"] == 13000
    assert sale_row["payment_method"] == "cash"
    assert sale_row["linked_order_ref"] == "ORD-LEGACY"
    assert sale_row["linked_payment_ref"] == "9"


def test_draft_returns_per_chip_expected_rows(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        small_chip = conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, ?, ?, ?)",
            (1, "S", 12000, 1),
        ).lastrowid
        large_chip = conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, ?, ?, ?)",
            (1, "L", 18000, 2),
        ).lastrowid
        create_lot_with_items(conn, 1, small_chip, 3)
        create_lot_with_items(conn, 1, large_chip, 2)

    resp = api_client.get("/api/reconciliations/draft")
    assert resp.status_code == 200
    products = resp.json()["products"]
    product = next(p for p in products if p["product_id"] == 1)
    assert product["expected_qty"] == 5
    options = {(row["price_chip_id"], row["expected_qty"]) for row in product["options"]}
    assert (small_chip, 3) in options
    assert (large_chip, 2) in options


def test_submit_per_chip_lines_and_history(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        chip_id = conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, ?, ?, ?)",
            (1, "S", 12000, 1),
        ).lastrowid
        create_lot_with_items(conn, 1, chip_id, 5)

    payload = {
        "staff_name": "An",
        "payment_method": "cash",
        "waste_reason": "Bị hỏng",
        "lines": [
            {
                "product_id": 1,
                "price_chip_id": chip_id,
                "expected_qty": 5,
                "counted_qty": 2,
                "sale_qty": 2,
                "waste_qty": 1,
                "manual_unit_price": 12000,
            }
        ],
    }
    resp = api_client.post("/api/reconciliations/submit", json=payload)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        line = conn.execute("SELECT * FROM reconciliation_lines").fetchone()
        assert line is not None
        assert line["price_chip_id"] == chip_id

        waste = conn.execute(
            "SELECT * FROM stock_movements WHERE movement_type = 'waste' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert waste is not None
        assert waste["price_chip_id"] == chip_id

        option_qty = conn.execute(
            """SELECT COUNT(*) AS qty
               FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = ? AND sl.price_chip_id = ? AND ii.status = 'available'""",
            (1, chip_id),
        ).fetchone()["qty"]
        assert option_qty == 2

    history = api_client.get(f"/api/reconciliations/history/{session_id}")
    assert history.status_code == 200
    hist_line = history.json()["lines"][0]
    assert hist_line["price_chip_id"] == chip_id


def test_submit_prefers_explicit_chip_when_chip_price_matches_base(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 0)
        conn.execute("UPDATE products SET base_price = ? WHERE id = ?", (130000, 1))
        chip_id = conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, ?, ?, ?)",
            (1, "130", 130000, 1),
        ).lastrowid
        create_lot_with_items(conn, 1, chip_id, 4)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "normalized_price": 130000,
                    "price_chip_id": chip_id,
                    "expected_qty": 4,
                    "counted_qty": 4,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )

    assert resp.status_code == 201
    with get_db() as conn:
        line = conn.execute("SELECT * FROM reconciliation_lines").fetchone()
        assert line["price_chip_id"] == chip_id


def test_submit_returns_409_when_any_chip_expected_is_stale(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        chip_id = conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, ?, ?, ?)",
            (1, "S", 12000, 1),
        ).lastrowid
        create_lot_with_items(conn, 1, chip_id, 4)

    resp = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 1,
                    "price_chip_id": chip_id,
                    "expected_qty": 3,
                    "counted_qty": 3,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )
    assert resp.status_code == 409


def test_submit_no_chip_product_still_works_with_base_row(api_client):
    with get_db() as conn:
        _mark_product_display(conn, 2, "true")
        _set_stock(conn, 2, 3)

    draft = api_client.get("/api/reconciliations/draft")
    assert draft.status_code == 200
    product = next(p for p in draft.json()["products"] if p["product_id"] == 2)
    assert len(product["options"]) == 1
    assert product["options"][0]["price_chip_id"] is None
    assert product["options"][0]["expected_qty"] == 3

    submit = api_client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": 2,
                    "price_chip_id": None,
                    "expected_qty": 3,
                    "counted_qty": 2,
                    "sale_qty": 1,
                    "waste_qty": 0,
                    "manual_unit_price": 10000,
                }
            ],
            "payment_method": "cash",
        },
    )
    assert submit.status_code == 201


def test_submit_waste_creates_cogs_journal_entry(api_client):
    """AC5: reconciliation waste line auto-generates a waste_cogs journal
    entry (debit 5900, credit 1300) using cost_history → baseline fallback."""
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

    with get_db() as conn:
        waste_movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' "
            "AND reference_id LIKE 'reconciliation:%' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        assert waste_movement is not None
        entries = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type = 'waste_cogs' "
            "AND source_id = ? ORDER BY id",
            (waste_movement["id"],),
        ).fetchall()
        assert len(entries) == 1

        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
            (entries[0]["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if l["debit"] > 0)
        credit_line = next(l for l in lines if l["credit"] > 0)
        cogs_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (debit_line["account_id"],)
        ).fetchone()
        inv_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()
        assert cogs_acc["code"] == "5900"
        assert inv_acc["code"] == "1300"
        # Product 1 base_price=10000 → baseline 30% = 3000 × 1 = 3000
        assert debit_line["debit"] == 3000.0
        assert credit_line["credit"] == 3000.0


def test_submit_waste_cogs_uses_cost_history_when_present(api_client):
    """AC5: reconciliation waste with explicit cost_history row uses that
    cost instead of baseline."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 22000, "2020-01-01T00:00:00Z"),
        )

    payload = {
        "staff_name": "An",
        "payment_method": "cash",
        "waste_reason": "Hết hạn",
        "lines": [
            {
                "product_id": 1,
                "expected_qty": 5,
                "counted_qty": 3,
                "sale_qty": 1,
                "waste_qty": 1,
                "manual_unit_price": 15000,
            }
        ],
    }

    resp = api_client.post("/api/reconciliations/submit", json=payload)
    assert resp.status_code == 201

    with get_db() as conn:
        waste_movement = conn.execute(
            "SELECT id FROM stock_movements WHERE movement_type = 'waste' "
            "AND reference_id LIKE 'reconciliation:%' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        entries = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type = 'waste_cogs' AND source_id = ?",
            (waste_movement["id"],),
        ).fetchall()
        assert len(entries) == 1
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ?",
            (entries[0]["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if l["debit"] > 0)
        # cost_history cost 22000 × qty 1 = 22000
        assert debit_line["debit"] == 22000.0


def test_submit_no_waste_creates_no_cogs_entry(api_client):
    """AC5 negative: reconciliation with no waste lines produces no
    waste_cogs journal entry."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    payload = {
        "staff_name": "An",
        "payment_method": "cash",
        "lines": [
            {
                "product_id": 1,
                "expected_qty": 5,
                "counted_qty": 4,
                "sale_qty": 1,
                "waste_qty": 0,
                "manual_unit_price": 15000,
            }
        ],
    }

    resp = api_client.post("/api/reconciliations/submit", json=payload)
    assert resp.status_code == 201

    with get_db() as conn:
        count = conn.execute(
            "SELECT COUNT(*) AS c FROM journal_entries WHERE source_type = 'waste_cogs'"
        ).fetchone()
        assert count["c"] == 0


def test_submit_reconciliation_survives_waste_cogs_sync_failure(api_client, monkeypatch):
    """Regression for review finding M-1: a failure inside _sync_waste_cogs_journal
    must not break reconciliation submission. The sync call is wrapped in
    try/except so accounting failures are logged but never block the primary
    business operation (matching the defensive pattern at all other journal
    sync call sites).
    """
    from baker.services import journal_sync

    def _boom(conn, product_id, movement_id, quantity):
        raise RuntimeError("simulated accounting failure")

    monkeypatch.setattr(journal_sync, "_sync_waste_cogs_journal", _boom)

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
    # Reconciliation must succeed even though waste COGS sync raised.
    assert resp.status_code == 201


# ─── Timestamp format (DG-202 TC-7) ──────────────────────────────────────────


def test_reconciliation_session_created_at_is_z_suffixed(api_client):
    """TC-7: reconciliation_sessions.created_at is Z-suffixed UTC."""
    from datetime import datetime

    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    payload = {
        "staff_name": "TC-7",
        "payment_method": "cash",
        "waste_reason": "",
        "lines": [
            {
                "product_id": 1,
                "expected_qty": 5,
                "counted_qty": 5,
                "sale_qty": 0,
                "waste_qty": 0,
                "manual_unit_price": 12000,
            }
        ],
    }
    resp = api_client.post("/api/reconciliations/submit", json=payload)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    # Verify via the history list endpoint.
    history = api_client.get("/api/reconciliations/history")
    assert history.status_code == 200
    sessions = history.json()["sessions"]
    session = next(s for s in sessions if s["id"] == session_id)
    created_at = session["created_at"]
    assert created_at is not None
    assert created_at.endswith("Z"), f"created_at not Z-suffixed: {created_at}"
    assert "+" not in created_at
    datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ")

    # Also verify via the detail endpoint.
    detail = api_client.get(f"/api/reconciliations/history/{session_id}")
    assert detail.status_code == 200
    assert detail.json()["created_at"] == created_at
    assert detail.json()["created_at"].endswith("Z")


# ---------------------------------------------------------------------------
# DG-200 Phase 3 — Reconciliation Surplus Inflow (AC-3, AC-4, AC-5, AC-7)
# ---------------------------------------------------------------------------


def _set_negative_balance(conn, product_id: int, chip_id, qty: int) -> None:
    """Seed a negative_balance row directly for surplus-netting tests."""
    conn.execute(
        """INSERT INTO negative_balance (product_id, price_chip_id, qty, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)
           ON CONFLICT(product_id, price_chip_id) DO UPDATE
           SET qty = excluded.qty, updated_at = excluded.updated_at""",
        (product_id, chip_id, qty, "2026-07-05T00:00:00Z", "2026-07-05T00:00:00Z"),
    )


def _available_qty(conn, product_id: int, chip_id) -> int:
    row = conn.execute(
        """SELECT COUNT(*) AS c FROM inventory_items ii
           JOIN stock_lots sl ON sl.id = ii.lot_id
           WHERE sl.product_id = ? AND sl.price_chip_id IS NOT DISTINCT FROM ?
             AND ii.status = 'available'""",
        (product_id, chip_id),
    ).fetchone()
    return int(row["c"])


def _neg_qty(conn, product_id: int, chip_id) -> int:
    row = conn.execute(
        "SELECT qty FROM negative_balance WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?",
        (product_id, chip_id),
    ).fetchone()
    return int(row["qty"]) if row else 0


def _submit_surplus(client, product_id: int, expected_qty: int, counted_qty: int):
    return client.post(
        "/api/reconciliations/submit",
        json={
            "staff_name": "An",
            "lines": [
                {
                    "product_id": product_id,
                    "expected_qty": expected_qty,
                    "counted_qty": counted_qty,
                    "sale_qty": 0,
                    "waste_qty": 0,
                }
            ],
        },
    )


def test_surplus_offsets_negative_balance_no_restock_ac3(api_client):
    """AC-3: product with -5 negative balance, zero available, counted=2 →
    negative balance reduces to -3, no restock created."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 0)
        _set_negative_balance(conn, 1, None, 5)

    resp = _submit_surplus(api_client, 1, expected_qty=-5, counted_qty=2)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        assert _neg_qty(conn, 1, None) == 3
        assert _available_qty(conn, 1, None) == 0
        restock = conn.execute(
            """SELECT COUNT(*) AS c FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?""",
            (f"reconciliation:{session_id}",),
        ).fetchone()["c"]
        assert restock == 0


def test_surplus_clears_negative_then_restocks_ac4(api_client):
    """AC-4: product with -3 negative balance, zero available, counted=8 →
    negative cleared to 0, 5 items restocked as restock movement."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 0)
        _set_negative_balance(conn, 1, None, 3)

    resp = _submit_surplus(api_client, 1, expected_qty=-3, counted_qty=8)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        assert _neg_qty(conn, 1, None) == 0
        assert _available_qty(conn, 1, None) == 5
        restock_row = conn.execute(
            """SELECT id, quantity, lot_id FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (f"reconciliation:{session_id}",),
        ).fetchone()
        assert restock_row is not None
        assert restock_row["quantity"] == 5
        assert restock_row["lot_id"] is not None


def test_surplus_no_negative_creates_restock_ac5(api_client):
    """AC-5: product with 10 available (no negative), counted=15 → 5 items
    restocked, stock shows 15."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 10)

    resp = _submit_surplus(api_client, 1, expected_qty=10, counted_qty=15)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        assert _neg_qty(conn, 1, None) == 0
        assert _available_qty(conn, 1, None) == 15
        restock_row = conn.execute(
            """SELECT id, quantity FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (f"reconciliation:{session_id}",),
        ).fetchone()
        assert restock_row is not None
        assert restock_row["quantity"] == 5


def test_surplus_restock_logs_event_and_movement_ac7(api_client):
    """AC-7: reconciliation surplus inflow logs a stock_movement with type
    'restock', correct reference_id, qty=+S, and an Event is created."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 4)

    resp = _submit_surplus(api_client, 1, expected_qty=4, counted_qty=7)
    assert resp.status_code == 201
    session_id = resp.json()["id"]
    reference_id = f"reconciliation:{session_id}"

    with get_db() as conn:
        movement = conn.execute(
            """SELECT id, product_id, movement_type, quantity, reference_id, price_chip_id
               FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (reference_id,),
        ).fetchone()
        assert movement is not None
        assert movement["product_id"] == 1
        assert movement["movement_type"] == "restock"
        assert movement["quantity"] == 3
        assert movement["reference_id"] == reference_id

        event = conn.execute(
            """SELECT id, summary, type, data FROM events
               WHERE type = 'inventory' AND data LIKE ?""",
            (f'%"movement_type": "restock"%',),
        ).fetchone()
        assert event is not None
        assert event["type"] == "inventory"
        import json
        data = json.loads(event["data"])
        assert data["movement_type"] == "restock"
        assert data["quantity"] == 3
        assert data["reference_id"] == reference_id
        assert data["product_id"] == 1


def test_surplus_rejects_sale_or_waste_on_surplus_line(api_client):
    """Surplus line (counted > expected) must not carry sale_qty or waste_qty."""
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
                    "counted_qty": 8,
                    "sale_qty": 1,
                    "waste_qty": 0,
                    "manual_unit_price": 12000,
                }
            ],
        },
    )
    assert resp.status_code == 422
    assert "thừa" in resp.json()["detail"]

    with get_db() as conn:
        assert conn.execute("SELECT COUNT(*) FROM reconciliation_sessions").fetchone()[0] == 0


def test_draft_surfaces_net_position_when_negative_balance_exists(api_client):
    """FR-4: reconciliation draft expected_qty reflects net position
    (available - negative_balance)."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 3)
        _set_negative_balance(conn, 1, None, 5)

    resp = api_client.get("/api/reconciliations/draft")
    assert resp.status_code == 200
    product = next(p for p in resp.json()["products"] if p["product_id"] == 1)
    # net = 3 available - 5 negative = -2
    assert product["expected_qty"] == -2


# ---------------------------------------------------------------------------
# DG-200 Phase 4 — Accounting Entries (AC-9: Inventory debit for restock inflow)
# ---------------------------------------------------------------------------


def _restock_inflow_entries(conn, movement_id: int):
    return conn.execute(
        "SELECT * FROM journal_entries WHERE source_type = 'restock_inflow' "
        "AND source_id = ? ORDER BY id",
        (movement_id,),
    ).fetchall()


def _entry_lines(conn, entry_id: int):
    return conn.execute(
        "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
        (entry_id,),
    ).fetchall()


def test_surplus_restock_creates_inventory_debit_journal_ac9(api_client):
    """AC-9: reconciliation surplus inflow creates a journal entry debiting
    Inventory (1300) and crediting COGS (5900) for the restocked quantity
    (baseline cost)."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 10)

    resp = _submit_surplus(api_client, 1, expected_qty=10, counted_qty=15)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        restock_row = conn.execute(
            """SELECT id FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (f"reconciliation:{session_id}",),
        ).fetchone()
        assert restock_row is not None
        movement_id = restock_row["id"]

        entries = _restock_inflow_entries(conn, movement_id)
        assert len(entries) == 1

        lines = _entry_lines(conn, entries[0]["id"])
        debit_line = next(l for l in lines if l["debit"] > 0)
        credit_line = next(l for l in lines if l["credit"] > 0)
        inv_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (debit_line["account_id"],)
        ).fetchone()
        cogs_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()
        assert inv_acc["code"] == "1300"
        assert cogs_acc["code"] == "5900"
        # Product 1 base_price=10000 → baseline 30% = 3000 × 5 = 15000
        assert debit_line["debit"] == 15000.0
        assert credit_line["credit"] == 15000.0


def test_surplus_restock_inflow_uses_cost_history_ac9(api_client):
    """AC-9: cost_history overrides baseline when present."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 4)
        conn.execute(
            "INSERT INTO cost_history (product_id, cost, effective_from) VALUES (?, ?, ?)",
            (1, 25000, "2020-01-01T00:00:00Z"),
        )

    resp = _submit_surplus(api_client, 1, expected_qty=4, counted_qty=7)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        restock_row = conn.execute(
            """SELECT id FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (f"reconciliation:{session_id}",),
        ).fetchone()
        movement_id = restock_row["id"]
        entries = _restock_inflow_entries(conn, movement_id)
        assert len(entries) == 1
        lines = _entry_lines(conn, entries[0]["id"])
        debit_line = next(l for l in lines if l["debit"] > 0)
        # cost_history cost 25000 × qty 3 = 75000
        assert debit_line["debit"] == 75000.0


def test_surplus_restock_inflow_idempotent_ac9(api_client):
    """AC-9: re-invoking the sync helper directly must not duplicate entries."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 5)

    resp = _submit_surplus(api_client, 1, expected_qty=5, counted_qty=8)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        restock_row = conn.execute(
            """SELECT id FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (f"reconciliation:{session_id}",),
        ).fetchone()
        movement_id = restock_row["id"]

        from baker.services.journal_sync import _sync_restock_inflow_journal

        _sync_restock_inflow_journal(conn, 1, movement_id, 3)
        entries = _restock_inflow_entries(conn, movement_id)
        assert len(entries) == 1


def test_surplus_netting_only_no_inflow_journal_ac9(api_client):
    """AC-9: when surplus fully offsets a negative balance (no restock), no
    restock_inflow journal entry is created."""
    with get_db() as conn:
        _mark_product_display(conn, 1, "true")
        _set_stock(conn, 1, 0)
        _set_negative_balance(conn, 1, None, 5)

    resp = _submit_surplus(api_client, 1, expected_qty=-5, counted_qty=2)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        # No restock movement at all, so no restock_inflow journal entry.
        inflow_count = conn.execute(
            """SELECT COUNT(*) AS c FROM journal_entries je
               JOIN stock_movements sm ON sm.id = je.source_id
               WHERE je.source_type = 'restock_inflow'
                 AND sm.reference_id = ?""",
            (f"reconciliation:{session_id}",),
        ).fetchone()["c"]
        assert inflow_count == 0


def test_surplus_restock_inflow_no_cogs_when_cost_zero_ac9(api_client):
    """AC-9 edge: zero-cost product produces no restock_inflow journal entry."""
    prod = api_client.post(
        "/api/products",
        json={"name": "AC9 Zero", "category": "cake", "base_price": 0, "cost": 0},
    )
    assert prod.status_code == 201
    pid = prod.json()["id"]

    with get_db() as conn:
        _mark_product_display(conn, pid, "true")
        _set_stock(conn, pid, 3)

    resp = _submit_surplus(api_client, pid, expected_qty=3, counted_qty=6)
    assert resp.status_code == 201
    session_id = resp.json()["id"]

    with get_db() as conn:
        restock_row = conn.execute(
            """SELECT id FROM stock_movements
               WHERE movement_type = 'restock' AND reference_id = ?
               ORDER BY id DESC LIMIT 1""",
            (f"reconciliation:{session_id}",),
        ).fetchone()
        assert restock_row is not None
        entries = _restock_inflow_entries(conn, restock_row["id"])
        assert len(entries) == 0
