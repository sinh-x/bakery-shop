"""Unified photo API — hash-based flat storage."""

import hashlib
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import FileResponse

import baker.config
from baker.db.connection import get_db


router = APIRouter(prefix="/api/photos", tags=["photos"])


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
        img = Image.open(io.BytesIO(data))
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


@router.post("", status_code=201)
async def upload_photo(file: UploadFile):
    """Tải lên ảnh — hash SHA256, dedup, lưu flat. Trả về hash."""
    if file.content_type and not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Tệp phải là hình ảnh")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Tệp rỗng")

    try:
        hash_hex = save_photo(data, file.filename or "")
    except Exception:
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    return {"hash": hash_hex, "url": f"/api/photos/{hash_hex}.jpg"}


@router.get("/{photo_hash}.jpg")
def get_photo_by_hash(photo_hash: str):
    """Lấy ảnh theo hash."""
    photo_file = _flat_dir() / f"{photo_hash}.jpg"
    if not photo_file.exists():
        raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")
    return FileResponse(str(photo_file), media_type="image/jpeg")
