"""Catalog photo API routes — product gallery."""

from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

import baker.config
from baker.api.photos import save_photo
from baker.db.connection import get_db


router = APIRouter(prefix="/api/products", tags=["catalog"])


class CatalogPhotoUpdate(BaseModel):
    caption: str | None = None
    tags: str | None = None
    position: int | None = None


def _row_to_dict(row) -> dict:
    return dict(row)


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
            "SELECT cp.*, ph.hash as photo_hash "
            "FROM product_catalog_photos cp "
            "LEFT JOIN photos ph ON cp.photo_id = ph.id "
            "WHERE cp.product_id = ? ORDER BY cp.position, cp.id",
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

    try:
        hash_hex = save_photo(data, file.filename or "")
    except Exception:
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    with get_db() as conn:
        photo_row = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", (hash_hex,)
        ).fetchone()
        photo_id = photo_row[0] if photo_row else None

        # Dedup: if same photo already in this product's catalog, return existing record
        if photo_id is not None:
            existing = conn.execute(
                "SELECT cp.*, ph.hash as photo_hash "
                "FROM product_catalog_photos cp "
                "LEFT JOIN photos ph ON cp.photo_id = ph.id "
                "WHERE cp.product_id = ? AND cp.photo_id = ?",
                (product_id, photo_id),
            ).fetchone()
            if existing:
                return _row_to_dict(existing)

        result = conn.execute(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM product_catalog_photos WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        next_position = result[0]

        cursor = conn.execute(
            "INSERT INTO product_catalog_photos "
            "(product_id, file_path, caption, tags, position, photo_id) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (product_id, f"photos/{hash_hex}.jpg", caption, tags, next_position, photo_id),
        )
        new_id = cursor.lastrowid

        row = conn.execute(
            "SELECT cp.*, ph.hash as photo_hash "
            "FROM product_catalog_photos cp "
            "LEFT JOIN photos ph ON cp.photo_id = ph.id "
            "WHERE cp.id = ?",
            (new_id,),
        ).fetchone()
        return _row_to_dict(row)


@router.get("/{product_id}/catalog/{photo_id}/photo")
def get_catalog_photo(product_id: int, photo_id: int):
    """Lấy ảnh bộ sưu tập theo photo_id (phục vụ ảnh qua hash)."""
    with get_db() as conn:
        _get_product_or_404(conn, product_id)
        row = conn.execute(
            "SELECT ph.hash FROM product_catalog_photos cp "
            "LEFT JOIN photos ph ON cp.photo_id = ph.id "
            "WHERE cp.id = ? AND cp.product_id = ?",
            (photo_id, product_id),
        ).fetchone()

    if not row or not row["hash"]:
        raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

    photo_file = baker.config.DATA_DIR / "photos" / f"{row['hash']}.jpg"
    if not photo_file.exists():
        raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")
    return FileResponse(str(photo_file), media_type="image/jpeg")


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
            "SELECT cp.*, ph.hash as photo_hash "
            "FROM product_catalog_photos cp "
            "LEFT JOIN photos ph ON cp.photo_id = ph.id "
            "WHERE cp.id = ?",
            (photo_id,),
        ).fetchone()
        return _row_to_dict(row)


@router.delete("/{product_id}/catalog/{photo_id}", status_code=200)
def delete_catalog_photo(product_id: int, photo_id: int):
    """Xóa ảnh bộ sưu tập (chỉ xóa bản ghi DB, giữ file hash trên đĩa)."""
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

    return {"message": "Đã xóa ảnh"}
