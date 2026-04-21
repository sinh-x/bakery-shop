"""Tests for cross-product catalog browse endpoint, tag sync, and v28 schema."""

import io

from PIL import Image

from baker.db.connection import get_db


_counter = [0]


def _img(w: int, h: int) -> bytes:
    img = Image.new("RGB", (w, h), color="red")
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def _upload(client, product_id, tags=""):
    """Upload a uniquely-hashed image so dedup doesn't collapse rows."""
    _counter[0] += 1
    w = 100 + _counter[0]
    h = 100 + _counter[0]
    return client.post(
        f"/api/products/{product_id}/catalog",
        files={"file": (f"p{_counter[0]}.jpg", _img(w, h), "image/jpeg")},
        data={"tags": tags},
    ).json()


# --- GET /api/catalog/photos ---


def test_browse_empty(api_client):
    resp = api_client.get("/api/catalog/photos")
    assert resp.status_code == 200
    assert resp.json() == []


def test_browse_returns_product_name_and_photo_hash(api_client):
    _upload(api_client, 1)
    rows = api_client.get("/api/catalog/photos").json()
    assert len(rows) == 1
    row = rows[0]
    assert "product_name" in row and row["product_name"]
    assert "photo_hash" in row and row["photo_hash"]


def test_browse_filter_by_tag_key(api_client):
    _upload(api_client, 1, tags="hoa,sinh-nhat")
    _upload(api_client, 2, tags="socola")
    rows = api_client.get("/api/catalog/photos?tags=hoa").json()
    assert len(rows) == 1
    assert rows[0]["product_id"] == 1


def test_browse_filter_multiple_tags_or_logic(api_client):
    _upload(api_client, 1, tags="hoa")
    _upload(api_client, 2, tags="socola")
    _upload(api_client, 3, tags="fondant")
    rows = api_client.get("/api/catalog/photos?tags=hoa,socola").json()
    product_ids = {r["product_id"] for r in rows}
    assert product_ids == {1, 2}


def test_browse_pagination(api_client):
    for i in range(1, 6):
        _upload(api_client, i)
    page1 = api_client.get("/api/catalog/photos?page=1&page_size=2").json()
    page2 = api_client.get("/api/catalog/photos?page=2&page_size=2").json()
    assert len(page1) == 2
    assert len(page2) == 2
    assert {p["id"] for p in page1}.isdisjoint({p["id"] for p in page2})


def test_browse_page_size_clamped(api_client):
    # page_size > 100 should 422
    resp = api_client.get("/api/catalog/photos?page_size=500")
    assert resp.status_code == 422


# --- Tag sync behavior ---


def test_tag_sync_on_upload(api_client):
    photo = _upload(api_client, 1, tags="hoa,socola")
    with get_db() as conn:
        rows = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ? ORDER BY tag_key",
            (photo["id"],),
        ).fetchall()
    assert [r["tag_key"] for r in rows] == ["hoa", "socola"]


def test_tag_sync_on_update_replaces_tags(api_client):
    photo = _upload(api_client, 1, tags="hoa")
    api_client.patch(
        f"/api/products/1/catalog/{photo['id']}",
        json={"tags": "socola,fondant"},
    )
    with get_db() as conn:
        rows = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ? ORDER BY tag_key",
            (photo["id"],),
        ).fetchall()
    assert [r["tag_key"] for r in rows] == ["fondant", "socola"]


def test_tag_sync_on_update_caption_only_preserves_tags(api_client):
    photo = _upload(api_client, 1, tags="hoa")
    api_client.patch(
        f"/api/products/1/catalog/{photo['id']}",
        json={"caption": "x"},
    )
    with get_db() as conn:
        rows = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ?",
            (photo["id"],),
        ).fetchall()
    assert [r["tag_key"] for r in rows] == ["hoa"]


def test_tag_sync_on_delete_clears_junction(api_client):
    photo = _upload(api_client, 1, tags="hoa,socola")
    api_client.delete(f"/api/products/1/catalog/{photo['id']}")
    with get_db() as conn:
        rows = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ?",
            (photo["id"],),
        ).fetchall()
    assert rows == []


# --- Migration v28 / schema ---


def test_schema_at_v28(api_client):
    with get_db() as conn:
        cur = conn.execute("SELECT MAX(version) FROM schema_version")
        assert cur.fetchone()[0] >= 28


def test_catalog_photo_tags_has_cascade_fk(api_client):
    """v28 rebuilds table with ON DELETE CASCADE; verify FK-driven cleanup."""
    photo = _upload(api_client, 1, tags="hoa")
    # Direct DELETE on parent should cascade to junction rows
    with get_db() as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("DELETE FROM product_catalog_photos WHERE id = ?", (photo["id"],))
        conn.commit()
        rows = conn.execute(
            "SELECT tag_key FROM catalog_photo_tags WHERE photo_id = ?",
            (photo["id"],),
        ).fetchall()
    assert rows == []


def test_catalog_tag_vocabulary_matches_approved_f1(api_client):
    """v28 re-seeds the vocabulary — no typos from v27."""
    resp = api_client.get("/api/config/catalog_tag")
    assert resp.status_code == 200
    values = [item["value"] for item in resp.json()]
    # Spot-check expected approved keys present
    assert any(v.startswith("audience:nam:") for v in values)
    assert any(v.startswith("audience:be-trai:") for v in values)
    assert any(v.startswith("occasion:sinh-nhat:") for v in values)
    assert any(v.startswith("occasion:tet:") for v in values)
    assert any(v.startswith("style:hoa:") for v in values)
    assert any(v.startswith("style:minimalist:") for v in values)
    # v27 typos must NOT be present
    assert not any("Nam nữoi" in v for v in values)
    assert not any("Hữu quê" in v for v in values)
    assert not any("Phồn chấn" in v for v in values)


def test_catalog_tag_count_is_20(api_client):
    resp = api_client.get("/api/config/catalog_tag")
    assert len(resp.json()) == 20
