"""Product CRUD API routes."""

from fastapi import APIRouter, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

import baker.config
from baker.db.connection import get_db


router = APIRouter(prefix="/api/products", tags=["products"])


class ProductCreate(BaseModel):
    name: str
    category: str = "bread"
    base_price: float = 0
    cost: float = 0
    recipe_notes: str = ""


class ProductUpdate(BaseModel):
    name: str | None = None
    category: str | None = None
    base_price: float | None = None
    cost: float | None = None
    recipe_notes: str | None = None
    active: int | None = None


def _row_to_dict(row) -> dict:
    """Convert a sqlite3.Row to a dict."""
    return dict(row)


@router.get("")
def list_products(
    category: str | None = Query(None, description="Lọc theo danh mục"),
    active: int = Query(1, description="1 = đang bán, 0 = ngừng bán"),
):
    """Danh sách sản phẩm."""
    with get_db() as conn:
        conditions = ["active = ?"]
        params: list = [active]

        if category:
            conditions.append("category = ?")
            params.append(category)

        where = " AND ".join(conditions)
        rows = conn.execute(
            f"SELECT * FROM products WHERE {where} ORDER BY category, name",
            params,
        ).fetchall()

        return [_row_to_dict(r) for r in rows]


@router.get("/{product_id}")
def get_product(product_id: int):
    """Chi tiết sản phẩm."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
        return _row_to_dict(row)


@router.post("", status_code=201)
def create_product(product: ProductCreate):
    """Tạo sản phẩm mới."""
    with get_db() as conn:
        # Check duplicate name
        existing = conn.execute(
            "SELECT id FROM products WHERE name = ?", (product.name,)
        ).fetchone()
        if existing:
            raise HTTPException(
                status_code=409, detail=f"Sản phẩm '{product.name}' đã tồn tại"
            )

        cursor = conn.execute(
            "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
            "VALUES (?, ?, ?, ?, ?)",
            (
                product.name,
                product.category,
                product.base_price,
                product.cost,
                product.recipe_notes,
            ),
        )
        new_id = cursor.lastrowid

        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (new_id,)
        ).fetchone()
        return _row_to_dict(row)


@router.patch("/{product_id}")
def update_product(product_id: int, product: ProductUpdate):
    """Cập nhật sản phẩm."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        updates = []
        params: list = []
        data = product.model_dump(exclude_unset=True)

        if not data:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        # Check name uniqueness if name is being changed
        if "name" in data and data["name"] != row["name"]:
            existing = conn.execute(
                "SELECT id FROM products WHERE name = ? AND id != ?",
                (data["name"], product_id),
            ).fetchone()
            if existing:
                raise HTTPException(
                    status_code=409,
                    detail=f"Sản phẩm '{data['name']}' đã tồn tại",
                )

        for field, value in data.items():
            updates.append(f"{field} = ?")
            params.append(value)

        params.append(product_id)
        conn.execute(
            f"UPDATE products SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        return _row_to_dict(row)


@router.delete("/{product_id}")
def delete_product(product_id: int):
    """Xoá mềm sản phẩm (active=0)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        conn.execute(
            "UPDATE products SET active = 0 WHERE id = ?", (product_id,)
        )
        return {"message": f"Đã ngừng bán sản phẩm '{row['name']}'"}


def _resize_and_save(data: bytes, dest: str, max_size: int = 1200) -> None:
    """Resize image to max dimension and save as JPEG."""
    from PIL import Image
    import io

    img = Image.open(io.BytesIO(data))
    img = img.convert("RGB")

    if max(img.size) > max_size:
        img.thumbnail((max_size, max_size), Image.LANCZOS)

    img.save(dest, "JPEG", quality=85)


@router.post("/{product_id}/photo", status_code=200)
async def upload_photo(product_id: int, file: UploadFile):
    """Tải lên ảnh sản phẩm."""
    # Verify product exists
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

    # Validate content type
    if file.content_type and not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Tệp phải là hình ảnh")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Tệp rỗng")

    baker.config.PHOTOS_DIR.mkdir(parents=True, exist_ok=True)
    dest = str(baker.config.PHOTOS_DIR / f"{product_id}.jpg")

    try:
        _resize_and_save(data, dest)
    except Exception:
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    # Store relative photo path in DB
    photo_path = f"photos/products/{product_id}.jpg"
    with get_db() as conn:
        conn.execute(
            "UPDATE products SET photo_path = ? WHERE id = ?",
            (photo_path, product_id),
        )

    return {"message": "Đã tải lên ảnh", "photo_path": photo_path}


@router.get("/{product_id}/photo")
def get_photo(product_id: int):
    """Lấy ảnh sản phẩm."""
    photo_file = baker.config.PHOTOS_DIR / f"{product_id}.jpg"
    if not photo_file.exists():
        raise HTTPException(status_code=404, detail="Chưa có ảnh cho sản phẩm này")
    return FileResponse(str(photo_file), media_type="image/jpeg")
