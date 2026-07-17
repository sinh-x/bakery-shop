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
    # Diacritic-insensitive: "Trần" → "tran" also matches "an"
    assert len(rows) == 3
    names = {r["name"] for r in rows}
    assert "Nguyễn Văn An" in names
    assert "Lê Văn An" in names
    assert "Trần Thị Bình" in names


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


def test_order_create_without_customer_id_links_to_walk_in(api_client):
    """DG-252 AC1 — walk-in flow: no explicit customer id links to the shared
    "Khách lẻ" record so the order always has a non-NULL customer_id."""
    from baker.api.orders import WALK_IN_SHARED_CUSTOMER_NAME

    order = _create_order_with_customer(api_client, customer_name=WALK_IN_SHARED_CUSTOMER_NAME)
    assert order["customerId"] is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM customers WHERE id = ?", (order["customerId"],)
        ).fetchone()
        assert row is not None
        assert row["name"].lower() == WALK_IN_SHARED_CUSTOMER_NAME.lower()


def test_order_edit_updates_customer_id(api_client):
    customer = _create_customer(api_client, name="Gán sau", phone="0900")
    order = _create_order_with_customer(api_client, customer_name="Khách vãng lai")
    assert order["customerId"] is not None

    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": customer["id"]}
    )
    assert resp.status_code == 200
    assert resp.json()["customerId"] == customer["id"]


def test_order_edit_null_customer_id_re_resolves_not_unlinks(api_client):
    """DG-252 FR3 — explicit ``customerId: null`` re-resolves via the
    resolve → auto-create → walk-in chain instead of leaving the order
    unlinked."""
    customer = _create_customer(api_client, name="Bỏ liên kết", phone="0900")
    order = _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    assert order["customerId"] == customer["id"]

    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": None}
    )
    assert resp.status_code == 200
    # No phone/name in patch → falls back to the row's stored name "Bỏ liên kết"
    # which has no phone, so a fresh customer is auto-created for that name.
    new_id = resp.json()["customerId"]
    assert new_id is not None
    assert new_id != customer["id"]


def test_order_to_api_dict_falls_back_to_customer_name_when_no_customer_id(api_client):
    """NFR3 — orders auto-linked to a customer still display the original
    name/phone the staff typed (now stored on the order itself, not via NULL)."""
    order = _create_order_with_customer(
        api_client, customer_name="Khách vãng lai", phone="0900111"
    )
    assert order["customerId"] is not None
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
        assert version >= 56


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


# --- Multi-phone support (DG-205 Phase 2) ---


def _create_customer_multi_phone(client, name, phones):
    payload = {"name": name, "phones": phones}
    resp = client.post("/api/customers", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_create_customer_with_phones_array_stores_all(api_client):
    """AC3 — POST with phones array stores all in customer_phones, first is primary."""
    body = _create_customer_multi_phone(
        api_client,
        name="Khách đa SĐT",
        phones=[
            {"phone": "0901111222", "isPrimary": True},
            {"phone": "0902222333", "isPrimary": False},
        ],
    )
    assert body["phone"] == "0901111222"
    phones = body["phones"]
    assert len(phones) == 2
    assert {"phone": "0901111222", "isPrimary": True} in phones
    assert {"phone": "0902222333", "isPrimary": False} in phones


def test_create_customer_phones_without_primary_rejected(api_client):
    resp = api_client.post(
        "/api/customers",
        json={"name": "X", "phones": [{"phone": "0900", "isPrimary": False}]},
    )
    assert resp.status_code == 422


def test_create_customer_legacy_phone_field_still_works(api_client):
    """Backward compat — legacy phone string still accepted and stored."""
    resp = api_client.post(
        "/api/customers", json={"name": "Cũ", "phone": "0912345678"}
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["phone"] == "0912345678"
    assert len(body["phones"]) == 1
    assert body["phones"][0] == {"phone": "0912345678", "isPrimary": True}


def test_create_customer_empty_phone_yields_empty_phones(api_client):
    resp = api_client.post("/api/customers", json={"name": "Không SĐT", "phone": ""})
    assert resp.status_code == 201
    assert resp.json()["phones"] == []


def test_get_customer_returns_phones_array(api_client):
    """AC5 — GET /api/customers/{id} includes phones array alongside legacy phone."""
    created = _create_customer_multi_phone(
        api_client,
        name="Chi tiết đa SĐT",
        phones=[
            {"phone": "0903333444", "isPrimary": True},
            {"phone": "0904444555", "isPrimary": False},
        ],
    )
    resp = api_client.get(f"/api/customers/{created['id']}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["phone"] == "0903333444"
    assert len(body["phones"]) == 2


def test_list_customers_includes_phones_array(api_client):
    _create_customer_multi_phone(
        api_client,
        name="Liệt kê",
        phones=[{"phone": "0905555666", "isPrimary": True}],
    )
    resp = api_client.get("/api/customers")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert len(rows[0]["phones"]) == 1
    assert rows[0]["phones"][0]["phone"] == "0905555666"


def test_update_customer_phones_replaces_all(api_client):
    """AC4 — PATCH with phones array replaces old phone rows."""
    created = _create_customer_multi_phone(
        api_client,
        name="Sửa đa SĐT",
        phones=[
            {"phone": "0907777888", "isPrimary": True},
            {"phone": "0908888999", "isPrimary": False},
        ],
    )
    resp = api_client.patch(
        f"/api/customers/{created['id']}",
        json={"phones": [{"phone": "0910000111", "isPrimary": True}]},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["phone"] == "0910000111"
    assert len(body["phones"]) == 1
    assert body["phones"][0] == {"phone": "0910000111", "isPrimary": True}


def test_update_customer_phones_without_primary_rejected(api_client):
    created = _create_customer(api_client, name="Sửa lỗi", phone="0900")
    resp = api_client.patch(
        f"/api/customers/{created['id']}",
        json={"phones": [{"phone": "0911", "isPrimary": False}]},
    )
    assert resp.status_code == 422


def test_update_customer_legacy_phone_field_still_works(api_client):
    created = _create_customer(api_client, name="Cũ", phone="0900")
    resp = api_client.patch(
        f"/api/customers/{created['id']}", json={"phone": "0911"}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["phone"] == "0911"
    assert len(body["phones"]) == 1
    assert body["phones"][0] == {"phone": "0911", "isPrimary": True}


def test_search_by_secondary_phone_in_customer_phones(api_client):
    """AC6 — search matches against customer_phones.phone, not just customers.phone."""
    _create_customer_multi_phone(
        api_client,
        name="Khách phụ",
        phones=[
            {"phone": "0901234567", "isPrimary": True},
            {"phone": "0912999888", "isPrimary": False},
        ],
    )
    resp = api_client.get("/api/customers?search=0912999")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Khách phụ"


def test_delete_customer_cascades_to_customer_phones(api_client):
    """FR9 — deleting customer removes all customer_phones rows."""
    created = _create_customer_multi_phone(
        api_client,
        name="Xóa đa SĐT",
        phones=[
            {"phone": "0922111333", "isPrimary": True},
            {"phone": "0922222444", "isPrimary": False},
        ],
    )
    with get_db() as conn:
        count = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (created["id"],),
        ).fetchone()[0]
        assert count == 2

    resp = api_client.delete(f"/api/customers/{created['id']}")
    assert resp.status_code == 200

    with get_db() as conn:
        count = conn.execute(
            "SELECT COUNT(*) FROM customer_phones WHERE customer_id = ?",
            (created["id"],),
        ).fetchone()[0]
        assert count == 0


def test_shared_phone_visibility_uses_customer_phones(api_client):
    """Shared phone banner should detect phones in customer_phones, not just customers.phone."""
    _create_customer_multi_phone(
        api_client,
        name="Khách A",
        phones=[{"phone": "0933000111", "isPrimary": True}],
    )
    resp = api_client.post(
        "/api/customers",
        json={
            "name": "Khách B",
            "phones": [{"phone": "0933000111", "isPrimary": True}],
        },
    )
    assert resp.status_code == 201
    shared = resp.json()["sharedPhoneCustomers"]
    assert len(shared) == 1
    assert shared[0]["name"] == "Khách A"


def test_primary_phone_synced_to_customers_phone_on_update(api_client):
    """NFR3 — customers.phone denormalized field stays in sync with primary phone."""
    created = _create_customer_multi_phone(
        api_client,
        name="Đồng bộ",
        phones=[{"phone": "0944000111", "isPrimary": True}],
    )
    api_client.patch(
        f"/api/customers/{created['id']}",
        json={
            "phones": [
                {"phone": "0944000222", "isPrimary": False},
                {"phone": "0944000333", "isPrimary": True},
            ]
        },
    )
    with get_db() as conn:
        row = conn.execute(
            "SELECT phone FROM customers WHERE id = ?", (created["id"],)
        ).fetchone()
        assert row["phone"] == "0944000333"


# --- Customer yearly summary (DG-206 Phase 1: FR6, FR7, AC5) ---


def _current_year():
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).year


def test_get_customer_includes_year_summary_zero_for_new_customer(api_client):
    """FR7/AC5 — new customer with no orders shows zeroed yearSummary."""
    created = _create_customer(api_client, name="Chưa có đơn", phone="0900")
    resp = api_client.get(f"/api/customers/{created['id']}")
    assert resp.status_code == 200
    ys = resp.json()["yearSummary"]
    assert ys["year"] == _current_year()
    assert ys["orderCount"] == 0
    assert ys["totalVolume"] == 0


def test_get_customer_year_summary_counts_orders_in_current_year(api_client):
    """FR6 — summary reflects order count + total volume for the current year."""
    customer = _create_customer(api_client, name="Có đơn", phone="0900")
    _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    resp = api_client.get(f"/api/customers/{customer['id']}")
    ys = resp.json()["yearSummary"]
    assert ys["year"] == _current_year()
    assert ys["orderCount"] == 2
    assert ys["totalVolume"] == 20000  # 2 × 10000


def test_order_create_updates_customer_year_summary(api_client):
    """FR6/NFR2 — POST /api/orders with customerId updates the summary row."""
    from baker.db.connection import get_db
    from baker.models.customer import load_year_summary

    customer = _create_customer(api_client, name="Tạo đơn", phone="0900")
    _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    with get_db() as conn:
        ys = load_year_summary(conn, customer["id"], _current_year())
    assert ys["orderCount"] == 1
    assert ys["totalVolume"] == 10000


def test_order_edit_relinks_summary_to_new_customer(api_client):
    """FR6 — editing customerId moves the order's volume to the new customer."""
    from baker.db.connection import get_db
    from baker.models.customer import load_year_summary

    c1 = _create_customer(api_client, name="Cũ", phone="0901")
    c2 = _create_customer(api_client, name="Mới", phone="0902")
    order = _create_order_with_customer(
        api_client, customer_id=c1["id"], customer_name=c1["name"]
    )
    # Link the order to customer 2
    api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": c2["id"]}
    )
    with get_db() as conn:
        ys1 = load_year_summary(conn, c1["id"], _current_year())
        ys2 = load_year_summary(conn, c2["id"], _current_year())
    assert ys1["orderCount"] == 0
    assert ys1["totalVolume"] == 0
    assert ys2["orderCount"] == 1
    assert ys2["totalVolume"] == 10000


def test_order_edit_reassigns_customer_zeroes_old_summary(api_client):
    """DG-252 FR3/FR6 — setting customerId to another customer (or null, which
    now re-resolves) recomputes the old customer's year summary to zero when
    it had no other orders."""
    from baker.db.connection import get_db
    from baker.models.customer import load_year_summary

    customer = _create_customer(api_client, name="Bỏ liên kết", phone="0900")
    order = _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    other = _create_customer(api_client, name="Khác", phone="0901")
    api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": other["id"]}
    )
    with get_db() as conn:
        ys = load_year_summary(conn, customer["id"], _current_year())
    assert ys["orderCount"] == 0
    assert ys["totalVolume"] == 0


def test_order_edit_total_volume_updates_on_items_change(api_client):
    """FR6 — editing items (total_price) recomputes the summary volume."""
    from baker.db.connection import get_db
    from baker.models.customer import load_year_summary

    customer = _create_customer(api_client, name="Sửa đơn", phone="0900")
    order = _create_order_with_customer(
        api_client, customer_id=customer["id"], customer_name=customer["name"]
    )
    # Increase the item price; total_price changes from 10000 to 50000.
    api_client.patch(
        f"/api/orders/{order['orderRef']}",
        json={
            "items": [
                {"productName": "Bánh mì", "quantity": 1, "unitPrice": 50000, "productId": "BMI-01"}
            ]
        },
    )
    with get_db() as conn:
        ys = load_year_summary(conn, customer["id"], _current_year())
    assert ys["orderCount"] == 1
    assert ys["totalVolume"] == 50000


def test_customer_year_summary_table_created_by_migration():
    """FR6 — v60 migration creates the customer_year_summary table."""
    with get_db() as conn:
        from baker.db.schema import ensure_schema

        ensure_schema(conn)
        tables = {
            r["name"]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "customer_year_summary" in tables


def test_customer_year_summary_backfilled_from_existing_orders():
    """FR6 — v60 backfills summary rows from pre-existing orders."""
    with get_db() as conn:
        from baker.db.schema import ensure_schema

        ensure_schema(conn)
        # Insert a customer and an order linked to it in the current year.
        conn.execute(
            "INSERT INTO customers (name, phone) VALUES (?, ?)",
            ("Backfill khách", "0900"),
        )
        cust_id = conn.execute(
            "SELECT id FROM customers WHERE phone = '0900'"
        ).fetchone()["id"]
        conn.execute(
            "INSERT INTO orders (order_ref, customer_name, customer_phone, items, "
            "total_price, status, due_date, customer_id, created_at, updated_at) "
            "VALUES (?, ?, ?, '[]', 30000, 'new', '2026-07-01', ?, ?, ?)",
            ("ORD-BF-001", "Backfill khách", "0900", cust_id,
             "2026-01-15T10:00:00Z", "2026-01-15T10:00:00Z"),
        )
        # Re-run the v60 callable to simulate a backfill on a pre-v60 DB.
        from baker.db.schema import _migrate_v60_customer_year_summary

        _migrate_v60_customer_year_summary(conn)
        row = conn.execute(
            "SELECT order_count, total_volume FROM customer_year_summary "
            "WHERE customer_id = ? AND year = 2026",
            (cust_id,),
        ).fetchone()
        assert row is not None
        assert int(row["order_count"]) == 1
        assert float(row["total_volume"]) == 30000