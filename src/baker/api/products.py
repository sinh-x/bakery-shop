"""Product CRUD API routes."""

from fastapi import APIRouter, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

import baker.config
from baker.code_gen import generate_code, validate_code_format
from baker.db.connection import get_db
from baker.api.photos import save_photo


router = APIRouter(prefix="/api/products", tags=["products"])


class ProductCreate(BaseModel):
    name: str
    category: str = "bread"
    base_price: float = 0
    cost: float = 0
    recipe_notes: str = ""
    product_code: str | None = None


class ProductUpdate(BaseModel):
    name: str | None = None
    category: str | None = None
    base_price: float | None = None
    cost: float | None = None
    recipe_notes: str | None = None
    active: int | None = None
    product_code: str | None = None


def _row_to_dict(row) -> dict:
    """Convert a sqlite3.Row to a dict."""
    return dict(row)


@router.get("")
def list_products(
    category: str | None = Query(None, description="Lọc theo danh mục"),
    active: int = Query(1, description="1 = đang bán, 0 = ngừng bán"),
    code: str | None = Query(None, description="Lọc theo mã sản phẩm (partial match)"),
):
    """Danh sách sản phẩm."""
    with get_db() as conn:
        conditions = ["active = ?"]
        params: list = [active]

        if category:
            conditions.append("category = ?")
            params.append(category)

        if code:
            conditions.append("product_code LIKE ?")
            params.append(f"%{code}%")

        where = " AND ".join(conditions)
        rows = conn.execute(
            f"SELECT * FROM products WHERE {where} ORDER BY category, name",
            params,
        ).fetchall()

        return [_row_to_dict(r) for r in rows]


@router.get("/code/{code}")
def get_product_by_code(code: str):
    """Lấy sản phẩm theo mã code."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM products WHERE product_code = ?", (code,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
        return _row_to_dict(row)


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

        # Validate and check duplicate product_code
        if product.product_code:
            if not validate_code_format(product.product_code):
                raise HTTPException(
                    status_code=422,
                    detail=f"Mã sản phẩm không hợp lệ: '{product.product_code}' (định dạng: PREFIX-SUFFIX, ví dụ BMI-01)",
                )
            code_exists = conn.execute(
                "SELECT id FROM products WHERE product_code = ?",
                (product.product_code,),
            ).fetchone()
            if code_exists:
                raise HTTPException(
                    status_code=409,
                    detail=f"Mã sản phẩm '{product.product_code}' đã tồn tại",
                )
            code = product.product_code
        else:
            code = generate_code(conn, product.category) or ""
        cursor = conn.execute(
            "INSERT INTO products (name, category, base_price, cost, recipe_notes, product_code) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                product.name,
                product.category,
                product.base_price,
                product.cost,
                product.recipe_notes,
                code,
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

        # Check product_code uniqueness if being changed
        if (
            "product_code" in data
            and data["product_code"]
            and data["product_code"] != row["product_code"]
        ):
            code_exists = conn.execute(
                "SELECT id FROM products WHERE product_code = ? AND id != ?",
                (data["product_code"], product_id),
            ).fetchone()
            if code_exists:
                raise HTTPException(
                    status_code=409,
                    detail=f"Mã sản phẩm '{data['product_code']}' đã tồn tại",
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


@router.post("/{product_id}/photo", status_code=200)
async def upload_photo(product_id: int, file: UploadFile):
    """Tải lên ảnh sản phẩm."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

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
        if photo_row:
            conn.execute(
                "UPDATE products SET photo_id = ? WHERE id = ?",
                (photo_row[0], product_id),
            )

    return {"message": "Đã tải lên ảnh", "hash": hash_hex, "url": f"/api/photos/{hash_hex}.jpg"}


@router.get("/{product_id}/photo")
def get_photo(product_id: int):
    """Lấy ảnh sản phẩm."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT ph.hash FROM products p "
            "LEFT JOIN photos ph ON p.photo_id = ph.id "
            "WHERE p.id = ?",
            (product_id,),
        ).fetchone()

    if not row or not row["hash"]:
        raise HTTPException(status_code=404, detail="Chưa có ảnh cho sản phẩm này")

    photo_file = baker.config.DATA_DIR / "photos" / f"{row['hash']}.jpg"
    if not photo_file.exists():
        raise HTTPException(status_code=404, detail="Chưa có ảnh cho sản phẩm này")
    return FileResponse(str(photo_file), media_type="image/jpeg")
