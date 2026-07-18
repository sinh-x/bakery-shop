"""DG-252 Phase 1 — guaranteed customer_id linking at order create/edit.

Covers FR1 (POST always persists non-NULL customer_id: resolve → auto-create),
FR2 (identity-less orders link to the shared "Khách lẻ" record), FR3 (PATCH
re-resolution never leaves customer_id NULL), AC1, and NFR1 (added
resolution/auto-create work ≤ 50 ms p95 on a seeded DB).
"""

import statistics
import time

from baker.db.connection import get_db


def _create_order_payload(customer="Khách lẻ", phone="", items=None, **kwargs):
    if items is None:
        items = [{"productName": "Bánh mì", "quantity": 1, "unitPrice": 10000, "productId": "BMI-01"}]
    payload = {
        "customerName": customer,
        "customerPhone": phone,
        "items": items,
        "dueDate": "2026-07-01",
        **kwargs,
    }
    return payload


# --- FR1: resolve path (phone → name) ---------------------------------------


def test_fr1_create_resolves_existing_customer_by_phone(api_client):
    """FR1 — POST with a phone matching an existing customer links to it."""
    cust = api_client.post("/api/customers", json={"name": "Đã có", "phone": "0900111222"}).json()
    order = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="Đã có", phone="0900111222"),
    ).json()
    assert order["customerId"] == cust["id"]


def test_fr1_create_name_only_auto_creates_when_no_phone(api_client):
    """FR1 — POST with no phone but a name: ``_resolve_customer_id_by_phone``
    returns None for an empty phone (its name fallback is only reached when a
    non-empty phone fails to match), so the order auto-creates a customer.
    Duplicates from name-only orders are accepted by design (§11) and resolved
    via the merge tool (Phase 3)."""
    order = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="Chỉ tên mới", phone=""),
    ).json()
    assert order["customerId"] is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM customers WHERE id = ?", (order["customerId"],)
        ).fetchone()
        assert row["name"] == "Chỉ tên mới"


# --- FR1: auto-create path --------------------------------------------------


def test_fr1_create_auto_creates_customer_for_unknown_phone_and_name(api_client):
    """FR1 — POST with an unknown phone+name auto-creates a customer server-side."""
    resp = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="Khách tự tạo", phone="0912345678"),
    )
    assert resp.status_code == 201
    order = resp.json()
    assert order["customerId"] is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name, phone FROM customers WHERE id = ?", (order["customerId"],)
        ).fetchone()
        assert row is not None
        assert row["name"] == "Khách tự tạo"


def test_fr1_create_auto_creates_customer_for_name_only_no_phone(api_client):
    """FR1 — POST with a name but no phone, no name match → auto-create."""
    resp = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="Chỉ có tên mới", phone=""),
    )
    assert resp.status_code == 201
    order = resp.json()
    assert order["customerId"] is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM customers WHERE id = ?", (order["customerId"],)
        ).fetchone()
        assert row["name"] == "Chỉ có tên mới"


def test_fr1_create_auto_creates_customer_for_phone_only_no_name(api_client):
    """FR1 — POST with a phone but no name → auto-create uses placeholder name."""
    resp = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="", phone="0987654321"),
    )
    assert resp.status_code == 201
    order = resp.json()
    assert order["customerId"] is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name, phone FROM customers WHERE id = ?", (order["customerId"],)
        ).fetchone()
        assert row is not None


# --- FR2: shared "Khách lẻ" walk-in record ----------------------------------


def test_fr2_identity_less_order_links_to_shared_khach_le(api_client):
    """FR2 — no name AND no phone → links to the single shared "Khách lẻ"."""
    resp = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="", phone=""),
    )
    assert resp.status_code == 201
    order = resp.json()
    assert order["customerId"] is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM customers WHERE id = ?", (order["customerId"],)
        ).fetchone()
        assert row["name"].lower() == "khách lẻ"


def test_fr2_all_identity_less_orders_share_one_khach_le_record(api_client):
    """FR2 — the shared record is created once, never one-per-order."""
    ids = []
    for _ in range(3):
        order = api_client.post(
            "/api/orders", json=_create_order_payload(customer="", phone="")
        ).json()
        ids.append(order["customerId"])
    assert len(set(ids)) == 1, "walk-in orders must share a single Khách lẻ record"


def test_fr2_khach_le_record_is_created_if_missing(api_client):
    """FR2 — the helper materialises the shared record on first use."""
    with get_db() as conn:
        before = conn.execute(
            "SELECT COUNT(*) FROM customers WHERE LOWER(name) = 'khách lẻ'"
        ).fetchone()[0]
        assert before == 0
    api_client.post("/api/orders", json=_create_order_payload(customer="", phone="")).json()
    with get_db() as conn:
        after = conn.execute(
            "SELECT COUNT(*) FROM customers WHERE LOWER(name) = 'khách lẻ'"
        ).fetchone()[0]
        assert after == 1


# --- FR3: PATCH re-resolution never leaves customer_id NULL -----------------


def test_fr3_patch_null_customer_id_with_phone_auto_creates(api_client):
    """FR3 — explicit customerId=null + new phone+name auto-creates."""
    order = api_client.post(
        "/api/orders",
        json=_create_order_payload(customer="A", phone="0900"),
    ).json()
    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}",
        json={"customerId": None, "customerPhone": "0911222333", "customerName": "Khách mới 333"},
    )
    assert resp.status_code == 200
    new_id = resp.json()["customerId"]
    assert new_id is not None
    assert new_id != order["customerId"]


def test_fr3_patch_null_customer_id_no_phone_no_name_links_to_khach_le(api_client):
    """FR3 — explicit customerId=null with no phone/name falls back to the
    row's stored identity; an identity-less row links to "Khách lẻ"."""
    # Seed a truly identity-less order, then null its customer_id directly so
    # we can exercise the walk-in fallback through PATCH.
    order = api_client.post(
        "/api/orders", json=_create_order_payload(customer="", phone="")
    ).json()
    # Already linked to Khách lẻ by create; force a re-resolve by nulling.
    with get_db() as conn:
        conn.execute(
            "UPDATE orders SET customer_id = NULL WHERE id = ?", (order["id"],)
        )
    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerId": None}
    )
    assert resp.status_code == 200
    new_id = resp.json()["customerId"]
    assert new_id is not None
    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM customers WHERE id = ?", (new_id,)
        ).fetchone()
        assert row["name"].lower() == "khách lẻ"


def test_fr3_patch_phone_change_re_resolves_to_matching_customer(api_client):
    """FR3 — changing customerPhone to another customer's phone re-links."""
    cust_a = api_client.post("/api/customers", json={"name": "A", "phone": "0901"}).json()
    cust_b = api_client.post("/api/customers", json={"name": "B", "phone": "0902"}).json()
    order = api_client.post(
        "/api/orders", json=_create_order_payload(customer="A", phone="0901")
    ).json()
    assert order["customerId"] == cust_a["id"]
    resp = api_client.patch(
        f"/api/orders/{order['orderRef']}", json={"customerPhone": "0902"}
    )
    assert resp.status_code == 200
    assert resp.json()["customerId"] == cust_b["id"]


# --- AC1: every new order carries a non-NULL customer_id --------------------


def test_ac1_every_new_order_has_non_null_customer_id(api_client):
    """AC1 — walk-in, name-only, and name+phone all persist a non-NULL id."""
    cases = [
        {"customer": "", "phone": ""},  # walk-in
        {"customer": "Chỉ tên", "phone": ""},  # name-only
        {"customer": "Tên+SĐT", "phone": "0912345000"},  # name+phone
    ]
    for case in cases:
        order = api_client.post(
            "/api/orders", json=_create_order_payload(**case)
        ).json()
        assert order["customerId"] is not None, f"case {case} left customerId null"


# --- NFR1: ≤ 50 ms p95 added overhead on a seeded DB ------------------------


def test_nfr1_order_create_p95_under_50ms_on_seeded_db(api_client):
    """NFR1 — the resolve → auto-create → walk-in chain adds ≤ 50 ms p95 to
    POST /api/customers/orders on a prod-size-approximated DB.

    The overhead is measured against a baseline where customerId is supplied
    explicitly (no resolution work). The DB is seeded with 500 customers +
    2000 customer_phones rows + 2000 orders so the indexed lookups exercise a
    non-trivial surface.
    """
    # Seed a prod-approximated dataset.
    with get_db() as conn:
        for i in range(500):
            conn.execute(
                "INSERT INTO customers (name, phone, search_name, created_at, updated_at) "
                "VALUES (?, ?, ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
                (f"Khách {i:04d}", f"0900{i:06d}", f"khach {i:04d}"),
            )
        cust_ids = [
            r["id"]
            for r in conn.execute("SELECT id FROM customers ORDER BY id ASC").fetchall()
        ]
        for idx, cid in enumerate(cust_ids):
            conn.execute(
                "INSERT INTO customer_phones (customer_id, phone, is_primary) VALUES (?, ?, 1)",
                (cid, f"0900{idx:06d}"),
            )
        for i in range(2000):
            conn.execute(
                "INSERT INTO orders (order_ref, customer_name, customer_phone, items, "
                "total_price, status, due_date, customer_id, created_at, updated_at) "
                "VALUES (?, ?, ?, '[]', 10000, 'new', '2026-07-01', ?, "
                "'2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z')",
                (f"ORD-SEED-{i:05d}", f"Khách {i % 500:04d}", f"0900{i % 500:06d}", cust_ids[i % 500]),
            )

    # Baseline: explicit customerId (no resolution).
    baseline_samples = []
    for i in range(30):
        cust_id = cust_ids[i % len(cust_ids)]
        payload = _create_order_payload(customer=f"Khách {i:04d}", phone="")
        payload["customerId"] = cust_id
        t0 = time.perf_counter()
        r = api_client.post("/api/orders", json=payload)
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        assert r.status_code == 201
        baseline_samples.append(elapsed_ms)

    # Resolution path: unknown phone+name → auto-create (full chain).
    resolve_samples = []
    for i in range(30):
        payload = _create_order_payload(
            customer=f"Khách mới resolve {i:04d}", phone=f"0999{i:06d}"
        )
        t0 = time.perf_counter()
        r = api_client.post("/api/orders", json=payload)
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        assert r.status_code == 201
        assert r.json()["customerId"] is not None
        resolve_samples.append(elapsed_ms)

    baseline_p95 = statistics.quantiles(baseline_samples, n=20)[18]
    resolve_p95 = statistics.quantiles(resolve_samples, n=20)[18]
    overhead_p95 = resolve_p95 - baseline_p95
    # NFR1 budget: ≤ 50 ms p95 added overhead.
    assert overhead_p95 <= 50.0, (
        f"NFR1 violated: added p95 overhead {overhead_p95:.2f} ms > 50 ms "
        f"(baseline p95={baseline_p95:.2f} ms, resolve p95={resolve_p95:.2f} ms)"
    )