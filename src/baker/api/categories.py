"""Category CRUD API routes."""

import re

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator

from baker.api.auth import RequireRole, record_audit_log
from baker.db.connection import get_db


router = APIRouter(prefix="/api/categories", tags=["categories"])


class CategoryCreate(BaseModel):
    slug: str
    name: str
    code_prefix: str
    icon: str = ""

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Tên danh mục không được để trống")
        return v

    @field_validator("code_prefix")
    @classmethod
    def code_prefix_format(cls, v: str) -> str:
        if not re.fullmatch(r"[A-Z]{2,4}", v):
            raise ValueError("Mã viết tắt phải 2-4 ký tự in hoa")
        return v


class CategoryUpdate(BaseModel):
    name: str | None = None
    code_prefix: str | None = None
    active: int | None = None
    icon: str | None = None

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("Tên danh mục không được để trống")
        return v

    @field_validator("code_prefix")
    @classmethod
    def code_prefix_format(cls, v: str | None) -> str | None:
        if v is not None and not re.fullmatch(r"[A-Z]{2,4}", v):
            raise ValueError("Mã viết tắt phải 2-4 ký tự in hoa")
        return v


class CategoryReorderItem(BaseModel):
    id: int


def _row_to_dict(row) -> dict:
    return dict(row)


@router.get("")
def list_categories(include_inactive: int = Query(0)):
    """Danh sách categories. include_inactive=1 trả về cả categories đã ẩn."""
    with get_db() as conn:
        if include_inactive:
            rows = conn.execute(
                "SELECT * FROM categories ORDER BY active DESC, position, slug"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM categories WHERE active = 1 ORDER BY position, slug"
            ).fetchall()
        return [_row_to_dict(r) for r in rows]


@router.post("", status_code=201)
def create_category(category: CategoryCreate, actor: str = Depends(RequireRole("admin"))):
    """Tạo category mới."""
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id FROM categories WHERE slug = ?", (category.slug,)
        ).fetchone()
        if existing:
            raise HTTPException(
                status_code=409,
                detail=f"Category '{category.slug}' đã tồn tại",
            )

        max_pos = conn.execute(
            "SELECT COALESCE(MAX(position), -1) FROM categories"
        ).fetchone()[0]

        cursor = conn.execute(
            "INSERT INTO categories (slug, name, code_prefix, icon, position) "
            "VALUES (?, ?, ?, ?, ?)",
            (category.slug, category.name, category.code_prefix, category.icon, max_pos + 1),
        )
        new_id = cursor.lastrowid
        record_audit_log(
            conn,
            actor,
            "create",
            "category",
            new_id,
            old_value=None,
            new_value={
                "slug": category.slug,
                "name": category.name,
                "code_prefix": category.code_prefix,
                "icon": category.icon,
            },
        )
        row = conn.execute(
            "SELECT * FROM categories WHERE id = ?", (new_id,)
        ).fetchone()
        return _row_to_dict(row)


@router.patch("/reorder")
def reorder_categories(items: list[CategoryReorderItem], actor: str = Depends(RequireRole("admin"))):
    """Cập nhật thứ tự categories. items là danh sách {id} theo thứ tự mới."""
    with get_db() as conn:
        for idx, item in enumerate(items):
            conn.execute(
                "UPDATE categories SET position = ? WHERE id = ?",
                (idx, item.id),
            )
        record_audit_log(
            conn,
            actor,
            "update",
            "category",
            "reorder",
            old_value=None,
            new_value={"ordered_ids": [i.id for i in items]},
        )
    return {"ok": True, "count": len(items)}


@router.patch("/{category_id}")
def update_category(category_id: int, update: CategoryUpdate, actor: str = Depends(RequireRole("admin"))):
    """Cập nhật category (name, code_prefix, active)."""
    with get_db() as conn:
        existing = conn.execute(
            "SELECT * FROM categories WHERE id = ?", (category_id,)
        ).fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Category không tồn tại")

        old_snapshot = _row_to_dict(existing)
        fields: list[str] = []
        values: list = []

        old_prefix = existing["code_prefix"]
        prefix_changed = (
            update.code_prefix is not None and update.code_prefix != old_prefix
        )

        if update.name is not None:
            fields.append("name = ?")
            values.append(update.name)
        if update.code_prefix is not None:
            fields.append("code_prefix = ?")
            values.append(update.code_prefix)
        if update.active is not None:
            fields.append("active = ?")
            values.append(update.active)
        if update.icon is not None:
            fields.append("icon = ?")
            values.append(update.icon)

        if not fields:
            return _row_to_dict(existing)

        values.append(category_id)
        conn.execute(
            f"UPDATE categories SET {', '.join(fields)} WHERE id = ?", values
        )

        # Cascade prefix change to ALL products in this category (including inactive)
        if prefix_changed:
            # Abort if the new prefix is already used by another category's products
            conflict = conn.execute(
                "SELECT product_code FROM products "
                "WHERE category != ? AND product_code LIKE ?",
                (existing["slug"], f"{update.code_prefix}-%"),
            ).fetchone()
            if conflict:
                raise HTTPException(
                    status_code=409,
                    detail=f"Mã viết tắt '{update.code_prefix}' đã được dùng bởi danh mục khác",
                )
            conn.execute(
                "UPDATE products "
                "SET product_code = ? || substr(product_code, length(?)+1) "
                "WHERE category = ? AND product_code LIKE ?",
                (update.code_prefix, old_prefix, existing["slug"], f"{old_prefix}-%"),
            )

        new_snapshot = update.model_dump(exclude_unset=True)
        record_audit_log(
            conn,
            actor,
            "update",
            "category",
            category_id,
            old_value=old_snapshot,
            new_value=new_snapshot,
        )

        row = conn.execute(
            "SELECT * FROM categories WHERE id = ?", (category_id,)
        ).fetchone()
        return _row_to_dict(row)
