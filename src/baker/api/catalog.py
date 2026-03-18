"""Catalog photo API routes — product gallery."""

from pathlib import Path

from fastapi import APIRouter, Form, HTTPException, UploadFile
from pydantic import BaseModel

import baker.config
from baker.api.products import _resize_and_save
from baker.db.connection import get_db


router = APIRouter(prefix="/api/products", tags=["catalog"])


class CatalogPhotoUpdate(BaseModel):
    caption: str | None = None
    tags: str | None = None
    position: int | None = None


def _row_to_dict(row) -> dict:
    return dict(row)


def _catalog_dir(product_id: int) -> Path:
    return baker.config.PHOTOS_DIR / str(product_id) / "catalog"


def _catalog_file(product_id: int, photo_id: int) -> Path:
    return _catalog_dir(product_id) / f"{photo_id}.jpg"


def _catalog_path(product_id: int, photo_id: int) -> str:
    return f"photos/products/{product_id}/catalog/{photo_id}.jpg"


def _get_product_or_404(conn, product_id: int):
    row = conn.execute(
        "SELECT id FROM products WHERE id = ?", (product_id,)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
    return row


@router.get("/{product_id}/catalog")
def list_catalog_photos(product_id: int):
    """Danh sách ảnh bộ sưu tập của sản phẩm (theo thứ tự position)."""
    with get_db() as conn:
        _get_product_or_404(conn, product_id)
        rows = conn.execute(
            "SELECT * FROM product_catalog_photos WHERE product_id = ? ORDER BY position, id",
            (product_id,),
        ).fetchall()
        return [_row_to_dict(r) for r in rows]


@router.post("/{product_id}/catalog", status_code=201)
async def upload_catalog_photo(
    product_id: int,
    file: UploadFile,
    caption: str = Form(""),
    tags: str = Form(""),
):
    """Tải lên ảnh bộ sưu tập."""
    with get_db() as conn:
        _get_product_or_404(conn, product_id)

    if file.content_type and not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Tệp phải là hình ảnh")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Tệp rỗng")

    with get_db() as conn:
        result = conn.execute(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM product_catalog_photos WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        next_position = result[0]

        # Insert placeholder record to obtain photo_id
        cursor = conn.execute(
            "INSERT INTO product_catalog_photos (product_id, file_path, caption, tags, position) "
            "VALUES (?, ?, ?, ?, ?)",
            (product_id, "", caption, tags, next_position),
        )
        photo_id = cursor.lastrowid

    # Save the file using the photo_id
    catalog_dir = _catalog_dir(product_id)
    catalog_dir.mkdir(parents=True, exist_ok=True)
    dest = str(_catalog_file(product_id, photo_id))

    try:
        _resize_and_save(data, dest)
    except Exception:
        with get_db() as conn:
            conn.execute(
                "DELETE FROM product_catalog_photos WHERE id = ?", (photo_id,)
            )
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    file_path = _catalog_path(product_id, photo_id)
    with get_db() as conn:
        conn.execute(
            "UPDATE product_catalog_photos SET file_path = ? WHERE id = ?",
            (file_path, photo_id),
        )
        row = conn.execute(
            "SELECT * FROM product_catalog_photos WHERE id = ?", (photo_id,)
        ).fetchone()
        return _row_to_dict(row)


@router.patch("/{product_id}/catalog/{photo_id}")
def update_catalog_photo(
    product_id: int,
    photo_id: int,
    update: CatalogPhotoUpdate,
):
    """Cập nhật caption, tags, hoặc position của ảnh bộ sưu tập."""
    with get_db() as conn:
        _get_product_or_404(conn, product_id)

        row = conn.execute(
            "SELECT * FROM product_catalog_photos WHERE id = ? AND product_id = ?",
            (photo_id, product_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

        data = update.model_dump(exclude_unset=True)
        if not data:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        updates = [f"{field} = ?" for field in data]
        params = list(data.values()) + [photo_id]
        conn.execute(
            f"UPDATE product_catalog_photos SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        row = conn.execute(
            "SELECT * FROM product_catalog_photos WHERE id = ?", (photo_id,)
        ).fetchone()
        return _row_to_dict(row)


@router.delete("/{product_id}/catalog/{photo_id}", status_code=200)
def delete_catalog_photo(product_id: int, photo_id: int):
    """Xóa ảnh bộ sưu tập và tệp trên đĩa."""
    with get_db() as conn:
        _get_product_or_404(conn, product_id)

        row = conn.execute(
            "SELECT * FROM product_catalog_photos WHERE id = ? AND product_id = ?",
            (photo_id, product_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

        conn.execute(
            "DELETE FROM product_catalog_photos WHERE id = ?", (photo_id,)
        )

    # Remove file from disk (best-effort)
    photo_file = _catalog_file(product_id, photo_id)
    if photo_file.exists():
        photo_file.unlink()

    return {"message": "Đã xóa ảnh"}
