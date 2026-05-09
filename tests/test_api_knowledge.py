"""Tests for Baker API — knowledge base endpoints."""

import io
from starlette.testclient import TestClient


# ─── POST /api/knowledge ───────────────────────────────────────────────────────


def test_create_knowledge_minimal(api_client):
    resp = api_client.post("/api/knowledge", json={"title": "Công thức bánh"})
    assert resp.status_code == 201
    entry = resp.json()
    assert entry["title"] == "Công thức bánh"
    assert entry["type"] == "note"
    assert entry["tags"] == []
    assert entry["source"] == "app"
    assert entry["logged_by"] == ""
    assert entry["id"] is not None
    assert entry["created_at"] is not None
    assert entry["photos"] == []


def test_create_knowledge_full(api_client):
    resp = api_client.post("/api/knowledge", json={
        "title": "Cách sửa tủ lạnh",
        "content": "Bước 1: kiểm tra nguồn điện...",
        "type": "procedure",
        "tags": ["equipment", "maintenance"],
        "logged_by": "Sinh",
        "source": "app",
    })
    assert resp.status_code == 201
    entry = resp.json()
    assert entry["title"] == "Cách sửa tủ lạnh"
    assert entry["content"] == "Bước 1: kiểm tra nguồn điện..."
    assert entry["type"] == "procedure"
    assert entry["tags"] == ["equipment", "maintenance"]
    assert entry["logged_by"] == "Sinh"


def test_create_knowledge_empty_title_rejected(api_client):
    resp = api_client.post("/api/knowledge", json={"title": "   "})
    assert resp.status_code == 422


def test_create_knowledge_invalid_type_defaults_to_note(api_client):
    resp = api_client.post("/api/knowledge", json={
        "title": "Test",
        "type": "invalid_type",
    })
    assert resp.status_code == 201
    assert resp.json()["type"] == "note"


# ─── GET /api/knowledge ────────────────────────────────────────────────────────


def _seed_knowledge(api_client):
    api_client.post("/api/knowledge", json={
        "title": "Công thức bánh mì",
        "type": "recipe",
        "tags": ["bánh mì"],
    })
    api_client.post("/api/knowledge", json={
        "title": "Cách sửa lò nướng",
        "type": "procedure",
        "tags": ["equipment"],
    })
    api_client.post("/api/knowledge", json={
        "title": "Liên hệ nhà cung cấp bột",
        "type": "supplier",
        "tags": ["ordering"],
    })


def test_list_knowledge_returns_all(api_client):
    _seed_knowledge(api_client)
    resp = api_client.get("/api/knowledge")
    assert resp.status_code == 200
    entries = resp.json()
    assert len(entries) == 3


def test_list_knowledge_empty(api_client):
    resp = api_client.get("/api/knowledge")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_knowledge_filter_by_type(api_client):
    _seed_knowledge(api_client)
    resp = api_client.get("/api/knowledge", params={"type": "recipe"})
    assert resp.status_code == 200
    entries = resp.json()
    assert len(entries) == 1
    assert entries[0]["type"] == "recipe"


def test_list_knowledge_filter_by_tag(api_client):
    _seed_knowledge(api_client)
    resp = api_client.get("/api/knowledge", params={"tag": "equipment"})
    assert resp.status_code == 200
    entries = resp.json()
    assert len(entries) == 1
    assert "equipment" in entries[0]["tags"]


def test_list_knowledge_search_title(api_client):
    _seed_knowledge(api_client)
    resp = api_client.get("/api/knowledge", params={"search": "bánh mì"})
    assert resp.status_code == 200
    entries = resp.json()
    assert len(entries) == 1
    assert "bánh mì" in entries[0]["title"]


def test_list_knowledge_search_content(api_client):
    api_client.post("/api/knowledge", json={
        "title": "Ghi chú",
        "content": "Nhớ mua bột mì",
    })
    resp = api_client.get("/api/knowledge", params={"search": "bột mì"})
    assert resp.status_code == 200
    entries = resp.json()
    assert len(entries) == 1
    assert "bột mì" in entries[0]["content"]


def test_list_knowledge_limit(api_client):
    for i in range(5):
        api_client.post("/api/knowledge", json={"title": f"Mục {i}"})
    resp = api_client.get("/api/knowledge", params={"limit": 3})
    assert resp.status_code == 200
    assert len(resp.json()) == 3


def test_list_knowledge_newest_first(api_client):
    _seed_knowledge(api_client)
    resp = api_client.get("/api/knowledge")
    assert resp.status_code == 200
    entries = resp.json()
    timestamps = [e["updated_at"] for e in entries]
    assert timestamps == sorted(timestamps, reverse=True)


def test_list_knowledge_includes_photos(api_client):
    api_client.post("/api/knowledge", json={"title": "Test"})
    resp = api_client.get("/api/knowledge")
    assert resp.status_code == 200
    assert "photos" in resp.json()[0]
    assert isinstance(resp.json()[0]["photos"], list)


# ─── GET /api/knowledge/{id} ──────────────────────────────────────────────────


def test_get_knowledge_by_id(api_client):
    create_resp = api_client.post("/api/knowledge", json={
        "title": "Chi tiết",
        "type": "note",
    })
    entry_id = create_resp.json()["id"]

    resp = api_client.get(f"/api/knowledge/{entry_id}")
    assert resp.status_code == 200
    entry = resp.json()
    assert entry["id"] == entry_id
    assert entry["title"] == "Chi tiết"


def test_get_knowledge_not_found(api_client):
    resp = api_client.get("/api/knowledge/9999")
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


def test_get_knowledge_includes_photos(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]
    resp = api_client.get(f"/api/knowledge/{entry_id}")
    assert resp.status_code == 200
    assert "photos" in resp.json()


# ─── PATCH /api/knowledge/{id} ───────────────────────────────────────────────


def test_patch_knowledge_title(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Gốc"})
    entry_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/knowledge/{entry_id}", json={"title": "Đã sửa"})
    assert resp.status_code == 200
    assert resp.json()["title"] == "Đã sửa"


def test_patch_knowledge_type(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test", "type": "note"})
    entry_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/knowledge/{entry_id}", json={"type": "equipment"})
    assert resp.status_code == 200
    assert resp.json()["type"] == "equipment"


def test_patch_knowledge_tags(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/knowledge/{entry_id}", json={"tags": ["a", "b"]})
    assert resp.status_code == 200
    assert resp.json()["tags"] == ["a", "b"]


def test_patch_knowledge_clear_tags(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test", "tags": ["old"]})
    entry_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/knowledge/{entry_id}", json={"tags": []})
    assert resp.status_code == 200
    assert resp.json()["tags"] == []


def test_patch_knowledge_not_found(api_client):
    resp = api_client.patch("/api/knowledge/9999", json={"title": "X"})
    assert resp.status_code == 404


def test_patch_knowledge_empty_body(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/knowledge/{entry_id}", json={})
    assert resp.status_code == 400


def test_patch_knowledge_empty_title_rejected(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/knowledge/{entry_id}", json={"title": "  "})
    assert resp.status_code == 422


# ─── DELETE /api/knowledge/{id} ───────────────────────────────────────────────


def test_delete_knowledge(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Xóa tôi"})
    entry_id = create_resp.json()["id"]

    resp = api_client.delete(f"/api/knowledge/{entry_id}")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True

    # Confirm deleted
    get_resp = api_client.get(f"/api/knowledge/{entry_id}")
    assert get_resp.status_code == 404


def test_delete_knowledge_not_found(api_client):
    resp = api_client.delete("/api/knowledge/9999")
    assert resp.status_code == 404


# ─── Photo attachment / detachment ────────────────────────────────────────────


def test_attach_photo(api_client):
    """Create entry, upload a photo, attach it."""
    create_resp = api_client.post("/api/knowledge", json={"title": "Bánh với ảnh"})
    entry_id = create_resp.json()["id"]

    # Create a minimal JPEG in memory
    from PIL import Image
    import io
    img = Image.new("RGB", (10, 10), color="red")
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    buf.seek(0)

    files = {"file": ("test.jpg", buf, "image/jpeg")}
    resp = api_client.post(f"/api/knowledge/{entry_id}/photos", files=files)
    assert resp.status_code == 201
    photo = resp.json()
    assert "hash" in photo
    assert photo["url"].startswith("/api/photos/")


def test_attach_photo_entry_not_found(api_client):
    from PIL import Image
    import io
    img = Image.new("RGB", (10, 10))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    buf.seek(0)

    files = {"file": ("test.jpg", buf, "image/jpeg")}
    resp = api_client.post("/api/knowledge/9999/photos", files=files)
    assert resp.status_code == 404


def test_attach_photo_rejects_over_10mb(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Banh"})
    entry_id = create_resp.json()["id"]
    payload = b"x" * (10 * 1024 * 1024 + 1)

    files = {"file": ("too-large.jpg", payload, "image/jpeg")}
    resp = api_client.post(f"/api/knowledge/{entry_id}/photos", files=files)
    assert resp.status_code == 413


def test_list_photos(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]

    resp = api_client.get(f"/api/knowledge/{entry_id}/photos")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


def test_list_photos_entry_not_found(api_client):
    resp = api_client.get("/api/knowledge/9999/photos")
    assert resp.status_code == 404


def test_detach_photo(api_client):
    """Create entry + photo, then detach."""
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]

    # Upload photo
    from PIL import Image
    import io
    img = Image.new("RGB", (10, 10))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    buf.seek(0)
    files = {"file": ("test.jpg", buf, "image/jpeg")}
    attach_resp = api_client.post(f"/api/knowledge/{entry_id}/photos", files=files)
    photo_hash = attach_resp.json()["hash"]

    # Look up the actual photo_id integer from the hash
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema
    with get_db() as conn:
        ensure_schema(conn)
        row = conn.execute("SELECT id FROM photos WHERE hash = ?", (photo_hash,)).fetchone()
        photo_id = row["id"]

    # Detach using integer photo_id
    resp = api_client.delete(f"/api/knowledge/{entry_id}/photos/{photo_id}")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True


def test_detach_photo_not_found(api_client):
    create_resp = api_client.post("/api/knowledge", json={"title": "Test"})
    entry_id = create_resp.json()["id"]
    resp = api_client.delete(f"/api/knowledge/{entry_id}/photos/9999")
    assert resp.status_code == 404
