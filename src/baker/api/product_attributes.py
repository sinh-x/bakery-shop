"""Product attribute type and value management API routes."""

import json
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db

router = APIRouter(prefix="/api", tags=["product-attributes"])


# --- Pydantic models ---

class AttributeTypeCreate(BaseModel):
    attribute_type: str
    label_vi: str
    value_type: str = "text"
    applicable_categories: list[str] = []
    default_value: str = ""
    sort_order: int = 0


class AttributeTypeUpdate(BaseModel):
    label_vi: Optional[str] = None
    value_type: Optional[str] = None
    applicable_categories: Optional[list[str]] = None
    default_value: Optional[str] = None
    sort_order: Optional[int] = None
    active: Optional[int] = None


class AttributeTypeResponse(BaseModel):
    attribute_type: str
    label_vi: str
    value_type: str
    applicable_categories: list[str]
    default_value: str
    sort_order: int
    active: int


class ProductAttributeValueSet(BaseModel):
    attribute_type: str
    value: str


class ProductAttributeValueResponse(BaseModel):
    attribute_type: str
    value: str
    label_vi: Optional[str] = None


# --- Helpers ---

def _parse_applicable_categories(cats_json: str) -> list[str]:
    try:
        return json.loads(cats_json) if cats_json else []
    except (json.JSONDecodeError, TypeError):
        return []


# --- Attribute Type CRUD (system-level) ---

@router.get("/product-attributes")
def list_attribute_types(category: Optional[str] = None):
    """List all active attribute types, optionally filtered by category applicability."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM product_attributes WHERE active = 1 ORDER BY sort_order, attribute_type"
        ).fetchall()

        results = []
        for row in rows:
            cats = _parse_applicable_categories(row["applicable_categories"])
            if category and cats and category not in cats:
                continue
            results.append({
                "attribute_type": row["attribute_type"],
                "label_vi": row["label_vi"],
                "value_type": row["value_type"],
                "applicable_categories": cats,
                "default_value": row["default_value"],
                "sort_order": row["sort_order"],
                "active": row["active"],
            })
        return results


@router.post("/product-attributes", status_code=201)
def create_attribute_type(body: AttributeTypeCreate):
    """Create a new attribute type (system-level)."""
    with get_db() as conn:
        existing = conn.execute(
            "SELECT 1 FROM product_attributes WHERE attribute_type = ?",
            (body.attribute_type,),
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail=f"Attribute type '{body.attribute_type}' already exists")

        cats_json = json.dumps(body.applicable_categories)
        cursor = conn.execute(
            """INSERT INTO product_attributes
               (attribute_type, label_vi, value_type, applicable_categories, default_value, sort_order)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                body.attribute_type,
                body.label_vi,
                body.value_type,
                cats_json,
                body.default_value,
                body.sort_order,
            ),
        )
        new_type = conn.execute(
            "SELECT * FROM product_attributes WHERE id = ?", (cursor.lastrowid,)
        ).fetchone()
        return {
            "attribute_type": new_type["attribute_type"],
            "label_vi": new_type["label_vi"],
            "value_type": new_type["value_type"],
            "applicable_categories": _parse_applicable_categories(new_type["applicable_categories"]),
            "default_value": new_type["default_value"],
            "sort_order": new_type["sort_order"],
            "active": new_type["active"],
        }


@router.patch("/product-attributes/{attribute_type}")
def update_attribute_type(attribute_type: str, body: AttributeTypeUpdate):
    """Update an attribute type (system-level)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM product_attributes WHERE attribute_type = ?",
            (attribute_type,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy attribute type")

        updates = []
        params = []

        if body.label_vi is not None:
            updates.append("label_vi = ?")
            params.append(body.label_vi)
        if body.value_type is not None:
            updates.append("value_type = ?")
            params.append(body.value_type)
        if body.applicable_categories is not None:
            updates.append("applicable_categories = ?")
            params.append(json.dumps(body.applicable_categories))
        if body.default_value is not None:
            effective_value_type = body.value_type if body.value_type is not None else row["value_type"]
            if effective_value_type == "enum" and body.default_value != "":
                try:
                    option_id_int = int(body.default_value)
                except ValueError:
                    raise HTTPException(
                        status_code=422,
                        detail="default_value phải là id của tuỳ chọn (số nguyên)",
                    )
                option_row = conn.execute(
                    "SELECT id FROM product_attribute_options "
                    "WHERE id = ? AND attribute_id = ? AND active = 1",
                    (option_id_int, row["id"]),
                ).fetchone()
                if not option_row:
                    raise HTTPException(
                        status_code=422,
                        detail="default_value không hợp lệ: tuỳ chọn không tồn tại hoặc không thuộc attribute này",
                    )
            updates.append("default_value = ?")
            params.append(body.default_value)
        if body.sort_order is not None:
            updates.append("sort_order = ?")
            params.append(body.sort_order)
        if body.active is not None:
            updates.append("active = ?")
            params.append(body.active)

        if not updates:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        params.append(attribute_type)
        conn.execute(
            f"UPDATE product_attributes SET {', '.join(updates)} WHERE attribute_type = ?",
            params,
        )
        updated = conn.execute(
            "SELECT * FROM product_attributes WHERE attribute_type = ?",
            (attribute_type,),
        ).fetchone()
        return {
            "attribute_type": updated["attribute_type"],
            "label_vi": updated["label_vi"],
            "value_type": updated["value_type"],
            "applicable_categories": _parse_applicable_categories(updated["applicable_categories"]),
            "default_value": updated["default_value"],
            "sort_order": updated["sort_order"],
            "active": updated["active"],
        }


@router.delete("/product-attributes/{attribute_type}", status_code=204)
def deactivate_attribute_type(attribute_type: str):
    """Soft-delete an attribute type by setting active=0."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT 1 FROM product_attributes WHERE attribute_type = ?",
            (attribute_type,),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy attribute type")
        conn.execute(
            "UPDATE product_attributes SET active = 0 WHERE attribute_type = ?",
            (attribute_type,),
        )


# --- Product Attribute Value CRUD ---

@router.get("/products/{product_id}/attributes")
def get_product_attributes(product_id: int):
    """Get all attribute values for a specific product (per-product defaults)."""
    with get_db() as conn:
        product = conn.execute(
            "SELECT id, category FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not product:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        # Get applicable attribute types for this product's category
        applicable_types = conn.execute(
            """SELECT attribute_type, label_vi, value_type, applicable_categories,
                      default_value, sort_order
               FROM product_attributes
               WHERE active = 1
               ORDER BY sort_order""",
        ).fetchall()

        # Get existing values for this product
        existing = conn.execute(
            "SELECT attribute_type, value FROM product_attribute_values WHERE product_id = ?",
            (product_id,),
        ).fetchall()
        existing_map = {r["attribute_type"]: r["value"] for r in existing}

        result = {}
        product_category = product["category"]
        for row in applicable_types:
            cats = _parse_applicable_categories(row["applicable_categories"])
            if cats and product_category not in cats:
                continue
            attr_type = row["attribute_type"]
            result[attr_type] = {
                "attribute_type": attr_type,
                "value": existing_map.get(attr_type, row["default_value"]),
                "label_vi": row["label_vi"],
            }
        return result


@router.post("/products/{product_id}/attributes", status_code=200)
def set_product_attribute(product_id: int, body: ProductAttributeValueSet):
    """Set or update an attribute value for a specific product."""
    with get_db() as conn:
        product = conn.execute(
            "SELECT id FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not product:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        # Verify attribute type exists
        attr_type_row = conn.execute(
            "SELECT 1 FROM product_attributes WHERE attribute_type = ? AND active = 1",
            (body.attribute_type,),
        ).fetchone()
        if not attr_type_row:
            raise HTTPException(status_code=404, detail="Không tìm thấy attribute type")

        conn.execute(
            """INSERT INTO product_attribute_values (product_id, attribute_type, value)
               VALUES (?, ?, ?)
               ON CONFLICT(product_id, attribute_type) DO UPDATE SET value = excluded.value""",
            (product_id, body.attribute_type, body.value),
        )
        return {"attribute_type": body.attribute_type, "value": body.value}


@router.delete("/products/{product_id}/attributes/{attribute_type}", status_code=204)
def delete_product_attribute(product_id: int, attribute_type: str):
    """Remove a per-product attribute value (reverts to default)."""
    with get_db() as conn:
        conn.execute(
            "DELETE FROM product_attribute_values WHERE product_id = ? AND attribute_type = ?",
            (product_id, attribute_type),
        )
