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
    assert resp.json() == []


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
    assert len(body) == 1
    entry = body[0]
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
    assert len(resp.json()) == 1
    # original diacritics query also matches
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "123 Nguyễn Huệ"}
    )
    assert len(resp.json()) == 1


def test_autocomplete_case_insensitive(api_client):
    _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "123 NGUYEN HUE"}
    )
    assert len(resp.json()) == 1


def test_autocomplete_trims_query(api_client):
    _create_library_entry(api_client, "123 Nguyen Hue")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "  123 nguyen  "}
    )
    assert len(resp.json()) == 1


def test_autocomplete_paginates_to_20(api_client):
    for i in range(25):
        _create_library_entry(api_client, f"So {i} Nguyen Hue")
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "nguyen hue"}
    )
    assert resp.status_code == 200
    assert len(resp.json()) == 20


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
    assert len(body) == 2
    # customer's address first
    assert body[0]["id"] == customer_entry["id"]
    assert body[0]["isCustomerAddress"] is True
    assert body[1]["id"] == general["id"]
    assert body[1]["isCustomerAddress"] is False


def test_autocomplete_without_customer_id_no_priority_flag(api_client):
    entry = _create_library_entry(api_client, "123 Nguyen Hue")
    customer = _create_customer(api_client)
    _link_customer_address(customer["id"], entry["id"])
    resp = api_client.get(
        "/api/addresses/autocomplete", params={"q": "nguyen hue"}
    )
    body = resp.json()
    assert len(body) == 1
    assert body[0]["isCustomerAddress"] is False


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
    matches = [m for m in resp.json() if m["id"] == entry["id"]]
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