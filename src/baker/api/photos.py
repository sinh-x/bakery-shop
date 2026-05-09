"""Unified photo API — hash-based flat storage."""

import hashlib
import logging
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import UnidentifiedImageError

import baker.config
from baker.db.connection import get_db

logger = logging.getLogger("baker.server")


router = APIRouter(prefix="/api/photos", tags=["photos"])
MAX_UPLOAD_BYTES = 10 * 1024 * 1024
SHA256_HEX_RE = re.compile(r"^[0-9a-f]{64}$")


def _flat_dir() -> Path:
    return baker.config.DATA_DIR / "photos"


def save_photo(data: bytes, original_name: str = "") -> str:
    """Hash image data, resize, save to flat dir if new, insert DB record. Returns hash."""
    from PIL import Image
    import io

    hash_hex = hashlib.sha256(data).hexdigest()
    flat_dir = _flat_dir()
    flat_dir.mkdir(parents=True, exist_ok=True)
    dest = flat_dir / f"{hash_hex}.jpg"

    if not dest.exists():
        from PIL import ImageOps
        img = Image.open(io.BytesIO(data))
        img = ImageOps.exif_transpose(img)
        img = img.convert("RGB")
        if max(img.size) > 1200:
            img.thumbnail((1200, 1200), Image.LANCZOS)
        img.save(str(dest), "JPEG", quality=85)

    with get_db() as conn:
        existing = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", (hash_hex,)
        ).fetchone()
        if not existing:
            conn.execute(
                "INSERT INTO photos (hash, original_name) VALUES (?, ?)",
                (hash_hex, original_name),
            )

    return hash_hex


async def read_image_upload(file: UploadFile) -> bytes:
    """Validate an image upload and enforce size limit."""
    if file.content_type and not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Tệp phải là hình ảnh")

    data = await file.read(MAX_UPLOAD_BYTES + 1)
    if not data:
        raise HTTPException(status_code=400, detail="Tệp rỗng")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Tệp vượt quá giới hạn 10MB")
    return data


@router.post("", status_code=201)
async def upload_photo(file: UploadFile):
    """Tải lên ảnh — hash SHA256, dedup, lưu flat. Trả về hash."""
    data = await read_image_upload(file)

    try:
        hash_hex = save_photo(data, file.filename or "")
    except (UnidentifiedImageError, OSError, ValueError):
        logger.exception("Photo upload failed for file: %s", file.filename)
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    return {"hash": hash_hex, "url": f"/api/photos/{hash_hex}.jpg"}


@router.get("/{photo_hash}.jpg")
def get_photo_by_hash(photo_hash: str):
    """Lấy ảnh theo hash."""
    if not SHA256_HEX_RE.fullmatch(photo_hash):
        raise HTTPException(status_code=400, detail="Mã ảnh không hợp lệ")
    photo_file = _flat_dir() / f"{photo_hash}.jpg"
    if not photo_file.exists():
        raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")
    return FileResponse(str(photo_file), media_type="image/jpeg")
