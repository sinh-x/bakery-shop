"""Dedicated tests for baker.api.photos module functions (FR-PY-6).

Covers save_photo (hash, resize, dedup, DB insert), read_image_upload
(content-type/size validation), and get_photo_by_hash (hash validation, 404).
"""

import asyncio
import hashlib
import io

import pytest
from PIL import Image
from starlette.datastructures import UploadFile

from baker.api.photos import (
    MAX_UPLOAD_BYTES,
    SHA256_HEX_RE,
    get_photo_by_hash,
    read_image_upload,
    save_photo,
)


def _make_image_bytes(width=100, height=100, color="red") -> bytes:
    img = Image.new("RGB", (width, height), color=color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    buf.seek(0)
    return buf.read()


def _make_upload(data: bytes, filename: str = "test.jpg", content_type: str = "image/jpeg") -> UploadFile:
    from starlette.datastructures import Headers

    return UploadFile(
        file=io.BytesIO(data),
        filename=filename,
        headers=Headers({"content-type": content_type}),
    )


def test_save_photo_returns_sha256_hash(api_client):
    data = _make_image_bytes()
    hash_hex = save_photo(data, "test.jpg")
    assert len(hash_hex) == 64
    assert hash_hex == hashlib.sha256(data).hexdigest()


def test_save_photo_resizes_large_image(api_client):
    import baker.config

    data = _make_image_bytes(width=2000, height=1500)
    hash_hex = save_photo(data, "big.jpg")
    photo_path = baker.config.DATA_DIR / "photos" / f"{hash_hex}.jpg"
    assert photo_path.exists()
    saved = Image.open(photo_path)
    assert max(saved.size) <= 1200


def test_save_photo_dedup_does_not_reinsert(api_client):
    from baker.db.connection import get_db

    data = _make_image_bytes()
    hash1 = save_photo(data, "a.jpg")
    hash2 = save_photo(data, "b.jpg")
    assert hash1 == hash2
    with get_db() as conn:
        rows = conn.execute(
            "SELECT id, original_name FROM photos WHERE hash = ?", (hash1,)
        ).fetchall()
        assert len(rows) == 1


def test_save_photo_inserts_db_record(api_client):
    from baker.db.connection import get_db

    data = _make_image_bytes()
    hash_hex = save_photo(data, "my-photo.jpg")
    with get_db() as conn:
        row = conn.execute(
            "SELECT hash, original_name FROM photos WHERE hash = ?", (hash_hex,)
        ).fetchone()
        assert row is not None
        assert row["hash"] == hash_hex
        assert row["original_name"] == "my-photo.jpg"


def test_read_image_upload_valid(api_client):
    data = _make_image_bytes()
    upload = _make_upload(data)
    result = asyncio.run(read_image_upload(upload))
    assert result == data


def test_read_image_upload_rejects_non_image(api_client):
    upload = _make_upload(b"not an image", content_type="text/plain")
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(read_image_upload(upload))
    assert exc_info.value.status_code == 400
    assert "Tệp phải là hình ảnh" in str(exc_info.value.detail)


def test_read_image_upload_rejects_empty(api_client):
    upload = _make_upload(b"", content_type="image/jpeg")
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(read_image_upload(upload))
    assert exc_info.value.status_code == 400
    assert "Tệp rỗng" in str(exc_info.value.detail)


def test_read_image_upload_rejects_oversize(api_client):
    big = b"\x00" * (MAX_UPLOAD_BYTES + 1)
    upload = _make_upload(big, content_type="image/jpeg")
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(read_image_upload(upload))
    assert exc_info.value.status_code == 413
    assert "10MB" in str(exc_info.value.detail)


def test_get_photo_by_hash_invalid_hash_returns_400(api_client):
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        get_photo_by_hash("too-short")
    assert exc_info.value.status_code == 400


def test_get_photo_by_hash_valid_format_not_found_returns_404(api_client):
    from fastapi import HTTPException

    valid_but_missing = "0" * 64
    with pytest.raises(HTTPException) as exc_info:
        get_photo_by_hash(valid_but_missing)
    assert exc_info.value.status_code == 404


def test_get_photo_by_hash_serves_existing_photo(api_client):
    data = _make_image_bytes()
    hash_hex = save_photo(data, "serve.jpg")
    response = get_photo_by_hash(hash_hex)
    assert response.status_code == 200
    assert response.media_type == "image/jpeg"


def test_sha256_hex_regex_rejects_invalid():
    assert SHA256_HEX_RE.fullmatch("abc") is None
    assert SHA256_HEX_RE.fullmatch("g" * 64) is None
    assert SHA256_HEX_RE.fullmatch("a" * 64) is not None