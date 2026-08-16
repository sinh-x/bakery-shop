"""Tests for Baker API — payment transaction photo endpoints (DG-410 Phase 2).

Covers the ``/api/orders/{ref}/transactions/{txn_id}/photo`` routes that
wrap the Phase 1 ``PaymentTransactionPhoto`` model:

- ``GET``    — retrieve the attached photo link + hash (FR4 detail sheet).
- ``POST``   — upload + attach (FR2 record / FR3 add/replace).
- ``POST /photo/link`` — link an already-saved photo by hash (FR2 record
  flow, where the photo was already uploaded as an order-level
  ``chuyen-khoan`` proof).
- ``DELETE`` — detach the photo (FR3 remove; order-level strip untouched).

Verification of AC5 (join-table record persists and the transaction's photo
is returned correctly) lives here; the model-level invariants
(single-photo-per-txn, swap, cascade) are covered by
``tests/test_payment_transaction_photo.py`` (Phase 1).
"""

import hashlib
import io

import pytest
from PIL import Image

pytestmark = pytest.mark.critical


# --- Helpers --------------------------------------------------------------


def _make_test_image(width=100, height=100, color="blue") -> bytes:
    img = Image.new("RGB", (width, height), color=color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf.read()


def _create_order(client, customer="Nguyễn Văn A", total=300000):
    resp = client.post("/api/orders", json={
        "customerName": customer,
        "dueDate": "2026-03-25",
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": total}],
    })
    assert resp.status_code == 201
    return resp.json()


def _create_txn(client, ref, amount=100000, **kwargs):
    payload = {"amount": amount, **kwargs}
    resp = client.post(f"/api/orders/{ref}/transactions", json=payload)
    assert resp.status_code == 201
    return resp.json()


def _upload_order_photo(client, ref, image_data=None, tags="chuyen-khoan"):
    """Upload a photo at the order level and return the response payload."""
    if image_data is None:
        image_data = _make_test_image()
    resp = client.post(
        f"/api/orders/{ref}/photos",
        files={"file": ("photo.jpg", image_data, "image/jpeg")},
        data={"tags": tags},
    )
    assert resp.status_code == 201
    return resp.json()


def _attach_txn_photo(client, ref, txn_id, image_data=None):
    if image_data is None:
        image_data = _make_test_image(color="red")
    return client.post(
        f"/api/orders/{ref}/transactions/{txn_id}/photo",
        files={"file": ("txn_photo.jpg", image_data, "image/jpeg")},
    )


# --- GET photo ------------------------------------------------------------


def test_get_transaction_photo_404_when_none_attached(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.get(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert resp.status_code == 404


def test_get_transaction_photo_404_when_txn_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.get(f"/api/orders/{ref}/transactions/999999/photo")
    assert resp.status_code == 404


def test_get_transaction_photo_404_when_order_not_found(api_client):
    resp = api_client.get("/api/orders/ORD-NOTEXIST/transactions/1/photo")
    assert resp.status_code == 404


def test_get_transaction_photo_returns_attached_link_and_hash(api_client):
    """AC5: the join-table record persists and the photo is returned correctly."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    image = _make_test_image(color="green")
    attach = _attach_txn_photo(api_client, ref, txn["id"], image_data=image)
    assert attach.status_code == 201

    resp = api_client.get(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["paymentTransactionId"] == str(txn["id"])
    assert payload["photoHash"] is not None
    expected_hash = hashlib.sha256(image).hexdigest()
    assert payload["photoHash"] == expected_hash
    assert payload["createdAt"] is not None


# --- POST photo (upload + attach) ----------------------------------------


def test_attach_transaction_photo_upload_creates_link(api_client):
    """FR2/FR3: uploading a photo attaches it to the transaction."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)

    resp = _attach_txn_photo(api_client, ref, txn["id"])
    assert resp.status_code == 201
    payload = resp.json()
    assert payload["paymentTransactionId"] == str(txn["id"])
    assert payload["photoHash"] is not None


def test_attach_transaction_photo_replaces_existing_link(api_client):
    """FR3: re-attaching a different photo atomically replaces the link."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)

    first = _attach_txn_photo(api_client, ref, txn["id"], _make_test_image(color="red"))
    assert first.status_code == 201
    first_hash = first.json()["photoHash"]

    second = _attach_txn_photo(
        api_client, ref, txn["id"], _make_test_image(110, 110, color="blue")
    )
    assert second.status_code == 201
    second_hash = second.json()["photoHash"]

    assert second_hash != first_hash

    # Only ONE link row exists (UNIQUE enforced + upsert replaced).
    got = api_client.get(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert got.status_code == 200
    assert got.json()["photoHash"] == second_hash


def test_attach_transaction_photo_404_when_txn_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = _attach_txn_photo(api_client, ref, 999999)
    assert resp.status_code == 404


def test_attach_transaction_photo_404_when_order_not_found(api_client):
    resp = _attach_txn_photo(api_client, "ORD-NOTEXIST", 1)
    assert resp.status_code == 404


def test_attach_transaction_photo_rejects_non_image(api_client):
    """NFR1: non-image uploads are rejected by read_image_upload."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo",
        files={"file": ("notimage.txt", b"hello", "text/plain")},
    )
    assert resp.status_code == 400


def test_attach_transaction_photo_rejects_oversize(api_client):
    """NFR1: uploads > 10 MB are rejected (413)."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    big = b"\x00" * (10 * 1024 * 1024 + 1)
    resp = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo",
        files={"file": ("big.jpg", big, "image/jpeg")},
    )
    assert resp.status_code == 413


def test_attach_transaction_photo_dedup_reuses_storage(api_client):
    """NFR1: same bytes upload twice — same hash, single photos row."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn1 = _create_txn(api_client, ref)
    txn2 = _create_txn(api_client, ref, amount=50000)

    image = _make_test_image(color="purple")
    r1 = _attach_txn_photo(api_client, ref, txn1["id"], image)
    r2 = _attach_txn_photo(api_client, ref, txn2["id"], image)
    assert r1.status_code == 201 and r2.status_code == 201
    assert r1.json()["photoHash"] == r2.json()["photoHash"]


# --- POST /photo/link (link by hash) -------------------------------------


def test_link_transaction_photo_links_existing_hash(api_client):
    """FR2 record-payment flow: link an already-uploaded order-level photo."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)

    image = _make_test_image(color="orange")
    order_photo = _upload_order_photo(api_client, ref, image_data=image)
    order_hash = order_photo["photo_hash"]

    resp = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo/link",
        json={"photoHash": order_hash},
    )
    assert resp.status_code == 201
    payload = resp.json()
    assert payload["paymentTransactionId"] == str(txn["id"])
    assert payload["photoHash"] == order_hash


def test_link_transaction_photo_replaces_existing_link(api_client):
    """FR3: re-linking a different hash replaces the existing edge."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)

    h1 = _upload_order_photo(
        api_client, ref, image_data=_make_test_image(color="red")
    )["photo_hash"]
    h2 = _upload_order_photo(
        api_client, ref, image_data=_make_test_image(101, 101, color="blue")
    )["photo_hash"]

    r1 = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo/link",
        json={"photoHash": h1},
    )
    assert r1.status_code == 201
    r2 = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo/link",
        json={"photoHash": h2},
    )
    assert r2.status_code == 201
    assert r2.json()["photoHash"] == h2

    got = api_client.get(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert got.json()["photoHash"] == h2


def test_link_transaction_photo_404_when_hash_unknown(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo/link",
        json={"photoHash": "a" * 64},
    )
    assert resp.status_code == 404


def test_link_transaction_photo_404_when_txn_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.post(
        f"/api/orders/{ref}/transactions/999999/photo/link",
        json={"photoHash": "a" * 64},
    )
    assert resp.status_code == 404


# --- DELETE photo ---------------------------------------------------------


def test_detach_transaction_photo_removes_link(api_client):
    """FR3 remove: detach the per-transaction link."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    _attach_txn_photo(api_client, ref, txn["id"])

    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert resp.status_code == 200

    # Subsequent GET returns 404 (no link).
    get_resp = api_client.get(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert get_resp.status_code == 404


def test_detach_transaction_photo_404_when_none_attached(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)
    resp = api_client.delete(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert resp.status_code == 404


def test_detach_transaction_photo_404_when_txn_not_found(api_client):
    order = _create_order(api_client)
    ref = order["orderRef"]
    resp = api_client.delete(f"/api/orders/{ref}/transactions/999999/photo")
    assert resp.status_code == 404


def test_detach_transaction_photo_preserves_order_level_strip(api_client):
    """FR5: detaching the txn photo does NOT remove the order-level photo."""
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref)

    image = _make_test_image(color="yellow")
    order_photo = _upload_order_photo(api_client, ref, image_data=image)
    order_hash = order_photo["photo_hash"]

    # Link the order-level photo to the txn, then detach the txn link.
    link = api_client.post(
        f"/api/orders/{ref}/transactions/{txn['id']}/photo/link",
        json={"photoHash": order_hash},
    )
    assert link.status_code == 201

    detach = api_client.delete(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert detach.status_code == 200

    # The order-level photo strip is unchanged.
    list_resp = api_client.get(f"/api/orders/{ref}/photos")
    assert list_resp.status_code == 200
    photos = list_resp.json()
    assert len(photos) == 1
    assert photos[0]["photo_hash"] == order_hash


# --- AC5: end-to-end persistence ----------------------------------------


def test_ac5_join_table_record_persists_and_returns_correctly(api_client):
    """AC5: given a photo linked to a transaction, when the backend API is
    queried, then the join-table record persists and the transaction's photo
    is returned correctly.
    """
    order = _create_order(api_client)
    ref = order["orderRef"]
    txn = _create_txn(api_client, ref, amount=250000, type="payment", method="transfer")

    image = _make_test_image(color="teal")
    attach = _attach_txn_photo(api_client, ref, txn["id"], image_data=image)
    assert attach.status_code == 201
    expected_hash = hashlib.sha256(image).hexdigest()
    assert attach.json()["photoHash"] == expected_hash

    # Query the GET endpoint — record persists across a fresh request.
    resp = api_client.get(f"/api/orders/{ref}/transactions/{txn['id']}/photo")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["paymentTransactionId"] == str(txn["id"])
    assert payload["photoHash"] == expected_hash
    assert payload["id"] is not None
    assert payload["createdAt"] is not None

    # The underlying photos row is the dedup target of save_photo.
    list_resp = api_client.get(f"/api/photos/{expected_hash}.jpg")
    assert list_resp.status_code == 200