"""Product attribute option (enum value) management API routes."""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Path
from pydantic import BaseModel

from baker.api.auth import RequireRole
from baker.db.connection import get_db


router = APIRouter(prefix="/api", tags=["product-attribute-options"])


class OptionCreate(BaseModel):
    value_vi: str
    sort_order: Optional[int] = None
    active: Optional[int] = 1


class OptionUpdate(BaseModel):
    value_vi: Optional[str] = None
    sort_order: Optional[int] = None
    active: Optional[int] = None


class ReorderBody(BaseModel):
    ordered_ids: list[int]


def _option_row(row) -> dict:
    return {
        "id": row["id"],
        "attribute_id": row["attribute_id"],
        "value_vi": row["value_vi"],
        "sort_order": row["sort_order"],
        "active": row["active"],
    }


def _require_enum_attribute(conn, attribute_type: str):
    row = conn.execute(
        "SELECT id, value_type FROM product_attributes WHERE attribute_type = ? AND active = 1",
        (attribute_type,),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy attribute type")
    if row["value_type"] != "enum":
        raise HTTPException(
            status_code=409,
            detail=f"Attribute type '{attribute_type}' không phải dạng enum",
        )
    return row["id"]


def _require_option(conn, option_id: int):
    row = conn.execute(
        "SELECT id, attribute_id, value_vi, sort_order, active "
        "FROM product_attribute_options WHERE id = ?",
        (option_id,),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy tuỳ chọn")
    return row


@router.get("/product-attributes/{attribute_type}/options")
def list_options(
    attribute_type: str,
    active: Optional[int] = None,
):
    """List options for an enum attribute, ordered by sort_order then id."""
    with get_db() as conn:
        attribute_id = _require_enum_attribute(conn, attribute_type)

        sql = (
            "SELECT id, attribute_id, value_vi, sort_order, active "
            "FROM product_attribute_options WHERE attribute_id = ?"
        )
        params: list = [attribute_id]
        if active is not None:
            sql += " AND active = ?"
            params.append(active)
        sql += " ORDER BY sort_order, id"

        rows = conn.execute(sql, params).fetchall()
        return [_option_row(r) for r in rows]


@router.post("/product-attributes/{attribute_type}/options", status_code=201)
def create_option(
    body: OptionCreate,
    attribute_type: str,
    actor: str = Depends(RequireRole("admin")),
):
    """Create a new option for an enum attribute."""
    value_vi = body.value_vi.strip() if isinstance(body.value_vi, str) else ""
    if not value_vi:
        raise HTTPException(status_code=400, detail="Giá trị không được để trống")

    with get_db() as conn:
        attribute_id = _require_enum_attribute(conn, attribute_type)

        if body.sort_order is None:
            max_row = conn.execute(
                "SELECT COALESCE(MAX(sort_order), 0) AS m FROM product_attribute_options "
                "WHERE attribute_id = ?",
                (attribute_id,),
            ).fetchone()
            sort_order = (max_row["m"] or 0) + 1
        else:
            sort_order = body.sort_order

        active = body.active if body.active is not None else 1

        cursor = conn.execute(
            "INSERT INTO product_attribute_options "
            "(attribute_id, value_vi, sort_order, active) VALUES (?, ?, ?, ?)",
            (attribute_id, value_vi, sort_order, active),
        )
        row = conn.execute(
            "SELECT id, attribute_id, value_vi, sort_order, active "
            "FROM product_attribute_options WHERE id = ?",
            (cursor.lastrowid,),
        ).fetchone()
        return _option_row(row)


@router.patch("/product-attribute-options/{option_id}")
def update_option(
    body: OptionUpdate,
    option_id: int = Path(ge=0, description="Option ID"),
    actor: str = Depends(RequireRole("admin")),
):
    """Update an option's value_vi, sort_order, or active flag."""
    data = body.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

    updates: list[str] = []
    values: list = []

    if "value_vi" in data:
        value_vi = data["value_vi"].strip() if isinstance(data["value_vi"], str) else ""
        if not value_vi:
            raise HTTPException(status_code=400, detail="Giá trị không được để trống")
        updates.append("value_vi = ?")
        values.append(value_vi)

    if "sort_order" in data:
        updates.append("sort_order = ?")
        values.append(data["sort_order"])

    if "active" in data:
        updates.append("active = ?")
        values.append(1 if data["active"] else 0)

    with get_db() as conn:
        _require_option(conn, option_id)
        values.append(option_id)
        conn.execute(
            f"UPDATE product_attribute_options SET {', '.join(updates)} WHERE id = ?",
            values,
        )
        row = conn.execute(
            "SELECT id, attribute_id, value_vi, sort_order, active "
            "FROM product_attribute_options WHERE id = ?",
            (option_id,),
        ).fetchone()
        return _option_row(row)


@router.delete("/product-attribute-options/{option_id}", status_code=204)
def delete_option(
    option_id: int = Path(ge=0, description="Option ID"),
    actor: str = Depends(RequireRole("admin")),
):
    """Soft-delete an option by setting active=0 (preserves value_vi for historical orders)."""
    with get_db() as conn:
        _require_option(conn, option_id)
        conn.execute(
            "UPDATE product_attribute_options SET active = 0 WHERE id = ?",
            (option_id,),
        )


@router.post("/product-attributes/{attribute_type}/options/reorder")
def reorder_options(
    body: ReorderBody,
    attribute_type: str,
    actor: str = Depends(RequireRole("admin")),
):
    """Bulk-reorder options for an enum attribute by reassigning sort_order to list position."""
    with get_db() as conn:
        attribute_id = _require_enum_attribute(conn, attribute_type)

        rows = conn.execute(
            "SELECT id FROM product_attribute_options WHERE attribute_id = ?",
            (attribute_id,),
        ).fetchall()
        existing_ids = {r["id"] for r in rows}
        requested_ids = set(body.ordered_ids)

        unknown = requested_ids - existing_ids
        if unknown:
            raise HTTPException(
                status_code=422,
                detail=f"Tuỳ chọn không thuộc attribute này: {sorted(unknown)}",
            )

        for position, option_id in enumerate(body.ordered_ids):
            conn.execute(
                "UPDATE product_attribute_options SET sort_order = ? WHERE id = ?",
                (position, option_id),
            )

        result_rows = conn.execute(
            "SELECT id, attribute_id, value_vi, sort_order, active "
            "FROM product_attribute_options WHERE attribute_id = ? "
            "ORDER BY sort_order, id",
            (attribute_id,),
        ).fetchall()
        return [_option_row(r) for r in result_rows]
