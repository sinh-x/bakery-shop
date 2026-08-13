"""Tests for address library API (DG-385 Phase 2).

Covers the autocomplete endpoint (FR7/FR1/FR5), library CRUD (FR8),
normalization (FR1 — trim, lowercase, strip Vietnamese diacritics),
customer-prioritized ordering (FR5), and the ``googleMapsUrl`` payload
required for auto-bind (FR2/AC2).
"""

from baker.db.connection import get_db
from baker.services.address_library import link_customer_address


# --- Helpers ---------------------------------------------------------------


def _create_library_entry(client, display_address, google_maps_url=None):
    payload = {"displayAddress": display_address}
    if google_maps_url is not None:
        payload["googleMapsUrl"] = google_maps_url
    resp = client.post("/api/addresses/library", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _create_customer(client, name="Khách A", phone="0901234567"):
    resp = client.post("/api/customers", json={"name": name, "phone": phone})
    assert resp.status_code == 201, resp.text
    return resp.json()


def _link_customer_address(customer_id, address_library_id):
    with get_db() as conn:
        link_customer_address(conn, customer_id, address_library_id)


# --- Autocomplete ----------------------------------------------------------


def test_autocomplete_short_query_returns_empty(api_client):
    resp = api_client.get("/api/addresses/autocomplete", params={"q": "a"})
    assert resp.status_code == 200
    assert resp.json() == {"pastOrders": [], "library": []}


def test_autocomplete_missing_query_param(api_client):
    resp = api_client.get("/api/addresses/autocomplete")
    assert resp.status_code == 422


def test_autocomplete_returns_matching_address_with_map_url(api_client):
    _create_library_entry(
        api_client,
        "123 Nguyễn Huệ, Q1",
        google_maps_url="https://maps.google.com/abc",
    )
    _create_library_entry(api_client, "456 Lê Lợi, Q5")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "nguyen hue"}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["pastOrders"] == []
    library = body["library"]
    assert len(library) == 1
    entry = library[0]
    assert entry["displayAddress"] == "123 Nguyễn Huệ, Q1"
    assert entry["googleMapsUrl"] == "https://maps.google.com/abc"
    assert entry["isCustomerAddress"] is False


def test_autocomplete_normalization_strips_diacritics(api_client):
    _create_library_entry(api_client, "123 Nguyễn Huệ")
    # diacritics-stripped query matches
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "123 nguyen hue"}
    )
    assert resp.status_code == 200
    assert len(resp.json()["library"]) == 1
    # original diacritics query also matches
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "123 Nguyễn Huệ"}
    )
    assert len(resp.json()["library"]) == 1


def test_autocomplete_case_insensitive(api_client):
    _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "123 NGUYEN HUE"}
    )
    assert len(resp.json()["library"]) == 1


def test_autocomplete_trims_query(api_client):
    _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "  123 nguyen  "}
    )
    assert len(resp.json()["library"]) == 1


def test_autocomplete_paginates_to_20(api_client):
    for i in range(25):
        _create_library_entry(api_client, f"So {i} Nguyen Hue")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "nguyen hue"}
    )
    assert resp.status_code == 200
    assert len(resp.json()["library"]) == 20


def test_autocomplete_customer_addresses_ranked_first(api_client):
    general = _create_library_entry(api_client, "99 Nguyen Hue General")
    customer_entry = _create_library_entry(api_client, "12 Nguyen Hue Customer")
    customer = _create_customer(api_client)
    _link_customer_address(customer["id"], customer_entry["id"])

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "nguyen hue", "customerId": customer["id"]},
    )
    assert resp.status_code == 200
    body = resp.json()
    library = body["library"]
    assert len(library) == 2
    # customer's address first
    assert library[0]["id"] == customer_entry["id"]
    assert library[0]["isCustomerAddress"] is True
    assert library[1]["id"] == general["id"]
    assert library[1]["isCustomerAddress"] is False


def test_autocomplete_without_customer_id_no_priority_flag(api_client):
    entry = _create_library_entry(api_client, "123 Nguyen Hue")
    customer = _create_customer(api_client)
    _link_customer_address(customer["id"], entry["id"])
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "nguyen hue"}
    )
    body = resp.json()
    library = body["library"]
    assert len(library) == 1
    assert library[0]["isCustomerAddress"] is False


# --- Autocomplete grouped pastOrders (DG-388 Phase 2) --------------------


def _insert_order_for_customer(
    conn,
    *,
    order_ref,
    customer_id,
    delivery_type="door",
    delivery_address="",
    google_maps_url=None,
    status="delivered",
):
    conn.execute(
        """
        INSERT INTO orders (
            order_ref, customer_name, items, total_price, status,
            delivery_type, delivery_address, google_maps_url, customer_id
        ) VALUES (?, ?, '[]', 0, ?, ?, ?, ?, ?)
        """,
        (
            order_ref,
            "Khách test",
            status,
            delivery_type,
            delivery_address,
            google_maps_url,
            customer_id,
        ),
    )


def test_autocomplete_past_orders_returns_customer_addresses(api_client):
    """F1: pastOrders lists the customer's previous door-delivery addresses
    from past orders, with the most recent google_maps_url per address."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url="https://maps.google.com/abc",
        )
        _insert_order_for_customer(
            conn,
            order_ref="D2",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="45 Trần Hưng Đạo",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    assert resp.status_code == 200
    body = resp.json()
    past = body["pastOrders"]
    assert len(past) == 1
    assert past[0]["displayAddress"] == "123 Lê Lợi"
    assert past[0]["googleMapsUrl"] == "https://maps.google.com/abc"


def test_autocomplete_past_orders_empty_without_customer_id(api_client):
    """F1: no customerId → pastOrders is always empty (no past-order lookup)."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "le loi"}
    )
    body = resp.json()
    assert body["pastOrders"] == []


def test_autocomplete_past_orders_excludes_pickup_and_bus(api_client):
    """F1: only door-delivery orders contribute to pastOrders."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="P1",
            customer_id=customer["id"],
            delivery_type="pickup",
            delivery_address="Pickup counter",
            google_maps_url=None,
        )
        _insert_order_for_customer(
            conn,
            order_ref="B1",
            customer_id=customer["id"],
            delivery_type="bus",
            delivery_address="Bến xe",
            google_maps_url=None,
        )
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="12 Độc Lập",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "doc lap", "customerId": customer["id"]},
    )
    body = resp.json()
    addrs = {s["displayAddress"] for s in body["pastOrders"]}
    assert "12 Độc Lập" in addrs
    assert "Pickup counter" not in addrs
    assert "Bến xe" not in addrs


def test_autocomplete_past_orders_excludes_non_delivered_statuses(api_client):
    """DG-388 Phase 5.6-c4 Mn-3 regression: only orders with status in
    DELIVERED_STATUSES ('delivered', 'completed') contribute to pastOrders.
    A cancelled door-delivery order must NOT surface in the "Địa chỉ đã
    giao" (previously delivered) section."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        # delivered order at "12 Lê Lợi" — should be returned
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="12 Lê Lợi",
            google_maps_url=None,
            status="delivered",
        )
        # cancelled door-delivery order at "34 Trần Hưng Đạo" — must NOT
        # be returned (it never reached delivery, so the address is not a
        # "previously delivered" address).
        _insert_order_for_customer(
            conn,
            order_ref="C1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="34 Trần Hưng Đạo",
            google_maps_url=None,
            status="cancelled",
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    body = resp.json()
    addrs = {s["displayAddress"] for s in body["pastOrders"]}
    assert "12 Lê Lợi" in addrs
    assert "34 Trần Hưng Đạo" not in addrs


def test_autocomplete_past_orders_normalizes_query(api_client):
    """F1: past-order matching uses normalize_address so diacritics- and
    case-variants of the query resolve to the same address."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Nguyễn Huệ",
            google_maps_url=None,
        )
        conn.commit()

    # diacritics-stripped query matches diacritics-rich address
    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "123 nguyen hue", "customerId": customer["id"]},
    )
    body = resp.json()
    assert len(body["pastOrders"]) == 1
    assert body["pastOrders"][0]["displayAddress"] == "123 Nguyễn Huệ"

    # diacritics-rich query also matches
    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "123 NGUYỄN HUỆ", "customerId": customer["id"]},
    )
    assert len(resp.json()["pastOrders"]) == 1


def test_autocomplete_past_orders_dedupes_by_raw_address(api_client):
    """F1: the same raw delivery_address on multiple orders appears once,
    carrying the most recent google_maps_url seen for that address."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        # later order for the same address adds a link
        _insert_order_for_customer(
            conn,
            order_ref="D2",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url="https://maps.google.com/new",
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    body = resp.json()
    assert len(body["pastOrders"]) == 1
    assert body["pastOrders"][0]["displayAddress"] == "123 Lê Lợi"
    assert body["pastOrders"][0]["googleMapsUrl"] == "https://maps.google.com/new"


def test_autocomplete_past_orders_prefers_non_null_link_when_latest_is_null(api_client):
    """F1 regression: when the most recent order for an address has a NULL
    google_maps_url but an earlier order carried a link, the past-orders
    group must surface the most recent non-null link (per the docstring:
    "most recent google_maps_url seen for that address"), not the NULL
    value from the latest order."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        # earliest order carries a link
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url="https://maps.google.com/early",
        )
        # latest order for the same address has a NULL link
        _insert_order_for_customer(
            conn,
            order_ref="D2",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    body = resp.json()
    assert len(body["pastOrders"]) == 1
    assert body["pastOrders"][0]["displayAddress"] == "123 Lê Lợi"
    assert body["pastOrders"][0]["googleMapsUrl"] == "https://maps.google.com/early"


def test_autocomplete_past_orders_limits_to_10(api_client):
    """F2: pastOrders is capped at 10 per customer."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        for i in range(15):
            _insert_order_for_customer(
                conn,
                order_ref=f"D{i}",
                customer_id=customer["id"],
                delivery_type="door",
                delivery_address=f"Địa chỉ {i} Lê Lợi",
                google_maps_url=None,
            )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    body = resp.json()
    assert len(body["pastOrders"]) == 10


def test_autocomplete_past_orders_excludes_other_customers(api_client):
    """F1: pastOrders only returns the calling customer's addresses — orders
    for a different customer must not leak into this customer's group."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer_a = _create_customer(api_client, name="Khách A", phone="0901111111")
    customer_b = _create_customer(api_client, name="Khách B", phone="0902222222")
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="A1",
            customer_id=customer_a["id"],
            delivery_type="door",
            delivery_address="12 Lê Lợi A",
            google_maps_url=None,
        )
        _insert_order_for_customer(
            conn,
            order_ref="B1",
            customer_id=customer_b["id"],
            delivery_type="door",
            delivery_address="34 Lê Lợi B",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer_a["id"]},
    )
    body = resp.json()
    addrs = {s["displayAddress"] for s in body["pastOrders"]}
    assert "12 Lê Lợi A" in addrs
    assert "34 Lê Lợi B" not in addrs


def test_autocomplete_returns_both_groups_when_both_match(api_client):
    """FR3/AC3: endpoint returns {pastOrders, library} with both groups
    populated when the customer has matching past orders AND the library
    has matching entries."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    _create_library_entry(api_client, "123 Nguyen Hue Library")
    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="45 Nguyen Hue Past",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "nguyen hue", "customerId": customer["id"]},
    )
    body = resp.json()
    assert len(body["pastOrders"]) == 1
    assert body["pastOrders"][0]["displayAddress"] == "45 Nguyen Hue Past"
    assert len(body["library"]) == 1
    assert body["library"][0]["displayAddress"] == "123 Nguyen Hue Library"


def test_autocomplete_past_orders_omits_id_contract(api_client):
    """DG-388 CQ-3 (contract): the real `pastOrders` shape produced by
    `_autocomplete_past_orders` carries only `displayAddress` +
    `googleMapsUrl` and MUST omit `id` (past-order addresses have no
    address-library id by construction). The Flutter `AddressSuggestion`
    model has a nullable `id` to parse this shape without throwing; this
    test guards the backend side of that contract so a future change
    that re-introduces a required `id` (or a synthetic one) on pastOrders
    fails CI here.
    """
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    customer = _create_customer(api_client)
    with get_db() as conn:
        ensure_schema(conn)
        _insert_order_for_customer(
            conn,
            order_ref="D1",
            customer_id=customer["id"],
            delivery_type="door",
            delivery_address="99 Lê Lợi",
            google_maps_url="https://maps.google.com/abc",
        )
        conn.commit()

    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    assert resp.status_code == 200
    past = resp.json()["pastOrders"]
    assert len(past) == 1
    # Contract: pastOrders entries MUST NOT carry an `id` key.
    assert "id" not in past[0]
    assert past[0]["displayAddress"] == "99 Lê Lợi"
    assert past[0]["googleMapsUrl"] == "https://maps.google.com/abc"

    # The library section, by contrast, MUST still carry a non-null id
    # (library entries are address_library rows). Add a library entry
    # that matches the same query and verify the contract asymmetry.
    _create_library_entry(api_client, "Lê Lợi Library")
    resp = api_client.get(
        "/api/addresses/autocomplete",
        params={"q": "le loi", "customerId": customer["id"]},
    )
    body = resp.json()
    assert any(e["displayAddress"] == "99 Lê Lợi" for e in body["pastOrders"])
    lib_match = [e for e in body["library"] if e["displayAddress"] == "Lê Lợi Library"]
    assert lib_match, "library entry should match"
    assert lib_match[0]["id"] is not None


# --- Library CRUD ----------------------------------------------------------


def test_list_library_empty(api_client):
    resp = api_client.get("/api/addresses/library")
    assert resp.status_code == 200
    assert resp.json() == []


def test_create_library_entry(api_client):
    resp = api_client.post(
        "/api/addresses/library",
        json={"displayAddress": "123 Nguyen Hue", "googleMapsUrl": "https://maps/abc"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["id"] is not None
    assert body["displayAddress"] == "123 Nguyen Hue"
    assert body["googleMapsUrl"] == "https://maps/abc"
    assert body["createdAt"] is not None


def test_create_library_entry_strips_address(api_client):
    resp = api_client.post(
        "/api/addresses/library",
        json={"displayAddress": "  123 Nguyen Hue  "},
    )
    assert resp.status_code == 201
    assert resp.json()["displayAddress"] == "123 Nguyen Hue"


def test_create_library_entry_rejects_empty_address(api_client):
    resp = api_client.post(
        "/api/addresses/library", json={"displayAddress": "   "}
    )
    assert resp.status_code == 422


def test_create_library_entry_idempotent_on_duplicate_pair(api_client):
    first = _create_library_entry(
        api_client, "123 Nguyen Hue", google_maps_url="https://maps/abc"
    )
    second = api_client.post(
        "/api/addresses/library",
        json={"displayAddress": "123 Nguyen Hue", "googleMapsUrl": "https://maps/abc"},
    )
    assert second.status_code == 201
    # same row returned (idempotent)
    assert second.json()["id"] == first["id"]


def test_list_library_returns_entries(api_client):
    _create_library_entry(api_client, "123 Nguyen Hue")
    _create_library_entry(api_client, "456 Le Loi")
    resp = api_client.get("/api/addresses/library")
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 2


def test_list_library_search_matches_normalized(api_client):
    _create_library_entry(api_client, "123 Nguyễn Huệ")
    _create_library_entry(api_client, "456 Lê Lợi")
    resp = api_client.get(
        "/api/addresses/library", params={"search": "nguyen hue"}
    )
    assert resp.status_code == 200
    rows = resp.json()
    assert len(rows) == 1
    assert rows[0]["displayAddress"] == "123 Nguyễn Huệ"


def test_update_library_entry_address(api_client):
    entry = _create_library_entry(api_client, "Cũ")
    resp = api_client.patch(
        f"/api/addresses/library/{entry['id']}",
        json={"displayAddress": "Mới"},
    )
    assert resp.status_code == 200
    assert resp.json()["displayAddress"] == "Mới"


def test_update_library_entry_link(api_client):
    entry = _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.patch(
        f"/api/addresses/library/{entry['id']}",
        json={"googleMapsUrl": "https://maps/new"},
    )
    assert resp.status_code == 200
    assert resp.json()["googleMapsUrl"] == "https://maps/new"


def test_update_library_entry_recomputes_normalized_address(api_client):
    entry = _create_library_entry(api_client, "Old Address")
    api_client.patch(
        f"/api/addresses/library/{entry['id']}",
        json={"displayAddress": "123 Nguyễn Huệ"},
    )
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "nguyen hue"}
    )
    matches = [m for m in resp.json()["library"] if m["id"] == entry["id"]]
    assert len(matches) == 1


def test_update_library_entry_not_found(api_client):
    resp = api_client.patch(
        "/api/addresses/library/99999", json={"displayAddress": "x"}
    )
    assert resp.status_code == 404


def test_update_library_entry_collision_returns_409(api_client):
    _create_library_entry(
        api_client, "123 Nguyen Hue", google_maps_url="https://maps/abc"
    )
    second = _create_library_entry(
        api_client, "456 Le Loi", google_maps_url="https://maps/def"
    )
    resp = api_client.patch(
        f"/api/addresses/library/{second['id']}",
        json={"displayAddress": "123 Nguyen Hue", "googleMapsUrl": "https://maps/abc"},
    )
    assert resp.status_code == 409


def test_update_library_entry_no_fields_returns_existing(api_client):
    entry = _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.patch(
        f"/api/addresses/library/{entry['id']}", json={}
    )
    assert resp.status_code == 200
    assert resp.json()["id"] == entry["id"]


def test_delete_library_entry(api_client):
    entry = _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.delete(f"/api/addresses/library/{entry['id']}")
    assert resp.status_code == 200
    assert resp.json() == {"ok": True, "id": entry["id"]}
    # gone from list
    listing = api_client.get("/api/addresses/library").json()
    assert all(r["id"] != entry["id"] for r in listing)


def test_delete_library_entry_not_found(api_client):
    resp = api_client.delete("/api/addresses/library/99999")
    assert resp.status_code == 404


def test_delete_library_entry_cascades_customer_links(api_client):
    entry = _create_library_entry(api_client, "123 Nguyen Hue")
    customer = _create_customer(api_client)
    _link_customer_address(customer["id"], entry["id"])
    api_client.delete(f"/api/addresses/library/{entry['id']}")
    # customer_addresses row should be gone (FK CASCADE from v101)
    with get_db() as conn:
        row = conn.execute(
            "SELECT COUNT(*) FROM customer_addresses WHERE address_library_id = ?",
            (entry["id"],),
        ).fetchone()[0]
        assert row == 0


# --- Normalization unit ----------------------------------------------------


def test_normalize_address_unit():
    from baker.models.address import normalize_address

    assert normalize_address("  123 Nguyễn Huệ  ") == "123 nguyen hue"
    assert normalize_address("123 NGUYỄN HUỆ") == "123 nguyen hue"
    assert normalize_address("") == ""
    assert normalize_address("Đồng Khởi") == "dong khoi"


# --- Missing-links endpoint (DG-387 Phase 5) ------------------------------


def _insert_order(
    conn,
    *,
    order_ref,
    delivery_type="door",
    delivery_address="",
    google_maps_url=None,
    status="delivered",
):
    conn.execute(
        """
        INSERT INTO orders (
            order_ref, customer_name, items, total_price, status,
            delivery_type, delivery_address, google_maps_url, customer_id
        ) VALUES (?, ?, '[]', 0, ?, ?, ?, ?, NULL)
        """,
        (
            order_ref,
            "Khách test",
            status,
            delivery_type,
            delivery_address,
            google_maps_url,
        ),
    )


def test_missing_links_returns_unique_addresses_with_counts(api_client):
    """AC6/FR5: JSON array of unique ``(deliveryAddress, orderCount)`` for
    door-delivery orders with empty/NULL ``google_maps_url``."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D2",
            delivery_type="delivery",
            delivery_address="123 Lê Lợi",
            google_maps_url="",
        )
        _insert_order(
            conn,
            order_ref="D3",
            delivery_type="door",
            delivery_address="45 Trần Hưng Đạo",
            google_maps_url=None,
        )
        # Has a link — excluded.
        _insert_order(
            conn,
            order_ref="D4",
            delivery_type="door",
            delivery_address="78 Nguyễn Huệ",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    by_addr = {r["deliveryAddress"]: r["orderCount"] for r in body}
    assert by_addr["123 Lê Lợi"] == 2
    assert by_addr["45 Trần Hưng Đạo"] == 1
    assert "78 Nguyễn Huệ" not in by_addr
    # Ordered by orderCount DESC.
    assert body[0]["orderCount"] >= body[1]["orderCount"]


def test_missing_links_empty_when_all_have_links(api_client):
    """AC6: when every door-delivery order has a link, returns empty array."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url="https://maps.google.com/x",
        )
        conn.commit()

    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200
    assert resp.json() == []


def test_missing_links_excludes_pickup_and_bus(api_client):
    """FR5 guard: only ``door`` and ``delivery`` orders are considered;
    ``pickup`` and ``bus`` orders with missing links must NOT appear."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="P1",
            delivery_type="pickup",
            delivery_address="Pickup counter",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="B1",
            delivery_type="bus",
            delivery_address="Bến xe Nha Trang",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="12 Độc Lập",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200
    body = resp.json()
    addrs = {r["deliveryAddress"] for r in body}
    assert "12 Độc Lập" in addrs
    assert "Pickup counter" not in addrs
    assert "Bến xe Nha Trang" not in addrs


def test_missing_links_excludes_empty_delivery_address(api_client):
    """FR5 guard: door-delivery orders with an empty/NULL
    ``delivery_address`` are excluded (matches v102 backfill + Phase 3
    sync guard)."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D2",
            delivery_type="door",
            delivery_address=None,
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D3",
            delivery_type="door",
            delivery_address="45 Trần Hưng Đạo",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["deliveryAddress"] == "45 Trần Hưng Đạo"


def test_missing_links_is_read_only(api_client):
    """NFR4/FR5: the endpoint does not mutate the database."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="123 Lê Lợi",
            google_maps_url=None,
        )
        conn.commit()
        before = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]

    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200

    with get_db() as conn:
        after = conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
        assert after == before
        row = conn.execute(
            "SELECT google_maps_url FROM orders WHERE order_ref = ?", ("D1",)
        ).fetchone()
        assert row["google_maps_url"] is None


def test_missing_links_groups_by_raw_delivery_address(api_client):
    """FR5: grouping is on raw ``delivery_address`` (not normalized) — two
    diacritic-variant addresses that normalize to the same value appear as
    two separate rows."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        _insert_order(
            conn,
            order_ref="D1",
            delivery_type="door",
            delivery_address="Số 123 Lê Lợi",
            google_maps_url=None,
        )
        _insert_order(
            conn,
            order_ref="D2",
            delivery_type="door",
            delivery_address="so 123 le loi",
            google_maps_url=None,
        )
        conn.commit()

    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    addrs = {r["deliveryAddress"] for r in body}
    assert "Số 123 Lê Lợi" in addrs
    assert "so 123 le loi" in addrs


def test_missing_links_limit_param_paginates(api_client):
    """FR5: ``?limit=`` paginates the response (default 100)."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        for i in range(5):
            _insert_order(
                conn,
                order_ref=f"D{i}",
                delivery_type="door",
                delivery_address=f"Địa chỉ {i}",
                google_maps_url=None,
            )
        conn.commit()

    # limit=2 returns at most 2 rows.
    resp = api_client.get("/api/addresses/missing-links", params={"limit": 2})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2

    # default limit returns all 5.
    resp = api_client.get("/api/addresses/missing-links")
    assert resp.status_code == 200
    assert len(resp.json()) == 5


def test_missing_links_limit_rejects_non_positive(api_client):
    """FR5: ``limit`` must be >= 1 (FastAPI ``ge=1`` validation)."""
    resp = api_client.get("/api/addresses/missing-links", params={"limit": 0})
    assert resp.status_code == 422