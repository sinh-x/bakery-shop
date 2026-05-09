"""Product CRUD API routes."""

import json
from fastapi import APIRouter, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from PIL import UnidentifiedImageError
from pydantic import BaseModel

import baker.config
from baker.code_gen import generate_code, get_category_prefix
from baker.db.connection import get_db
from baker.api.photos import read_image_upload, save_photo


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


def _product_price_chips(conn, product_id: int) -> list[dict]:
    """Get ordered price chips for a product."""
    rows = conn.execute(
        "SELECT id, label, price, position "
        "FROM product_price_chips "
        "WHERE product_id = ? "
        "ORDER BY position, id",
        (product_id,),
    ).fetchall()
    return [
        {
            "id": row["id"],
            "label": row["label"],
            "price": row["price"],
            "position": row["position"],
        }
        for row in rows
    ]


def _product_attributes(conn, product_id: int) -> dict:
    """Get attribute values for a product, falling back to attribute type defaults."""
    # Get product's category for applicable_types check
    product = conn.execute(
        "SELECT category FROM products WHERE id = ?", (product_id,)
    ).fetchone()
    if not product:
        return {}

    product_category = product["category"]

    # Get applicable attribute types for this category
    applicable_types = {
        row["attribute_type"]: row["default_value"]
        for row in conn.execute(
            """SELECT attribute_type, default_value, applicable_categories
               FROM product_attributes WHERE active = 1"""
        ).fetchall()
        if product_category in (json.loads(row["applicable_categories"]) if row["applicable_categories"] else [])
    }

    # Get per-product overrides
    overrides = {
        row["attribute_type"]: row["value"]
        for row in conn.execute(
            "SELECT attribute_type, value FROM product_attribute_values WHERE product_id = ?",
            (product_id,),
        ).fetchall()
    }

    result = {}
    for attr_type, default in applicable_types.items():
        result[attr_type] = overrides.get(attr_type, default)
    # Also include per-product overrides not covered by applicable_types
    for attr_type, value in overrides.items():
        if attr_type not in result:
            result[attr_type] = value
    return result


def _product_enum_attributes(conn, product_id: int, product_category: str) -> list[dict]:
    """Build the enum_attributes list for a product.

    Returns one entry per enum attribute applicable to the product's category.
    Each entry embeds the active options ordered by sort_order then id, plus
    `default_option_id` (parsed from `product_attributes.default_value`) and a
    per-option `is_default` flag.
    """
    enum_attrs = conn.execute(
        """SELECT id, attribute_type, label_vi, applicable_categories, default_value
           FROM product_attributes
           WHERE active = 1 AND value_type = 'enum'
           ORDER BY sort_order, attribute_type"""
    ).fetchall()

    result: list[dict] = []
    for attr in enum_attrs:
        try:
            cats = json.loads(attr["applicable_categories"]) if attr["applicable_categories"] else []
        except (json.JSONDecodeError, TypeError):
            cats = []
        if cats and product_category not in cats:
            continue

        try:
            default_option_id = int(attr["default_value"]) if attr["default_value"] else None
        except (ValueError, TypeError):
            default_option_id = None

        option_rows = conn.execute(
            "SELECT id, value_vi, sort_order, active FROM product_attribute_options "
            "WHERE attribute_id = ? AND active = 1 ORDER BY sort_order, id",
            (attr["id"],),
        ).fetchall()

        options = [
            {
                "id": opt["id"],
                "value_vi": opt["value_vi"],
                "sort_order": opt["sort_order"],
                "active": opt["active"],
                "is_default": default_option_id is not None and opt["id"] == default_option_id,
            }
            for opt in option_rows
        ]

        result.append({
            "attribute_type": attr["attribute_type"],
            "label_vi": attr["label_vi"],
            "default_option_id": default_option_id,
            "options": options,
        })

    return result


def _enrich_product(conn, row) -> dict:
    """Attach computed product fields for API responses."""
    product = _row_to_dict(row)
    product["attributes"] = _product_attributes(conn, product["id"])
    product["price_chips"] = _product_price_chips(conn, product["id"])
    product["enum_attributes"] = _product_enum_attributes(
        conn, product["id"], product.get("category") or ""
    )
    return product


@router.get("")
def list_products(
    category: str | None = Query(None, description="Lọc theo danh mục"),
    active: int = Query(1, description="1 = đang bán, 0 = ngừng bán"),
    code: str | None = Query(None, description="Lọc theo mã sản phẩm (partial match)"),
    trung_bay: int = Query(0, description="1 = chỉ sản phẩm trưng bày"),
):
    """Danh sách sản phẩm."""
    with get_db() as conn:
        conditions = ["p.active = ?"]
        params: list = [active]
        joins = []

        if category:
            conditions.append("p.category = ?")
            params.append(category)

        if code:
            conditions.append("p.product_code LIKE ?")
            params.append(f"%{code}%")

        joins.append(
            """LEFT JOIN (
                   SELECT sl.product_id, COUNT(ii.id) AS quantity
                   FROM stock_lots sl
                   LEFT JOIN inventory_items ii
                     ON ii.lot_id = sl.id AND ii.status = 'available'
                   GROUP BY sl.product_id
               ) ps ON ps.product_id = p.id"""
        )
        select_cols = "p.*, COALESCE(ps.quantity, 0) AS stock_qty"
        if trung_bay:
            joins.append(
                """LEFT JOIN product_attribute_values pav
                   ON pav.product_id = p.id AND pav.attribute_type = 'trung_bay'"""
            )
            conditions.append("pav.value = 'true'")

        where = " AND ".join(conditions)
        join_sql = "\n".join(joins)
        rows = conn.execute(
            f"SELECT {select_cols} FROM products p {join_sql} WHERE {where} ORDER BY p.category, p.name",
            params,
        ).fetchall()

        result = []
        for r in rows:
            prod = _enrich_product(conn, r)
            result.append(prod)
        return result


@router.get("/code/{code}")
def get_product_by_code(code: str):
    """Lấy sản phẩm theo mã code."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM products WHERE product_code = ?", (code,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
        prod = _enrich_product(conn, row)
        return prod


@router.get("/{product_id}")
def get_product(product_id: int):
    """Chi tiết sản phẩm."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")
        prod = _enrich_product(conn, row)
        return prod


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

        # Resolve product_code: auto-prefix from category if needed
        if product.product_code:
            prefix = get_category_prefix(conn, product.category)
            if "-" not in product.product_code:
                # Suffix-only provided — auto-prefix
                code = f"{prefix}-{product.product_code}" if prefix else product.product_code
            else:
                # Full code provided — validate prefix matches category
                if prefix and not product.product_code.startswith(f"{prefix}-"):
                    raise HTTPException(
                        status_code=422,
                        detail=f"Mã sản phẩm phải bắt đầu bằng '{prefix}-' cho danh mục này",
                    )
                code = product.product_code
            code_exists = conn.execute(
                "SELECT id FROM products WHERE product_code = ?",
                (code,),
            ).fetchone()
            if code_exists:
                raise HTTPException(
                    status_code=409,
                    detail=f"Mã sản phẩm '{code}' đã tồn tại",
                )
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
        return _enrich_product(conn, row)


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

        # Resolve effective category (new or current)
        effective_category = data.get("category", row["category"])

        # Auto-prefix suffix-only product_code
        if "product_code" in data and data["product_code"] and "-" not in data["product_code"]:
            prefix = get_category_prefix(conn, effective_category)
            if prefix:
                data["product_code"] = f"{prefix}-{data['product_code']}"

        # When category changes and no explicit product_code provided, update prefix
        if "category" in data and data["category"] != row["category"] and "product_code" not in data:
            new_prefix = get_category_prefix(conn, data["category"])
            current_code = row["product_code"] or ""
            if new_prefix and current_code and "-" in current_code:
                old_suffix = current_code.split("-", 1)[1]
                data["product_code"] = f"{new_prefix}-{old_suffix}"

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
        return _enrich_product(conn, row)


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

    data = await read_image_upload(file)

    try:
        hash_hex = save_photo(data, file.filename or "")
    except (UnidentifiedImageError, OSError, ValueError):
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
