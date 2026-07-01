"""Product price chip management API routes."""

from fastapi import APIRouter, HTTPException, Path
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.utils.time import now_utc


router = APIRouter(prefix="/api", tags=["product-price-chips"])


class PriceChipCreate(BaseModel):
    label: str
    price: float = 0
    position: int = 0


class PriceChipUpdate(BaseModel):
    label: str | None = None
    price: float | None = None
    position: int | None = None


def _ensure_product_exists(conn, product_id: int) -> None:
    row = conn.execute("SELECT 1 FROM products WHERE id = ?", (product_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")


def _ensure_chip_exists(conn, chip_id: int, product_id: int) -> None:
    row = conn.execute(
        "SELECT id FROM product_price_chips WHERE id = ? AND product_id = ?",
        (chip_id, product_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy mức giá")


def _chip_rows(conn, product_id: int) -> list[dict]:
    rows = conn.execute(
        "SELECT id, label, price, position FROM product_price_chips "
        "WHERE product_id = ? ORDER BY position, id",
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


def _chip_has_stock_or_history(conn, chip_id: int) -> bool:
    checks = [
        "SELECT 1 FROM stock_lots WHERE price_chip_id = ? LIMIT 1",
        """SELECT 1 FROM inventory_items ii
           JOIN stock_lots sl ON sl.id = ii.lot_id
           WHERE sl.price_chip_id = ? LIMIT 1""",
        "SELECT 1 FROM stock_movements WHERE price_chip_id = ? LIMIT 1",
        "SELECT 1 FROM order_items WHERE price_chip_id = ? LIMIT 1",
        "SELECT 1 FROM reconciliation_lines WHERE price_chip_id = ? LIMIT 1",
    ]
    for query in checks:
        if conn.execute(query, (chip_id,)).fetchone():
            return True
    return False


@router.get("/products/{product_id}/price-chips")
def list_product_price_chips(
    product_id: int = Path(ge=0, description="Product ID"),
):
    """Get all preset price chips for a product."""
    with get_db() as conn:
        _ensure_product_exists(conn, product_id)
        return _chip_rows(conn, product_id)


@router.post("/products/{product_id}/price-chips", status_code=201)
def create_product_price_chip(
    chip: PriceChipCreate,
    product_id: int = Path(ge=0, description="Product ID"),
):
    """Create a preset price chip for a product."""
    label = chip.label.strip()
    if not label:
        raise HTTPException(status_code=400, detail="Nhãn không được để trống")
    if chip.price < 0:
        raise HTTPException(status_code=400, detail="Giá không hợp lệ")

    with get_db() as conn:
        _ensure_product_exists(conn, product_id)
        cursor = conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (product_id, label, chip.price, chip.position, now_utc()),
        )
        row = conn.execute(
            "SELECT id, label, price, position FROM product_price_chips WHERE id = ?",
            (cursor.lastrowid,),
        ).fetchone()
        return {
            "id": row["id"],
            "label": row["label"],
            "price": row["price"],
            "position": row["position"],
        }


@router.patch("/products/{product_id}/price-chips/{chip_id}")
def update_product_price_chip(
    chip: PriceChipUpdate,
    product_id: int = Path(ge=0, description="Product ID"),
    chip_id: int = Path(ge=0, description="Price chip ID"),
):
    """Update a product preset price chip."""
    data = chip.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

    updates: list[str] = []
    values: list = []

    if "label" in data:
        label = data["label"].strip() if isinstance(data["label"], str) else ""
        if not label:
            raise HTTPException(status_code=400, detail="Nhãn không được để trống")
        updates.append("label = ?")
        values.append(label)

    if "price" in data:
        if data["price"] < 0:
            raise HTTPException(status_code=400, detail="Giá không hợp lệ")
        updates.append("price = ?")
        values.append(data["price"])

    if "position" in data:
        updates.append("position = ?")
        values.append(data["position"])

    with get_db() as conn:
        _ensure_product_exists(conn, product_id)
        _ensure_chip_exists(conn, chip_id, product_id)
        values.append(chip_id)
        conn.execute(
            f"UPDATE product_price_chips SET {', '.join(updates)} WHERE id = ?",
            values,
        )
        row = conn.execute(
            "SELECT id, label, price, position FROM product_price_chips WHERE id = ?",
            (chip_id,),
        ).fetchone()
        return {
            "id": row["id"],
            "label": row["label"],
            "price": row["price"],
            "position": row["position"],
        }


@router.delete("/products/{product_id}/price-chips/{chip_id}", status_code=204)
def delete_product_price_chip(
    product_id: int = Path(ge=0, description="Product ID"),
    chip_id: int = Path(ge=0, description="Price chip ID"),
):
    """Delete a preset price chip from a product."""
    with get_db() as conn:
        _ensure_product_exists(conn, product_id)
        _ensure_chip_exists(conn, chip_id, product_id)
        if _chip_has_stock_or_history(conn, chip_id):
            raise HTTPException(
                status_code=422,
                detail="Không thể xóa mức giá vì đã có tồn kho hoặc lịch sử liên quan",
            )
        conn.execute(
            "DELETE FROM product_price_chips WHERE id = ? AND product_id = ?",
            (chip_id, product_id),
        )
