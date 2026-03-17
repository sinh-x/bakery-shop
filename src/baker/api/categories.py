"""Category CRUD API routes."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db


router = APIRouter(prefix="/api/categories", tags=["categories"])


class CategoryCreate(BaseModel):
    slug: str
    name: str
    code_prefix: str


def _row_to_dict(row) -> dict:
    return dict(row)


@router.get("")
def list_categories():
    """Danh sách categories."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM categories WHERE active = 1 ORDER BY slug"
        ).fetchall()
        return [_row_to_dict(r) for r in rows]


@router.post("", status_code=201)
def create_category(category: CategoryCreate):
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

        cursor = conn.execute(
            "INSERT INTO categories (slug, name, code_prefix) VALUES (?, ?, ?)",
            (category.slug, category.name, category.code_prefix),
        )
        new_id = cursor.lastrowid
        row = conn.execute(
            "SELECT * FROM categories WHERE id = ?", (new_id,)
        ).fetchone()
        return _row_to_dict(row)
