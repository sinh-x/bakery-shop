"""Order photo API routes — decoration references and chat screenshots."""

from typing import Optional

from fastapi import APIRouter, Form, HTTPException, UploadFile
from pydantic import BaseModel

from baker.api.photos import save_photo
from baker.db.connection import get_db


router = APIRouter(prefix="/api/orders", tags=["order-photos"])


class OrderPhotoUpdate(BaseModel):
    tags: str | None = None
    position: int | None = None


def _row_to_dict(row) -> dict:
    return dict(row)


def _get_order_or_404(conn, ref: str):
    row = conn.execute(
        "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
        (ref, ref),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
    return row


@router.get("/{ref}/photos")
def list_order_photos(ref: str):
    """Danh sách ảnh của đơn hàng (theo thứ tự position)."""
    with get_db() as conn:
        order = _get_order_or_404(conn, ref)
        rows = conn.execute(
            "SELECT op.*, ph.hash as photo_hash "
            "FROM order_photos op "
            "LEFT JOIN photos ph ON op.photo_id = ph.id "
            "WHERE op.order_id = ? ORDER BY op.position, op.id",
            (order["id"],),
        ).fetchall()
        return [_row_to_dict(r) for r in rows]


@router.post("/{ref}/photos", status_code=201)
async def upload_order_photo(
    ref: str,
    file: UploadFile,
    tags: str = Form(""),
    workItemId: Optional[str] = Form(None),
):
    """Tải lên ảnh cho đơn hàng (ảnh mẫu trang trí, chat screenshot, v.v.)."""
    work_item_id: Optional[int] = int(workItemId) if workItemId else None

    with get_db() as conn:
        order = _get_order_or_404(conn, ref)
        order_id = order["id"]

        # Validate work_item_id belongs to this order
        if work_item_id is not None:
            item_row = conn.execute(
                "SELECT id FROM order_items WHERE id = ? AND order_id = ?",
                (work_item_id, order_id),
            ).fetchone()
            if not item_row:
                raise HTTPException(status_code=404, detail="Không tìm thấy công việc")

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

        # Dedup: if same photo already attached to this order+work_item, return existing
        if photo_id is not None:
            existing = conn.execute(
                "SELECT op.*, ph.hash as photo_hash "
                "FROM order_photos op "
                "LEFT JOIN photos ph ON op.photo_id = ph.id "
                "WHERE op.order_id = ? AND op.photo_id = ? AND "
                "COALESCE(op.work_item_id, -1) = COALESCE(?, -1)",
                (order_id, photo_id, work_item_id),
            ).fetchone()
            if existing:
                return _row_to_dict(existing)

        result = conn.execute(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM order_photos WHERE order_id = ?",
            (order_id,),
        ).fetchone()
        next_position = result[0]

        cursor = conn.execute(
            "INSERT INTO order_photos (order_id, photo_id, tags, position, work_item_id) "
            "VALUES (?, ?, ?, ?, ?)",
            (order_id, photo_id, tags, next_position, work_item_id),
        )
        new_id = cursor.lastrowid

        row = conn.execute(
            "SELECT op.*, ph.hash as photo_hash "
            "FROM order_photos op "
            "LEFT JOIN photos ph ON op.photo_id = ph.id "
            "WHERE op.id = ?",
            (new_id,),
        ).fetchone()
        return _row_to_dict(row)


@router.patch("/{ref}/photos/{photo_id}")
def update_order_photo(ref: str, photo_id: int, update: OrderPhotoUpdate):
    """Cập nhật tags hoặc position của ảnh đơn hàng."""
    with get_db() as conn:
        order = _get_order_or_404(conn, ref)

        row = conn.execute(
            "SELECT * FROM order_photos WHERE id = ? AND order_id = ?",
            (photo_id, order["id"]),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

        data = update.model_dump(exclude_unset=True)
        if not data:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        updates = [f"{field} = ?" for field in data]
        params = list(data.values()) + [photo_id]
        conn.execute(
            f"UPDATE order_photos SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        row = conn.execute(
            "SELECT op.*, ph.hash as photo_hash "
            "FROM order_photos op "
            "LEFT JOIN photos ph ON op.photo_id = ph.id "
            "WHERE op.id = ?",
            (photo_id,),
        ).fetchone()
        return _row_to_dict(row)


@router.delete("/{ref}/photos/{photo_id}", status_code=200)
def delete_order_photo(ref: str, photo_id: int):
    """Xóa ảnh khỏi đơn hàng (chỉ xóa bản ghi DB, giữ file hash trên đĩa)."""
    with get_db() as conn:
        order = _get_order_or_404(conn, ref)

        row = conn.execute(
            "SELECT * FROM order_photos WHERE id = ? AND order_id = ?",
            (photo_id, order["id"]),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

        conn.execute("DELETE FROM order_photos WHERE id = ?", (photo_id,))

    return {"message": "Đã xóa ảnh"}
