"""Tests for customer management API and order-customer linking (DG-182 Phase 1)."""

from baker.db.connection import get_db
from baker.db.schema import ensure_schema


# --- Helpers ---


def _create_customer(client, name="Nguyễn Văn A", phone="0901234567", **kwargs):
    payload = {"name": name, "phone": phone, **kwargs}
    resp = client.post("/api/customers", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


# --- Customer CRUD ---


def test_list_customers_empty(api_client):
    resp = api_client.get("/api/customers")
    assert resp.status_code == 200
    assert resp.json() == []


def test_create_customer_minimal(api_client):
    resp = api_client.post("/api/customers", json={"name": "Trần Thị B", "phone": ""})
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Trần Thị B"
    assert body["phone"] == ""
    assert body["id"] is not None
    assert body["sharedPhoneCustomers"] == []


def test_create_customer_rejects_empty_name(api_client):
    resp = api_client.post("/api/customers", json={"name": "  ", "phone": "0900"})
    assert resp.status_code == 422


def test_create_customer_strips_name_and_phone(api_client):
    resp = api_client.post("/api/customers", json={"name": "  Lê Văn C  ", "phone": "  0900  "})
    assert resp.status_code == 201
    assert resp.json()["name"] == "Lê Văn C"
    assert resp.json()["phone"] == "0900"


def test_list_customers_returns_created(api_client):
    _create_customer(api_client, name="Khách 1")
    _create_customer(api_client, name="Khách 2")
    resp = api_client.get("/api/customers")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 2
    # newest first (id DESC)
    assert rows[0]["name"] == "Khách 2"


def test_get_customer_by_id(api_client):
    created = _create_customer(api_client, name="Chi tiết khách")
    resp = api_client.get(f"/api/customers/{created['id']}")
    assert resp.status_code == 200
    assert resp.json()["name"] == "Chi tiết khách"


def test_get_customer_not_found(api_client):
    resp = api_client.get("/api/customers/99999")
    assert resp.status_code == 404


def test_update_customer_name_and_phone(api_client):
    created = _create_customer(api_client, name="Cũ", phone="0900")
    resp = api_client.patch(
        f"/api/customers/{created['id']}",
        json={"name": "Mới", "phone": "0911"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "Mới"
    assert body["phone"] == "0911"


def test_update_customer_no_changes_returns_current(api_client):
    created = _create_customer(api_client, name="Không đổi", phone="0900")
    resp = api_client.patch(f"/api/customers/{created['id']}", json={})
    assert resp.status_code == 200
    assert resp.json()["name"] == "Không đổi"


def test_update_customer_not_found(api_client):
    resp = api_client.patch("/api/customers/99999", json={"name": "X"})
    assert resp.status_code == 404


def test_delete_customer(api_client):
    created = _create_customer(api_client, name="Xóa tôi")
    resp = api_client.delete(f"/api/customers/{created['id']}")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True
    # Confirm gone
    get_resp = api_client.get(f"/api/customers/{created['id']}")
    assert get_resp.status_code == 404


def test_delete_customer_not_found(api_client):
    resp = api_client.delete("/api/customers/99999")
    assert resp.status_code == 404


# --- Search (FR1) ---


def test_search_by_name_partial(api_client):
    _create_customer(api_client, name="Nguyễn Văn An", phone="0901")
    _create_customer(api_client, name="Trần Thị Bình", phone="0902")
    _create_customer(api_client, name="Lê Văn An", phone="0903")
    resp = api_client.get("/api/customers?search=An")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 2
    names = {r["name"] for r in rows}
    assert "Nguyễn Văn An" in names
    assert "Lê Văn An" in names


def test_search_by_phone_partial(api_client):
    _create_customer(api_client, name="Khách A", phone="0901234567")
    _create_customer(api_client, name="Khách B", phone="0911222333")
    resp = api_client.get("/api/customers?search=0901")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Khách A"


def test_search_empty_string_returns_all(api_client):
    _create_customer(api_client, name="Khách X")
    resp = api_client.get("/api/customers?search=")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


# --- Phone sharing visibility (FR2a, AC6) ---


def test_create_customer_with_shared_phone_returns_others(api_client):
    _create_customer(api_client, name="Khách 1", phone="0900111222")
    resp = api_client.post(
        "/api/customers", json={"name": "Khách 2", "phone": "0900111222"}
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["name"] == "Khách 2"
    shared = body["sharedPhoneCustomers"]
    assert len(shared) == 1
    assert shared[0]["name"] == "Khách 1"


def test_create_customer_with_unique_phone_returns_empty_shared(api_client):
    resp = api_client.post(
        "/api/customers", json={"name": "Độc nhất", "phone": "0900999888"}
    )
    assert resp.status_code == 201
    assert resp.json()["sharedPhoneCustomers"] == []


def test_update_customer_phone_to_shared_returns_others(api_client):
    _create_customer(api_client, name="Cũ 1", phone="0900555444")
    created = _create_customer(api_client, name="Cũ 2", phone="0900")
    resp = api_client.patch(
        f"/api/customers/{created['id']}", json={"phone": "0900555444"}
    )
    assert resp.status_code == 200
    shared = resp.json()["sharedPhoneCustomers"]
    assert len(shared) == 1
    assert shared[0]["name"] == "Cũ 1"


def test_create_customer_empty_phone_no_shared_list(api_client):
    _create_customer(api_client, name="Không SĐT 1", phone="0900")
    resp = api_client.post(
        "/api/customers", json={"name": "Không SĐT 2", "phone": ""}
    )
    assert resp.status_code == 201
    assert resp.json()["sharedPhoneCustomers"] == []


# --- Customer order history (FR6) ---


def _create_order_with_customer(client, customer_id=None, customer_name="Khách lẻ", phone=""):
    payload = {
        "customerName": customer_name,
        "customerPhone": phone,
        "items": [{"productName": "Bánh mì", "quantity": 1, "unitPrice": 10000, "productId": "BMI-01"}],
        "dueDate": "2026-07-01",
    }
    if customer_id is not None:
        payload["customerId"] = customer_id
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_get_customer_orders_empty(api_client):
    created = _create_customer(api_client, name="Chưa có đơn")
    resp = api_client.get(f"/api/customers/{created['id']}/orders")
    assert resp.status_code == 200
    assert resp.json() == []


def test_get_customer_orders_returns_linked_orders(api_client):
    customer = _create_customer(api_client, name="Có đơn", phone="0900")
    order = _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"], phone=customer["phone"]
    )
    resp = api_client.get(f"/api/customers/{customer['id']}/orders")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert rows[0]["id"] == order["id"]
    assert rows[0]["customerId"] == customer["id"]


def test_get_customer_orders_not_found(api_client):
    resp = api_client.get("/api/customers/99999/orders")
    assert resp.status_code == 404


# --- Order customerId linking (FR8, AC7) ---


def test_order_create_accepts_customer_id(api_client):
    customer = _create_customer(api_client, name="Liên kết", phone="0900")
    order = _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    assert order["customerId"] == customer["id"]


def test_order_create_without_customer_id_defaults_null(api_client):
    """AC7 — walk-in flow: no customer record required, customerId null."""
    order = _create_order_with_customer(api_client, customer_name="Khách lẻ")
    assert order["customerId"] is None


def test_order_edit_updates_customer_id(api_client):
    customer = _create_customer(api_client, name="Gán sau", phone="0900")
    order = _create_order_with_customer(api_client, customer_name="Khách lẻ")
    assert order["customerId"] is None

    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": customer["id"]}
    )
    assert resp.status_code == 200
    assert resp.json()["customerId"] == customer["id"]


def test_order_edit_unlinks_customer_id_with_null(api_client):
    customer = _create_customer(api_client, name="Bỏ liên kết", phone="0900")
    order = _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    assert order["customerId"] == customer["id"]

    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": None}
    )
    assert resp.status_code == 200
    assert resp.json()["customerId"] is None


def test_order_to_api_dict_falls_back_to_customer_name_when_no_customer_id(api_client):
    """NFR3 — existing orders without customer_id still display name/phone."""
    order = _create_order_with_customer(
        api_client, customer_name="Khách vãng lai", phone="0900111"
    )
    assert order["customerId"] is None
    assert order["customerName"] == "Khách vãng lai"


# --- customerId existence validation (review-auto CQ-1) ---


def test_order_create_rejects_nonexistent_customer_id(api_client):
    """POST /api/orders with non-existent customerId returns 422."""
    payload = {
        "customerName": "Khách lẻ",
        "customerPhone": "",
        "customerId": 999999,
        "items": [{"productName": "Bánh mì", "quantity": 1, "unitPrice": 10000, "productId": "BMI-01"}],
        "dueDate": "2026-07-01",
    }
    resp = api_client.post("/api/orders", json=payload)
    assert resp.status_code == 422


def test_order_edit_rejects_nonexistent_customer_id(api_client):
    """PUT /api/orders/{ref} with non-existent customerId returns 422."""
    order = _create_order_with_customer(api_client, customer_name="Khách lẻ")
    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": 999999}
    )
    assert resp.status_code == 422


# --- Migration v56: auto-match existing orders by phone (FR9) ---


def test_migration_v56_auto_matches_orders_by_phone():
    with get_db() as conn:
        ensure_schema(conn)
        # Insert a customer with a phone
        conn.execute(
            "INSERT INTO customers (name, phone) VALUES (?, ?)",
            ("Khách auto", "0900777888"),
        )
        customer_id = conn.execute(
            "SELECT id FROM customers WHERE phone = '0900777888'"
        ).fetchone()["id"]
        # Insert an order with matching phone but no customer_id
        conn.execute(
            "INSERT INTO orders (order_ref, customer_name, customer_phone, items, total_price, status, due_date) "
            "VALUES ('ORD-AUTO-001', 'Khách auto', '0900777888', '[]', 50000, 'new', '2026-07-01')"
        )
        # Re-run the v56 callable to simulate auto-match (idempotent)
        from baker.db.schema import _migrate_v56_customers_and_order_link

        _migrate_v56_customers_and_order_link(conn)

        linked = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-AUTO-001'"
        ).fetchone()
        assert linked["customer_id"] == customer_id


def test_migration_v56_does_not_link_orders_without_phone():
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO customers (name, phone) VALUES ('Khách có SĐT', '0900')"
        )
        conn.execute(
            "INSERT INTO orders (order_ref, customer_name, customer_phone, items, total_price, status, due_date) "
            "VALUES ('ORD-NOPHONE-001', 'Khách lẻ', '', '[]', 30000, 'new', '2026-07-01')"
        )
        from baker.db.schema import _migrate_v56_customers_and_order_link

        _migrate_v56_customers_and_order_link(conn)

        linked = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref = 'ORD-NOPHONE-001'"
        ).fetchone()
        assert linked["customer_id"] is None


def test_migration_v56_creates_customers_table_with_index():
    with get_db() as conn:
        ensure_schema(conn)
        columns = {
            row["name"]: row
            for row in conn.execute("PRAGMA table_info(customers)").fetchall()
        }
        assert {"id", "name", "phone", "created_at", "updated_at"} <= set(columns)
        assert columns["name"]["notnull"] == 1
        # phone is NOT unique (NFR4)
        index_rows = conn.execute("PRAGMA index_list(customers)").fetchall()
        index_names = [r["name"] for r in index_rows]
        assert "idx_customers_name" in index_names
        assert "idx_customers_phone" in index_names

        # orders has customer_id column
        order_cols = {
            row["name"] for row in conn.execute("PRAGMA table_info(orders)").fetchall()
        }
        assert "customer_id" in order_cols


def test_migration_v56_schema_version_is_56():
    with get_db() as conn:
        ensure_schema(conn)
        version = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0]
        assert version == 58


def test_migration_v56_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        from baker.db.schema import _migrate_v56_customers_and_order_link

        _migrate_v56_customers_and_order_link(conn)
        _migrate_v56_customers_and_order_link(conn)
        # Still works — customers table exists, customer_id column exists
        columns = {
            row["name"] for row in conn.execute("PRAGMA table_info(orders)").fetchall()
        }
        assert "customer_id" in columns


# --- Phone not unique (NFR4) ---


def test_phone_is_not_unique_multiple_customers_same_phone(api_client):
    """NFR4 — multiple customers may share a phone; no UNIQUE constraint."""
    r1 = api_client.post("/api/customers", json={"name": "A", "phone": "0900555666"})
    r2 = api_client.post("/api/customers", json={"name": "B", "phone": "0900555666"})
    assert r1.status_code == 201
    assert r2.status_code == 201
    assert r1.json()["id"] != r2.json()["id"]


# --- Delete clears order links ---


def test_delete_customer_clears_order_links(api_client):
    customer = _create_customer(api_client, name="Sẽ xóa", phone="0900")
    _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    resp = api_client.delete(f"/api/customers/{customer['id']}")
    assert resp.status_code == 200
    assert resp.json()["linkedOrdersCleared"] == 1