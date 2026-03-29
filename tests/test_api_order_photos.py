"""Tests for Baker API — order photos endpoints."""

import io

import pytest
from PIL import Image


# --- Helpers ---


def _make_test_image(width=100, height=100) -> bytes:
    """Create a minimal JPEG image for testing."""
    img = Image.new("RGB", (width, height), color="blue")
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf.read()


def _create_order(client, customer="Nguyễn Văn A", **kwargs):
    payload = {"customerName": customer, **kwargs}
    resp = client.post("/api/orders", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _upload_photo(client, ref, image_data=None, tags=""):
    if image_data is None:
        image_data = _make_test_image()
    return client.post(
        f"/api/orders/{ref}/photos",
        files={"file": ("photo.jpg", image_data, "image/jpeg")},
        data={"tags": tags},
    )


# --- List photos ---


def test_list_order_photos_empty(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.get(f"/api/orders/{ref}/photos")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_order_photos_returns_uploaded(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    _upload_photo(api_client, ref, tags="mau-trang-tri")
    resp = api_client.get(f"/api/orders/{ref}/photos")
    assert resp.status_code == 200
    photos = resp.json()
    assert len(photos) == 1
    assert photos[0]["tags"] == "mau-trang-tri"
    assert "photo_hash" in photos[0]


def test_list_order_photos_ordered_by_position(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    _upload_photo(api_client, ref, _make_test_image(100, 100))
    _upload_photo(api_client, ref, _make_test_image(101, 101))
    _upload_photo(api_client, ref, _make_test_image(102, 102))
    photos = api_client.get(f"/api/orders/{ref}/photos").json()
    positions = [p["position"] for p in photos]
    assert positions == sorted(positions)


def test_list_order_photos_order_not_found(api_client):
    resp = api_client.get("/api/orders/NONEXISTENT-REF/photos")
    assert resp.status_code == 404


# --- Upload photo ---


def test_upload_order_photo(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _upload_photo(api_client, ref, tags="chat-zalo")
    assert resp.status_code == 201
    data = resp.json()
    assert "id" in data
    assert data["tags"] == "chat-zalo"
    assert "photo_hash" in data
    assert "position" in data
    assert data["position"] == 0


def test_upload_order_photo_default_fields(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _upload_photo(api_client, ref)
    assert resp.status_code == 201
    data = resp.json()
    assert data["tags"] == ""
    assert data["position"] == 0


def test_upload_order_photo_position_increments(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    first = _upload_photo(api_client, ref, _make_test_image(100, 100))
    second = _upload_photo(api_client, ref, _make_test_image(101, 101))
    assert first.json()["position"] == 0
    assert second.json()["position"] == 1


def test_upload_order_photo_dedup_returns_existing(api_client):
    """Uploading the same photo twice returns the same record (deduped)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    image_data = _make_test_image()
    first = _upload_photo(api_client, ref, image_data)
    second = _upload_photo(api_client, ref, image_data)
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]


def test_upload_order_photo_order_not_found(api_client):
    resp = _upload_photo(api_client, "NO-SUCH-ORDER")
    assert resp.status_code == 404


def test_upload_order_photo_empty_file(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/photos",
        files={"file": ("empty.jpg", b"", "image/jpeg")},
    )
    assert resp.status_code == 400


def test_upload_order_photo_non_image_rejected(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/photos",
        files={"file": ("doc.pdf", b"fake-pdf-content", "application/pdf")},
    )
    assert resp.status_code == 400


def test_upload_order_photo_lookup_by_numeric_id(api_client):
    """Order photos endpoint works with numeric order id as well."""
    order = _create_order(api_client)
    order_id = str(order["id"])
    resp = _upload_photo(api_client, order_id)
    assert resp.status_code == 201


# --- Update tags ---


def test_update_order_photo_tags(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    photo = _upload_photo(api_client, ref).json()
    resp = api_client.patch(
        f"/api/orders/{ref}/photos/{photo['id']}",
        json={"tags": "banh-hoan-thanh"},
    )
    assert resp.status_code == 200
    assert resp.json()["tags"] == "banh-hoan-thanh"


def test_update_order_photo_position(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    photo = _upload_photo(api_client, ref).json()
    resp = api_client.patch(
        f"/api/orders/{ref}/photos/{photo['id']}",
        json={"position": 5},
    )
    assert resp.status_code == 200
    assert resp.json()["position"] == 5


def test_update_order_photo_empty_body(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    photo = _upload_photo(api_client, ref).json()
    resp = api_client.patch(
        f"/api/orders/{ref}/photos/{photo['id']}",
        json={},
    )
    assert resp.status_code == 400


def test_update_order_photo_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.patch(
        f"/api/orders/{ref}/photos/9999",
        json={"tags": "x"},
    )
    assert resp.status_code == 404


def test_update_order_photo_order_not_found(api_client):
    resp = api_client.patch(
        "/api/orders/NO-SUCH-ORDER/photos/1",
        json={"tags": "x"},
    )
    assert resp.status_code == 404


# --- Delete photo ---


def test_delete_order_photo(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    photo = _upload_photo(api_client, ref).json()
    resp = api_client.delete(f"/api/orders/{ref}/photos/{photo['id']}")
    assert resp.status_code == 200
    assert resp.json()["message"] == "Đã xóa ảnh"
    # Confirm it's gone from the list
    photos = api_client.get(f"/api/orders/{ref}/photos").json()
    assert all(p["id"] != photo["id"] for p in photos)


def test_delete_order_photo_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.delete(f"/api/orders/{ref}/photos/9999")
    assert resp.status_code == 404


def test_delete_order_photo_order_not_found(api_client):
    resp = api_client.delete("/api/orders/NO-SUCH-ORDER/photos/1")
    assert resp.status_code == 404


def test_delete_does_not_remove_other_order_photos(api_client):
    """Deleting one photo doesn't affect others on the same order."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    p1 = _upload_photo(api_client, ref, _make_test_image(100, 100)).json()
    p2 = _upload_photo(api_client, ref, _make_test_image(101, 101)).json()
    api_client.delete(f"/api/orders/{ref}/photos/{p1['id']}")
    photos = api_client.get(f"/api/orders/{ref}/photos").json()
    assert len(photos) == 1
    assert photos[0]["id"] == p2["id"]


def test_photos_isolated_between_orders(api_client):
    """Photos uploaded to one order don't appear on another."""
    order_a = _create_order(api_client, customer="A")
    order_b = _create_order(api_client, customer="B")
    _upload_photo(api_client, order_a["orderRef"])
    photos_b = api_client.get(f"/api/orders/{order_b['orderRef']}/photos").json()
    assert photos_b == []


# --- Per-item photo linking (v13) ---


def _upload_photo_with_item(client, ref, image_data=None, tags="", work_item_id=None):
    if image_data is None:
        image_data = _make_test_image()
    data = {"tags": tags}
    if work_item_id is not None:
        data["workItemId"] = str(work_item_id)
    return client.post(
        f"/api/orders/{ref}/photos",
        files={"file": ("photo.jpg", image_data, "image/jpeg")},
        data=data,
    )


def _create_order_with_item(client):
    """Create order with 1 item, return (order, work_item_id)."""
    resp = client.post("/api/orders", json={
        "customerName": "Test",
        "items": [{"productName": "Bánh kem 16cm", "unitPrice": 200000}],
    })
    assert resp.status_code == 201
    order = resp.json()
    work_item_id = int(order["workItems"][0]["id"])
    return order, work_item_id


def test_upload_photo_with_work_item_id(api_client):
    """Photo uploaded with workItemId stores the FK."""
    order, work_item_id = _create_order_with_item(api_client)
    ref = order["orderRef"]
    resp = _upload_photo_with_item(api_client, ref, work_item_id=work_item_id)
    assert resp.status_code == 201
    data = resp.json()
    assert data["work_item_id"] == work_item_id


def test_upload_photo_without_work_item_id_is_order_level(api_client):
    """Photo uploaded without workItemId has null work_item_id (order-level)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _upload_photo(api_client, ref)
    assert resp.status_code == 201
    assert resp.json()["work_item_id"] is None


def test_upload_photo_invalid_work_item_id(api_client):
    """Photo upload with non-existent workItemId returns 404."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _upload_photo_with_item(api_client, ref, work_item_id=99999)
    assert resp.status_code == 404


def test_upload_photo_work_item_wrong_order(api_client):
    """Photo upload with workItemId from a different order returns 404."""
    order_a, item_a_id = _create_order_with_item(api_client)
    order_b = _create_order(api_client, customer="B")
    ref_b = order_b["orderRef"]
    resp = _upload_photo_with_item(api_client, ref_b, work_item_id=item_a_id)
    assert resp.status_code == 404


def test_dedup_per_item_photo(api_client):
    """Same photo uploaded twice to same work_item returns existing record."""
    order, work_item_id = _create_order_with_item(api_client)
    ref = order["orderRef"]
    image_data = _make_test_image()
    first = _upload_photo_with_item(api_client, ref, image_data, work_item_id=work_item_id)
    second = _upload_photo_with_item(api_client, ref, image_data, work_item_id=work_item_id)
    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
