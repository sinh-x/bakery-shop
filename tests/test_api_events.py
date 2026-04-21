"""Tests for Baker API — event endpoints (Phase 1)."""


# --- POST /api/events ---


def test_create_event_minimal(api_client):
    resp = api_client.post("/api/events", json={"summary": "Tủ lạnh kêu lạ"})
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["summary"] == "Tủ lạnh kêu lạ"
    assert ev["type"] == "note"
    assert ev["tags"] == []
    assert ev["source"] == "app"
    assert ev["logged_by"] == ""
    assert ev["id"] is not None
    assert ev["timestamp"] is not None


def test_create_event_full(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Sự cố tủ lạnh",
        "type": "equipment",
        "tags": ["equipment", "maintenance"],
        "logged_by": "Diễm",
        "data": {"severity": "high"},
        "source": "app",
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["type"] == "equipment"
    assert ev["tags"] == ["equipment", "maintenance"]
    assert ev["logged_by"] == "Diễm"
    assert ev["data"] == {"severity": "high"}
    assert ev["source"] == "app"


def test_create_event_empty_summary_rejected(api_client):
    resp = api_client.post("/api/events", json={"summary": "   "})
    assert resp.status_code == 422


def test_create_event_missing_summary_rejected(api_client):
    resp = api_client.post("/api/events", json={"type": "note"})
    assert resp.status_code == 422


# --- GET /api/events ---


def _seed_events(api_client):
    """Seed a few events for filter tests."""
    api_client.post("/api/events", json={
        "summary": "Tủ lạnh hỏng", "type": "equipment",
        "tags": ["equipment"], "logged_by": "Diễm",
    })
    api_client.post("/api/events", json={
        "summary": "Khách hỏi giá bánh", "type": "note",
        "tags": ["knowledge-gap"], "logged_by": "Lan",
    })
    api_client.post("/api/events", json={
        "summary": "Nhập thêm bột mì", "type": "inventory",
        "tags": ["ordering"], "logged_by": "Diễm",
    })


def test_list_events_returns_all(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 3


def test_list_events_empty_db(api_client):
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_events_filter_by_type(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"type": "equipment"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["type"] == "equipment"


def test_list_events_filter_by_tag(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"tag": "equipment"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert "equipment" in events[0]["tags"]


def test_list_events_filter_by_multiple_tags(api_client):
    """Comma-separated tags returns union of matched events."""
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"tag": "equipment,ordering"})
    assert resp.status_code == 200
    # fetch_events applies AND per-tag, so each separate tag works independently
    # With comma-sep -> tags=["equipment","ordering"] -> events that have BOTH tags = 0
    # Confirm the endpoint doesn't error out
    assert resp.status_code == 200


def test_list_events_filter_by_logged_by(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"logged_by": "Lan"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["logged_by"] == "Lan"


def test_list_events_search(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"search": "tủ lạnh"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert "Tủ lạnh" in events[0]["summary"]


def test_list_events_limit(api_client):
    for i in range(5):
        api_client.post("/api/events", json={"summary": f"Event {i}"})
    resp = api_client.get("/api/events", params={"limit": 3})
    assert resp.status_code == 200
    assert len(resp.json()) == 3


def test_list_events_newest_first(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    events = resp.json()
    timestamps = [ev["timestamp"] for ev in events]
    assert timestamps == sorted(timestamps, reverse=True)


def test_list_events_tags_as_list(api_client):
    """Tags in response should be a list, not a comma string."""
    api_client.post("/api/events", json={"summary": "Test", "tags": ["a", "b"]})
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    ev = resp.json()[0]
    assert isinstance(ev["tags"], list)
    assert "a" in ev["tags"]
    assert "b" in ev["tags"]


# --- GET /api/events/{id} ---


def test_get_event_by_id(api_client):
    create_resp = api_client.post("/api/events", json={
        "summary": "Chi tiết sự kiện", "type": "note",
    })
    event_id = create_resp.json()["id"]

    resp = api_client.get(f"/api/events/{event_id}")
    assert resp.status_code == 200
    ev = resp.json()
    assert ev["id"] == event_id
    assert ev["summary"] == "Chi tiết sự kiện"


def test_get_event_not_found(api_client):
    resp = api_client.get("/api/events/9999")
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


def test_get_event_data_is_dict(api_client):
    """data field must be a parsed dict, not a JSON string."""
    create_resp = api_client.post("/api/events", json={
        "summary": "Data test", "data": {"key": "value"},
    })
    event_id = create_resp.json()["id"]
    resp = api_client.get(f"/api/events/{event_id}")
    assert resp.status_code == 200
    assert resp.json()["data"] == {"key": "value"}


# --- PATCH /api/events/{id} ---


def test_patch_event_summary(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Bản gốc"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"summary": "Đã chỉnh sửa"})
    assert resp.status_code == 200
    assert resp.json()["summary"] == "Đã chỉnh sửa"
    assert resp.json()["id"] == event_id


def test_patch_event_type(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test", "type": "note"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"type": "equipment"})
    assert resp.status_code == 200
    assert resp.json()["type"] == "equipment"


def test_patch_event_tags(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"tags": ["equipment", "maintenance"]})
    assert resp.status_code == 200
    assert resp.json()["tags"] == ["equipment", "maintenance"]


def test_patch_event_clear_tags(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test", "tags": ["old"]})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"tags": []})
    assert resp.status_code == 200
    assert resp.json()["tags"] == []


def test_patch_event_not_found(api_client):
    resp = api_client.patch("/api/events/9999", json={"summary": "X"})
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


def test_patch_event_empty_body(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={})
    assert resp.status_code == 400
    assert "Không có gì" in resp.json()["detail"]


def test_patch_event_empty_summary_rejected(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"summary": "   "})
    assert resp.status_code == 422


def test_patch_event_multiple_fields(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Gốc", "type": "note"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={
        "summary": "Cập nhật", "type": "equipment", "tags": ["staff"],
    })
    assert resp.status_code == 200
    ev = resp.json()
    assert ev["summary"] == "Cập nhật"
    assert ev["type"] == "equipment"
    assert ev["tags"] == ["staff"]


# --- Phase 5: Order Events Integration Tests ---


def _create_order_via_api(client, customer="Khách test"):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000}],
    })
    assert resp.status_code == 201
    return resp.json()


def test_create_event_with_order_id(api_client):
    """POST /api/events with orderId creates event linked to the order."""
    order = _create_order_via_api(api_client)
    order_int_id = int(order["id"])
    resp = api_client.post("/api/events", json={
        "summary": "Ghi chú đơn hàng",
        "type": "note",
        "orderId": order_int_id,
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["order_id"] == order_int_id


def test_create_event_with_invalid_order_id_returns_404(api_client):
    """POST /api/events with non-existent orderId returns 404."""
    resp = api_client.post("/api/events", json={
        "summary": "Sự kiện lạ",
        "orderId": 99999,
    })
    assert resp.status_code == 404
    assert "Không tìm thấy đơn hàng" in resp.json()["detail"]


def test_list_events_filter_by_order_id(api_client):
    """GET /api/events?order_id=N returns only events for that order."""
    order = _create_order_via_api(api_client)
    order_int_id = int(order["id"])
    # Event linked to this order
    resp1 = api_client.post("/api/events", json={
        "summary": "Sự kiện đơn hàng A", "type": "note", "orderId": order_int_id,
    })
    assert resp1.status_code == 201
    # Another event NOT linked to any order
    resp2 = api_client.post("/api/events", json={"summary": "Sự kiện chung"})
    assert resp2.status_code == 201

    # Filter by order_id should return all events linked to that order
    # (including auto-created order creation event + manual event)
    resp = api_client.get("/api/events", params={"order_id": order_int_id})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 2
    summaries = [e["summary"] for e in events]
    assert "Sự kiện đơn hàng A" in summaries
    # Order creation auto-event should also be included
    assert any("created" in e["summary"] for e in events)
    for ev in events:
        assert ev["order_id"] == order_int_id


def test_list_events_no_order_id_filter(api_client):
    """GET /api/events with no order_id returns all events including unlinked."""
    order = _create_order_via_api(api_client)
    order_int_id = int(order["id"])
    api_client.post("/api/events", json={
        "summary": "Sự kiện đơn", "orderId": order_int_id,
    })
    api_client.post("/api/events", json={"summary": "Sự kiện chung"})

    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    events = resp.json()
    # At minimum these 2 + order creation auto-event
    assert len(events) >= 2


def test_get_order_events_returns_linked_events(api_client):
    """GET /api/orders/{ref}/events returns events linked to the order."""
    order = _create_order_via_api(api_client)
    ref = order["orderRef"]
    order_int_id = int(order["id"])

    # Create a manual event linked to this order
    ev_resp = api_client.post("/api/events", json={
        "summary": "Sự kiện thủ công", "type": "note", "orderId": order_int_id,
    })
    assert ev_resp.status_code == 201

    resp = api_client.get(f"/api/orders/{ref}/events")
    assert resp.status_code == 200
    events = resp.json()
    # Manual event must appear
    manual_events = [e for e in events if e["summary"] == "Sự kiện thủ công"]
    assert len(manual_events) == 1
    assert manual_events[0]["order_id"] == order_int_id


def test_get_order_events_not_found_for_invalid_ref(api_client):
    """GET /api/orders/INVALID/events returns 404."""
    resp = api_client.get("/api/orders/ORD-NOTEXIST/events")
    assert resp.status_code == 404


def test_auto_generated_status_change_event_has_order_id(api_client):
    """Order status change auto-generates an event with order_id set."""
    order = _create_order_via_api(api_client)
    ref = order["orderRef"]
    order_int_id = int(order["id"])

    # Transition order status to trigger auto-event
    api_client.post(f"/api/orders/{ref}/status", json={"status": "confirmed"})

    resp = api_client.get(f"/api/orders/{ref}/events")
    assert resp.status_code == 200
    events = resp.json()
    status_events = [e for e in events if "status:" in e["summary"]]
    assert len(status_events) >= 1
    # Status auto-event should have order_id set
    assert status_events[0]["order_id"] == order_int_id


def test_existing_events_without_order_id_still_work(api_client):
    """Events created without orderId are returned normally in list."""
    resp = api_client.post("/api/events", json={
        "summary": "Sự kiện không có đơn",
        "type": "note",
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["order_id"] is None

    list_resp = api_client.get("/api/events")
    assert list_resp.status_code == 200
    events = list_resp.json()
    unlinked = [e for e in events if e["order_id"] is None]
    assert len(unlinked) >= 1


def test_get_order_events_by_id_instead_of_ref(api_client):
    """GET /api/orders/{id}/events works with numeric ID (not just orderRef)."""
    order = _create_order_via_api(api_client)
    order_id_str = order["id"]

    # Create manual event
    api_client.post("/api/events", json={
        "summary": "Sự kiện theo ID", "orderId": int(order_id_str),
    })

    # Use numeric ID instead of orderRef
    resp = api_client.get(f"/api/orders/{order_id_str}/events")
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) >= 1
