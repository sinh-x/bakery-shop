"""Tests for DG-385 Phase 3 — address library auto-sync on order save/edit.

Covers FR3 (auto-upsert on create), FR4 (sync on link add/update/remove
via edit), AC3 (delivery order create with link → upsert), AC4 (link
change via edit → library updated), and AC8 (reference-count: link
removed from one order does not delete the library entry when other
orders still reference the same address+link pair).

The sync fires ONLY for door-to-door delivery orders (``door`` or legacy
``"delivery"``) and ONLY when a Google Maps link is present, added,
updated, or removed. Pickup and bus orders do NOT trigger library sync.
"""

from concurrent.futures import ThreadPoolExecutor

from baker.db.connection import get_db


# --- Helpers ---------------------------------------------------------------


def _create_order(
    client,
    *,
    customer="Khách A",
    delivery_type="pickup",
    delivery_address="",
    google_maps_url=None,
    customer_id=None,
    items=None,
    **kwargs,
):
    if items is None:
        items = [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}]
    payload = {
        "customerName": customer,
        "items": items,
        "dueDate": "2026-08-15",
        "deliveryType": delivery_type,
        "deliveryAddress": delivery_address,
        **kwargs,
    }
    if google_maps_url is not None:
        payload["googleMapsUrl"] = google_maps_url
    if customer_id is not None:
        payload["customerId"] = customer_id
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _edit_order(client, ref, **kwargs):
    resp = client.patch(f"/api/orders/{ref}", json=kwargs)
    assert resp.status_code == 200, resp.text
    return resp.json()


def _library_count(conn):
    return conn.execute("SELECT COUNT(*) FROM address_library").fetchone()[0]


def _library_rows(conn):
    return conn.execute(
        "SELECT normalized_address, display_address, google_maps_url "
        "FROM address_library ORDER BY id"
    ).fetchall()


def _library_has(conn, display_address, google_maps_url):
    rows = conn.execute(
        "SELECT 1 FROM address_library "
        "WHERE display_address = ? AND "
        "  (google_maps_url IS ? OR google_maps_url = ?)",
        (display_address, google_maps_url, google_maps_url),
    ).fetchone()
    return rows is not None


def _create_customer(client, name="Khách A", phone="0901234567"):
    resp = client.post("/api/customers", json={"name": name, "phone": phone})
    assert resp.status_code == 201, resp.text
    return resp.json()


# --- FR3 / AC3: create_order upserts library for door delivery + link ------


def test_create_door_order_with_link_upserts_library(api_client):
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ, Q1",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 1
        assert _library_has(conn, "123 Nguyễn Huệ, Q1", "https://maps.google.com/abc")


def test_create_door_order_with_link_links_customer(api_client):
    customer = _create_customer(api_client)
    _create_order(
        api_client,
        customer=customer["name"],
        customer_id=customer["id"],
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        row = conn.execute(
            "SELECT al.id, ca.customer_id FROM address_library al "
            "JOIN customer_addresses ca ON ca.address_library_id = al.id "
            "WHERE al.display_address = ?",
            ("123 Nguyễn Huệ",),
        ).fetchone()
        assert row is not None
        assert row["customer_id"] == customer["id"]


def test_create_door_order_without_link_does_not_sync(api_client):
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url=None,
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_create_door_order_with_empty_link_does_not_sync(api_client):
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_create_door_order_without_address_does_not_sync(api_client):
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_create_pickup_order_with_link_does_not_sync(api_client):
    _create_order(
        api_client,
        delivery_type="pickup",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_create_bus_order_with_link_does_not_sync(api_client):
    _create_order(
        api_client,
        delivery_type="bus",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_create_legacy_delivery_type_with_link_upserts_library(api_client):
    _create_order(
        api_client,
        delivery_type="delivery",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 1


def test_create_two_door_orders_same_pair_upserts_once(api_client):
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 1


def test_create_door_orders_different_links_creates_two_entries(api_client):
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/def",
    )
    with get_db() as conn:
        assert _library_count(conn) == 2


# --- FR4 / AC4: edit_order syncs on link changes --------------------------


def test_edit_add_link_to_door_order_upserts_library(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_has(conn, "123 Nguyễn Huệ", "https://maps.google.com/abc")


def test_edit_update_link_on_door_order_replaces_library_entry(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl="https://maps.google.com/def",
    )
    with get_db() as conn:
        # old entry gone (no other orders reference it)
        assert not _library_has(conn, "123 Nguyễn Huệ", "https://maps.google.com/abc")
        # new entry present
        assert _library_has(conn, "123 Nguyễn Huệ", "https://maps.google.com/def")


def test_edit_remove_link_from_door_order_deletes_library_when_no_refs(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl=None,
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_edit_clear_link_with_empty_string_deletes_library(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl="",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_edit_pickup_order_does_not_sync_library(api_client):
    order = _create_order(
        api_client,
        delivery_type="pickup",
        delivery_address="123 Nguyễn Huệ",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_edit_address_only_on_door_order_does_not_resync(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    # Edit notes only — link unchanged, library must stay as-is
    _edit_order(api_client, order["orderRef"], notes="ghi chú mới")
    with get_db() as conn:
        assert _library_count(conn) == 1
        assert _library_has(conn, "123 Nguyễn Huệ", "https://maps.google.com/abc")


def test_edit_same_link_unchanged_does_not_delete(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    # Re-send the same link — must NOT trigger deletion
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_count(conn) == 1


def test_edit_door_to_pickup_removes_library_when_no_refs(api_client):
    order = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url="https://maps.google.com/abc",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        deliveryType="pickup",
        deliveryAddress="",
    )
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_edit_pickup_to_door_with_link_upserts_library(api_client):
    order = _create_order(
        api_client,
        delivery_type="pickup",
        delivery_address="123 Nguyễn Huệ",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        deliveryType="door",
        deliveryAddress="123 Nguyễn Huệ",
        googleMapsUrl="https://maps.google.com/abc",
    )
    with get_db() as conn:
        assert _library_has(conn, "123 Nguyễn Huệ", "https://maps.google.com/abc")


# --- AC8: reference-count — link removal preserves entries still in use ---


def test_ac8_link_removed_from_one_order_other_order_keeps_entry(api_client):
    addr = "123 Nguyễn Huệ"
    url = "https://maps.google.com/abc"
    order_a = _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    # Remove the link from order A only — order B still references the pair
    _edit_order(api_client, order_a["orderRef"], googleMapsUrl=None)
    with get_db() as conn:
        assert _library_count(conn) == 1
        assert _library_has(conn, addr, url)


def test_ac8_link_changed_on_one_order_other_order_keeps_old_entry(api_client):
    addr = "123 Nguyễn Huệ"
    url = "https://maps.google.com/abc"
    order_a = _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    # Change link on order A — old entry must remain (order B uses it),
    # new entry must be created for the new pair.
    _edit_order(
        api_client,
        order_a["orderRef"],
        googleMapsUrl="https://maps.google.com/def",
    )
    with get_db() as conn:
        assert _library_count(conn) == 2
        assert _library_has(conn, addr, url)
        assert _library_has(conn, addr, "https://maps.google.com/def")


def test_ac8_both_orders_remove_link_deletes_entry(api_client):
    addr = "123 Nguyễn Huệ"
    url = "https://maps.google.com/abc"
    order_a = _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    order_b = _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    _edit_order(api_client, order_a["orderRef"], googleMapsUrl=None)
    # After A clears, only B references — entry still kept
    with get_db() as conn:
        assert _library_count(conn) == 1
    # B clears too — no refs left, entry deleted
    _edit_order(api_client, order_b["orderRef"], googleMapsUrl=None)
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_ac8_pickup_order_with_same_address_does_not_count_as_ref(api_client):
    addr = "123 Nguyễn Huệ"
    url = "https://maps.google.com/abc"
    order_a = _create_order(
        api_client,
        delivery_type="door",
        delivery_address=addr,
        google_maps_url=url,
    )
    # A pickup order with the same address+link must NOT keep the library
    # entry alive when the door order's link is removed — the reference
    # count only considers door-delivery orders.
    _create_order(
        api_client,
        delivery_type="pickup",
        delivery_address=addr,
        google_maps_url=url,
    )
    _edit_order(api_client, order_a["orderRef"], googleMapsUrl=None)
    with get_db() as conn:
        assert _library_count(conn) == 0


def test_ac8_normalized_address_variants_collapse_in_reference_count(api_client):
    # Two orders with diacritics/case variants of the same address and the
    # same link — the reference count must treat them as the same pair.
    url = "https://maps.google.com/abc"
    order_a = _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
        google_maps_url=url,
    )
    _create_order(
        api_client,
        delivery_type="door",
        delivery_address="123 NGUYỄN HUỆ",
        google_maps_url=url,
    )
    # Removing the link from A must keep the entry (B is the same pair).
    _edit_order(api_client, order_a["orderRef"], googleMapsUrl=None)
    with get_db() as conn:
        assert _library_count(conn) == 1


# --- Customer link sync on edit -------------------------------------------


def test_edit_add_link_links_customer(api_client):
    customer = _create_customer(api_client)
    order = _create_order(
        api_client,
        customer=customer["name"],
        customer_id=customer["id"],
        delivery_type="door",
        delivery_address="123 Nguyễn Huệ",
    )
    _edit_order(
        api_client,
        order["orderRef"],
        googleMapsUrl="https://maps.google.com/abc",
    )
    with get_db() as conn:
        row = conn.execute(
            "SELECT ca.customer_id FROM address_library al "
            "JOIN customer_addresses ca ON ca.address_library_id = al.id "
            "WHERE al.google_maps_url = ?",
            ("https://maps.google.com/abc",),
        ).fetchone()
        assert row is not None
        assert row["customer_id"] == customer["id"]


# --- CQ-1 regression: concurrent upsert must not raise IntegrityError -------


def test_concurrent_create_library_entry_no_integrity_error(use_memory_db):
    """CQ-1: parallel calls to ``create_library_entry`` for the same pair.

    The previous SELECT-then-INSERT implementation could raise
    ``IntegrityError`` when two callers observed no existing row and both
    attempted INSERT. The ``INSERT OR IGNORE`` + ``SELECT`` fix makes the
    upsert atomic so concurrent callers resolve to the single winning row
    without surfacing an ``IntegrityError`` (which would 500 the request
    or crash an enclosing order-save transaction).
    """
    from baker.db.schema import ensure_schema
    from baker.services.address_library import create_library_entry

    with get_db() as conn:
        ensure_schema(conn)

    address = "123 Nguyễn Huệ"
    url = "https://maps.google.com/abc"

    def _upsert():
        with get_db() as conn:
            return create_library_entry(conn, display_address=address, google_maps_url=url)

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: _upsert(), range(32)))

    # All 32 concurrent upserts must resolve to the same single row.
    ids = {r.id for r in results}
    assert len(ids) == 1, f"expected one library row, got ids={ids}"
    with get_db() as conn:
        assert _library_count(conn) == 1
        assert _library_has(conn, address, url)


def test_concurrent_order_create_same_pair_no_integrity_error(api_client):
    """CQ-1 end-to-end: concurrent door-delivery order creation with the same
    address+link pair must not 500. Each ``POST /api/orders`` runs
    ``sync_on_order_save`` → ``create_library_entry`` inside its own
    ``get_db()`` transaction; under the old implementation the second
    request could ``IntegrityError`` and surface a 500 to the client.
    """
    addr = "123 Nguyễn Huệ"
    url = "https://maps.google.com/abc"

    def _post(_):
        return api_client.post(
            "/api/orders",
            json={
                "customerName": "Khách đồng thời",
                "items": [
                    {"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}
                ],
                "dueDate": "2026-08-15",
                "deliveryType": "door",
                "deliveryAddress": addr,
                "googleMapsUrl": url,
            },
        )

    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(_post, range(8)))

    assert all(r.status_code == 201 for r in responses), [
        (r.status_code, r.text) for r in responses
    ]
    with get_db() as conn:
        assert _library_count(conn) == 1
        assert _library_has(conn, addr, url)