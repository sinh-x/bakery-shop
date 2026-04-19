"""Stock management API routes for trưng bày product inventory."""

from fastapi import APIRouter, HTTPException

from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.event import Event


router = APIRouter(prefix="/api", tags=["stock"])


# --- Pydantic models ---

class StockGetResponse(BaseModel):
    quantity: int


class RestockRequest(BaseModel):
    quantity: int
    note: str = ""


class WasteRequest(BaseModel):
    quantity: int
    reason: str = ""


class AdjustRequest(BaseModel):
    quantity: int
    reason: str = ""


class StockOverviewItem(BaseModel):
    product_id: int
    product_name: str
    category: str
    quantity: int


def _log_stock_movement(
    conn,
    product_id: int,
    movement_type: str,
    quantity: int,
    reason: str = "",
    reference_id: str = "",
):
    """Insert a stock movement record and log to events table."""
    conn.execute(
        """INSERT INTO stock_movements
           (product_id, movement_type, quantity, reason, reference_id)
           VALUES (?, ?, ?, ?, ?)""",
        (product_id, movement_type, quantity, reason, reference_id),
    )
    # Build product name for event summary
    product_row = conn.execute(
        "SELECT name FROM products WHERE id = ?", (product_id,)
    ).fetchone()
    product_name = product_row["name"] if product_row else f"product_id={product_id}"

    type_labels = {
        "restock": "Nhập hàng",
        "sale": "Bán hàng",
        "waste": "Hao hụt",
        "adjustment": "Điều chỉnh",
    }
    label = type_labels.get(movement_type, movement_type)
    sign = "+" if quantity >= 0 else ""
    summary = f"{label} {sign}{quantity} {product_name}"
    data = {
        "product_id": product_id,
        "product_name": product_name,
        "movement_type": movement_type,
        "quantity": quantity,
    }
    if reason:
        data["reason"] = reason
    if reference_id:
        data["reference_id"] = reference_id
    Event(summary=summary, type="inventory", data=data).save(conn)


@router.get("/products/{product_id}/stock", response_model=StockGetResponse)
def get_stock(product_id: int):
    """Get current stock quantity for a product."""
    with get_db() as conn:
        product = conn.execute(
            "SELECT id FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not product:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        row = conn.execute(
            "SELECT quantity FROM product_stock WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        quantity = row["quantity"] if row else 0
        return StockGetResponse(quantity=quantity)


@router.post("/products/{product_id}/stock/restock", status_code=200)
def restock_product(product_id: int, body: RestockRequest):
    """Increase stock for a product (restock)."""
    if body.quantity <= 0:
        raise HTTPException(status_code=422, detail="Số lượng phải lớn hơn 0")

    with get_db() as conn:
        product = conn.execute(
            "SELECT id, name FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not product:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        # Atomic upsert
        existing = conn.execute(
            "SELECT id, quantity FROM product_stock WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE product_stock SET quantity = quantity + ? WHERE product_id = ?",
                (body.quantity, product_id),
            )
        else:
            conn.execute(
                "INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)",
                (product_id, body.quantity),
            )

        _log_stock_movement(
            conn,
            product_id,
            "restock",
            body.quantity,
            reason=body.note,
        )

        new_qty = conn.execute(
            "SELECT quantity FROM product_stock WHERE product_id = ?",
            (product_id,),
        ).fetchone()["quantity"]

        return {"product_id": product_id, "quantity": new_qty}


@router.post("/products/{product_id}/stock/waste", status_code=200)
def waste_stock(product_id: int, body: WasteRequest):
    """Decrease stock for a product (waste/spoilage)."""
    if body.quantity <= 0:
        raise HTTPException(status_code=422, detail="Số lượng phải lớn hơn 0")
    if not body.reason.strip():
        raise HTTPException(status_code=422, detail="Lý do là bắt buộc khi ghi hao hụt")

    with get_db() as conn:
        product = conn.execute(
            "SELECT id FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not product:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        # Atomic decrement, clamp to 0
        existing = conn.execute(
            "SELECT id, quantity FROM product_stock WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        if existing:
            new_qty = max(0, existing["quantity"] - body.quantity)
            conn.execute(
                "UPDATE product_stock SET quantity = ? WHERE product_id = ?",
                (new_qty, product_id),
            )
        else:
            new_qty = 0
            conn.execute(
                "INSERT INTO product_stock (product_id, quantity) VALUES (?, 0)",
                (product_id,),
            )

        _log_stock_movement(
            conn,
            product_id,
            "waste",
            -body.quantity,
            reason=body.reason,
        )

        return {"product_id": product_id, "quantity": new_qty}


@router.post("/products/{product_id}/stock/adjust", status_code=200)
def adjust_stock(product_id: int, body: AdjustRequest):
    """Set exact stock quantity for a product (adjustment)."""
    if body.quantity < 0:
        raise HTTPException(status_code=422, detail="Số lượng không được âm")
    if not body.reason.strip():
        raise HTTPException(status_code=422, detail="Lý do là bắt buộc khi điều chỉnh")

    with get_db() as conn:
        product = conn.execute(
            "SELECT id FROM products WHERE id = ?", (product_id,)
        ).fetchone()
        if not product:
            raise HTTPException(status_code=404, detail="Không tìm thấy sản phẩm")

        old_row = conn.execute(
            "SELECT quantity FROM product_stock WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        old_qty = old_row["quantity"] if old_row else 0

        # Atomic upsert
        if old_row:
            conn.execute(
                "UPDATE product_stock SET quantity = ? WHERE product_id = ?",
                (body.quantity, product_id),
            )
        else:
            conn.execute(
                "INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)",
                (product_id, body.quantity),
            )

        delta = body.quantity - old_qty
        _log_stock_movement(
            conn,
            product_id,
            "adjustment",
            delta,
            reason=body.reason,
        )

        return {"product_id": product_id, "quantity": body.quantity}


@router.get("/stock/overview", response_model=list[StockOverviewItem])
def stock_overview():
    """List all trưng bày products with current stock quantity."""
    with get_db() as conn:
        rows = conn.execute(
            """SELECT p.id AS product_id, p.name AS product_name, p.category,
                      COALESCE(ps.quantity, 0) AS quantity
               FROM products p
               LEFT JOIN product_stock ps ON p.id = ps.product_id
               WHERE p.active = 1
                 AND EXISTS (
                     SELECT 1 FROM product_attribute_values pav
                     WHERE pav.product_id = p.id
                       AND pav.attribute_type = 'trung_bay'
                       AND pav.value = 'true'
                 )
               ORDER BY p.category, p.name""",
        ).fetchall()
        return [
            StockOverviewItem(
                product_id=r["product_id"],
                product_name=r["product_name"],
                category=r["category"],
                quantity=r["quantity"],
            )
            for r in rows
        ]
