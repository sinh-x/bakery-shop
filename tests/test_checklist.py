"""Tests for Baker API — checklist endpoints (DG-028 Phase 1)."""

import pytest
from datetime import date


# ── Helpers ──────────────────────────────────────────────────────────────────

TODAY = date.today().isoformat()


def _create_template(api_client, name="Kiểm tra tủ lạnh", period="opening", sort_order=1):
    resp = api_client.post("/api/checklist/templates", json={
        "name": name,
        "period": period,
        "sort_order": sort_order,
    })
    assert resp.status_code == 201
    return resp.json()


# ── Template CRUD ─────────────────────────────────────────────────────────────


def test_list_templates_empty(api_client):
    resp = api_client.get("/api/checklist/templates")
    assert resp.status_code == 200
    # Seed data from migration provides default templates
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) >= 13  # 6 opening + 7 closing seed items


def test_list_templates_seed_data(api_client):
    resp = api_client.get("/api/checklist/templates")
    assert resp.status_code == 200
    data = resp.json()
    periods = [t["period"] for t in data]
    assert "opening" in periods
    assert "closing" in periods


def test_list_templates_filter_by_period(api_client):
    resp = api_client.get("/api/checklist/templates?period=opening")
    assert resp.status_code == 200
    data = resp.json()
    assert all(t["period"] == "opening" for t in data)

    resp = api_client.get("/api/checklist/templates?period=closing")
    assert resp.status_code == 200
    data = resp.json()
    assert all(t["period"] == "closing" for t in data)


def test_create_template(api_client):
    tmpl = _create_template(api_client, name="Bật lò nướng", period="opening", sort_order=10)
    assert tmpl["name"] == "Bật lò nướng"
    assert tmpl["period"] == "opening"
    assert tmpl["sort_order"] == 10
    assert tmpl["active"] is True
    assert "id" in tmpl
    assert "created_at" in tmpl


def test_create_template_closing(api_client):
    tmpl = _create_template(api_client, name="Đếm tiền", period="closing", sort_order=5)
    assert tmpl["period"] == "closing"
    assert tmpl["name"] == "Đếm tiền"


def test_create_template_invalid_period(api_client):
    resp = api_client.post("/api/checklist/templates", json={
        "name": "Test", "period": "invalid",
    })
    assert resp.status_code == 400


def test_update_template(api_client):
    tmpl = _create_template(api_client, name="Tên cũ", period="opening")
    tmpl_id = tmpl["id"]

    resp = api_client.put(f"/api/checklist/templates/{tmpl_id}", json={
        "name": "Tên mới", "sort_order": 99
    })
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["name"] == "Tên mới"
    assert updated["sort_order"] == 99
    assert updated["period"] == "opening"  # unchanged


def test_update_template_not_found(api_client):
    resp = api_client.put("/api/checklist/templates/99999", json={"name": "X"})
    assert resp.status_code == 404


def test_update_template_invalid_period(api_client):
    tmpl = _create_template(api_client)
    resp = api_client.put(f"/api/checklist/templates/{tmpl['id']}", json={"period": "bad"})
    assert resp.status_code == 400


def test_delete_template(api_client):
    tmpl = _create_template(api_client, name="Sẽ bị xóa")
    tmpl_id = tmpl["id"]

    resp = api_client.delete(f"/api/checklist/templates/{tmpl_id}")
    assert resp.status_code == 204

    # Verify it's gone
    resp = api_client.get("/api/checklist/templates")
    ids = [t["id"] for t in resp.json()]
    assert tmpl_id not in ids


def test_delete_template_not_found(api_client):
    resp = api_client.delete("/api/checklist/templates/99999")
    assert resp.status_code == 404


# ── Daily checklist generation ────────────────────────────────────────────────


def test_get_daily_checklist_generates_entries(api_client):
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["date"] == TODAY
    assert "entries" in data
    assert len(data["entries"]) >= 13  # seed data (6 opening + 7 closing)


def test_get_daily_checklist_idempotent(api_client):
    """Calling daily twice for the same date should not duplicate entries."""
    resp1 = api_client.get(f"/api/checklist/daily?date={TODAY}")
    resp2 = api_client.get(f"/api/checklist/daily?date={TODAY}")
    assert len(resp1.json()["entries"]) == len(resp2.json()["entries"])


def test_get_daily_checklist_default_date(api_client):
    """GET /api/checklist/daily without date param uses today."""
    resp = api_client.get("/api/checklist/daily")
    assert resp.status_code == 200
    assert resp.json()["date"] == TODAY


def test_get_daily_checklist_entries_unchecked(api_client):
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entries = resp.json()["entries"]
    assert all(e["completed"] is False for e in entries)


def test_get_daily_checklist_entry_fields(api_client):
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry = resp.json()["entries"][0]
    assert "id" in entry
    assert "template_id" in entry
    assert "checklist_date" in entry
    assert "completed" in entry
    assert "completed_by" in entry
    assert "template_name" in entry
    assert "template_period" in entry


def test_get_daily_checklist_custom_date(api_client):
    resp = api_client.get("/api/checklist/daily?date=2026-01-01")
    assert resp.status_code == 200
    assert resp.json()["date"] == "2026-01-01"


# ── Toggle (tick/untick) ──────────────────────────────────────────────────────


def test_toggle_tick(api_client):
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry = resp.json()["entries"][0]
    entry_id = entry["id"]
    assert entry["completed"] is False

    resp = api_client.post(
        f"/api/checklist/daily/{entry_id}/toggle",
        json={"staff_name": "Ân"},
    )
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["completed"] is True
    assert updated["completed_by"] == "Ân"
    assert updated["completed_at"] is not None


def test_toggle_untick(api_client):
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]

    # Tick
    api_client.post(f"/api/checklist/daily/{entry_id}/toggle", json={"staff_name": "Sinh"})
    # Untick
    resp = api_client.post(f"/api/checklist/daily/{entry_id}/toggle", json={"staff_name": ""})
    assert resp.status_code == 200
    updated = resp.json()
    assert updated["completed"] is False
    assert updated["completed_by"] == ""
    assert updated["completed_at"] is None


def test_toggle_not_found(api_client):
    resp = api_client.post("/api/checklist/daily/99999/toggle", json={"staff_name": "Ân"})
    assert resp.status_code == 404


def test_toggle_persists_on_refresh(api_client):
    """After ticking an entry, the GET daily endpoint should reflect it."""
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]

    api_client.post(f"/api/checklist/daily/{entry_id}/toggle", json={"staff_name": "Phượng"})

    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entries = {e["id"]: e for e in resp.json()["entries"]}
    assert entries[entry_id]["completed"] is True
    assert entries[entry_id]["completed_by"] == "Phượng"


# ── History ───────────────────────────────────────────────────────────────────


def test_history_empty(api_client):
    resp = api_client.get("/api/checklist/history?from_date=2020-01-01&to_date=2020-01-02")
    assert resp.status_code == 200
    assert resp.json() == []


def test_history_returns_generated_date(api_client):
    # Generate today's checklist
    api_client.get(f"/api/checklist/daily?date={TODAY}")

    resp = api_client.get(f"/api/checklist/history?from_date={TODAY}&to_date={TODAY}")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["date"] == TODAY
    assert len(data[0]["entries"]) >= 13


def test_history_default_dates(api_client):
    """Without params, history returns today."""
    api_client.get(f"/api/checklist/daily?date={TODAY}")
    resp = api_client.get("/api/checklist/history")
    assert resp.status_code == 200
    data = resp.json()
    # At minimum today's date if entries were generated
    assert isinstance(data, list)


def test_history_multiple_dates(api_client):
    api_client.get("/api/checklist/daily?date=2026-03-20")
    api_client.get("/api/checklist/daily?date=2026-03-21")

    resp = api_client.get("/api/checklist/history?from_date=2026-03-20&to_date=2026-03-21")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    dates = [d["date"] for d in data]
    assert "2026-03-20" in dates
    assert "2026-03-21" in dates


def test_history_shows_completion(api_client):
    api_client.get(f"/api/checklist/daily?date={TODAY}")
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]
    api_client.post(f"/api/checklist/daily/{entry_id}/toggle", json={"staff_name": "Tân"})

    resp = api_client.get(f"/api/checklist/history?from_date={TODAY}&to_date={TODAY}")
    entries = resp.json()[0]["entries"]
    ticked = [e for e in entries if e["id"] == entry_id]
    assert len(ticked) == 1
    assert ticked[0]["completed"] is True
    assert ticked[0]["completed_by"] == "Tân"


# ─── Timestamp format (DG-202 TC-5, TC-6) ────────────────────────────────────


def test_completed_at_is_z_suffixed_when_set(api_client):
    """TC-5: completed_at is Z-suffixed UTC when a checklist entry is toggled
    complete."""
    from datetime import datetime

    api_client.get(f"/api/checklist/daily?date={TODAY}")
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]

    toggle_resp = api_client.post(
        f"/api/checklist/daily/{entry_id}/toggle", json={"staff_name": "Tân"}
    )
    assert toggle_resp.status_code == 200
    completed_at = toggle_resp.json()["completed_at"]
    assert completed_at is not None
    assert completed_at.endswith("Z")
    assert "+" not in completed_at
    datetime.strptime(completed_at, "%Y-%m-%dT%H:%M:%SZ")


def test_completed_at_null_when_not_completed(api_client):
    """TC-5 (null case): completed_at is null before toggling."""
    api_client.get(f"/api/checklist/daily?date={TODAY}")
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entry_id = resp.json()["entries"][0]["id"]
    entry = next(e for e in resp.json()["entries"] if e["id"] == entry_id)
    assert entry["completed_at"] is None


def test_created_at_is_z_suffixed(api_client):
    """TC-6: created_at on checklist entries is Z-suffixed UTC."""
    from datetime import datetime

    api_client.get(f"/api/checklist/daily?date={TODAY}")
    resp = api_client.get(f"/api/checklist/daily?date={TODAY}")
    entries = resp.json()["entries"]
    assert len(entries) > 0
    for entry in entries:
        created_at = entry["created_at"]
        assert created_at is not None
        assert created_at.endswith("Z"), f"created_at not Z-suffixed: {created_at}"
        assert "+" not in created_at
        datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ")


def test_template_created_at_is_z_suffixed(api_client):
    """TC-6 (template): checklist template created_at is Z-suffixed UTC."""
    from datetime import datetime

    resp = api_client.post("/api/checklist/templates", json={
        "name": "TC-6 template",
        "period": "opening",
        "sort_order": 99,
    })
    assert resp.status_code == 201
    created_at = resp.json()["created_at"]
    assert created_at is not None
    assert created_at.endswith("Z")
    assert "+" not in created_at
    datetime.strptime(created_at, "%Y-%m-%dT%H:%M:%SZ")
