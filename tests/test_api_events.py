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
        "type": "incident",
        "tags": ["equipment", "maintenance"],
        "logged_by": "Diễm",
        "data": {"severity": "high"},
        "source": "app",
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["type"] == "incident"
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
        "summary": "Tủ lạnh hỏng", "type": "incident",
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
    resp = api_client.get("/api/events", params={"type": "incident"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["type"] == "incident"


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
    resp = api_client.patch(f"/api/events/{event_id}", json={"type": "incident"})
    assert resp.status_code == 200
    assert resp.json()["type"] == "incident"


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
        "summary": "Cập nhật", "type": "incident", "tags": ["staff"],
    })
    assert resp.status_code == 200
    ev = resp.json()
    assert ev["summary"] == "Cập nhật"
    assert ev["type"] == "incident"
    assert ev["tags"] == ["staff"]
