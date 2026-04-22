"""Catalog photo API routes — product gallery."""

import logging
from fastapi import APIRouter, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

import baker.config
from baker.api.photos import save_photo
from baker.db.connection import get_db


logger = logging.getLogger("baker.server")

# Cross-product browse — registered at /api/catalog/photos
catalog_router = APIRouter(prefix="/api/catalog", tags=["catalog"])


@catalog_router.get("/photos")
def list_catalog_photos_cross_product(
    tags: str = Query("", max_length=2000, description="Comma-separated tag keys (OR logic)"),
    categories: str = Query("", max_length=2000, description="Comma-separated category slugs (OR logic)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=100),
):
    """Danh sách ảnh bộ sưu tập across all products — paginated, filterable by tags and categories.

    Trả về product_name và photo_hash cho mỗi ảnh.
    Khi không có tag lọc, trả tất cả ảnh trên tất cả sản phẩm (paginated).
    Categories filter is AND-combined with tags filter.
    """
    with get_db() as conn:
        offset = (page - 1) * page_size

        tag_keys = [t.strip() for t in tags.split(",") if t.strip()][:50] if tags else []
        cat_slugs = [c.strip() for c in categories.split(",") if c.strip()][:50] if categories else []

        if tag_keys or cat_slugs:
            conditions = []
            params = []

            if tag_keys:
                placeholders = ",".join("?" * len(tag_keys))
                conditions.append(f"cp.id IN (SELECT DISTINCT cpt.photo_id FROM catalog_photo_tags cpt WHERE cpt.tag_key IN ({placeholders}))")
                params.extend(tag_keys)

            if cat_slugs:
                cat_placeholders = ",".join("?" * len(cat_slugs))
                conditions.append(f"p.category IN ({cat_placeholders})")
                params.extend(cat_slugs)

            where_clause = " AND ".join(conditions)
            base_query = f"""
                SELECT cp.id, cp.product_id, cp.file_path, cp.caption, cp.tags,
                       cp.position, cp.created_at, ph.hash as photo_hash,
                       p.name as product_name
                FROM product_catalog_photos cp
                JOIN photos ph ON cp.photo_id = ph.id
                JOIN products p ON cp.product_id = p.id
                WHERE {where_clause}
                ORDER BY cp.product_id, cp.position, cp.id
                LIMIT ? OFFSET ?
            """
            rows = conn.execute(base_query, params + [page_size, offset]).fetchall()
        else:
            query = """
                SELECT cp.id, cp.product_id, cp.file_path, cp.caption, cp.tags,
                       cp.position, cp.created_at, ph.hash as photo_hash,
                       p.name as product_name
                FROM product_catalog_photos cp
                JOIN photos ph ON cp.photo_id = ph.id
                JOIN products p ON cp.product_id = p.id
                ORDER BY cp.product_id, cp.position, cp.id
                LIMIT ? OFFSET ?
            """
            rows = conn.execute(query, [page_size, offset]).fetchall()

        return [_row_to_dict(r) for r in rows]


# Per-product catalog — registered at /api/products/{product_id}/catalog
router = APIRouter(prefix="/api/products", tags=["catalog"])


# ─── Per-product catalog endpoints ─────────────────────────────────────────────


class CatalogPhotoUpdate(BaseModel):
    caption: str | None = None
    tags: str | None = None
    position: int | None = None


def _row_to_dict(row) -> dict:
    return dict(row)


def _sync_catalog_photo_tags(conn, photo_id: int, tags: str):
    """Replace all catalog_photo_tags entries for a photo with new tags."""
    conn.execute(
        "DELETE FROM catalog_photo_tags WHERE photo_id = ?", (photo_id,)
    )
    if tags:
        for tag_key in [t.strip() for t in tags.split(",") if t.strip()]:
            conn.execute(
                "INSERT OR IGNORE INTO catalog_photo_tags (photo_id, tag_key) VALUES (?, ?)",
                (photo_id, tag_key),
            )


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
        logger.exception("Catalog photo upload failed for file: %s", file.filename)
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

        # Sync tags to junction table (runs regardless of whether photos row was pre-existing)
        _sync_catalog_photo_tags(conn, new_id, tags)

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

        # Sync tags to junction table if tags field was updated
        new_tags = update.tags
        if new_tags is not None:
            _sync_catalog_photo_tags(conn, photo_id, new_tags)

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

        # Belt-and-braces: clear junction rows first (FK ON DELETE CASCADE added in v28, but explicit for clarity)
        conn.execute(
            "DELETE FROM catalog_photo_tags WHERE photo_id = ?", (photo_id,)
        )
        conn.execute(
            "DELETE FROM product_catalog_photos WHERE id = ?", (photo_id,)
        )

    return {"message": "Đã xóa ảnh"}
