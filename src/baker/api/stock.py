"""Stock management API routes for trưng bày product inventory."""

from fastapi import APIRouter, HTTPException

from pydantic import BaseModel

from baker.api.inventory_fifo import (
    available_quantity,
    consume_fifo_items,
    create_lot_with_items,
    normalize_price_chip,
)
from baker.db.connection import get_db
from baker.models.event import Event


router = APIRouter(prefix="/api", tags=["stock"])


# --- Pydantic models ---

class StockGetResponse(BaseModel):
    quantity: int


class RestockRequest(BaseModel):
    quantity: int
    note: str = ""
    price_chip_id: int | None = None


class WasteRequest(BaseModel):
    quantity: int
    reason: str = ""
    price_chip_id: int | None = None


class AdjustRequest(BaseModel):
    quantity: int
    reason: str = ""
    price_chip_id: int | None = None


class StockOverviewChipItem(BaseModel):
    price_chip_id: int | None
    quantity: int


class StockOverviewItem(BaseModel):
    product_id: int
    product_name: str
    category: str
    quantity: int
    per_chip: list[StockOverviewChipItem]


def _upsert_stock(conn, product_id: int, new_qty: int):
    """Backward-compatible stock setter for base-price option."""
    old_qty = available_quantity(conn, product_id, None)
    delta = new_qty - old_qty
    if delta > 0:
        create_lot_with_items(conn, product_id, None, delta)
    elif delta < 0:
        movement_id = _log_stock_movement(
            conn,
            product_id,
            "adjustment",
            delta,
            reason="reconciliation-sync",
            price_chip_id=None,
        )
        consume_fifo_items(conn, product_id, None, -delta, movement_id)


def _log_stock_movement(
    conn,
    product_id: int,
    movement_type: str,
    quantity: int,
    reason: str = "",
    reference_id: str = "",
    price_chip_id: int | None = None,
    lot_id: int | None = None,
):
    """Insert a stock movement record and log to events table."""
    cursor = conn.execute(
        """INSERT INTO stock_movements
           (product_id, movement_type, quantity, reason, reference_id, price_chip_id, lot_id)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (product_id, movement_type, quantity, reason, reference_id, price_chip_id, lot_id),
    )
    movement_id = cursor.lastrowid
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
    if price_chip_id is not None:
        data["price_chip_id"] = price_chip_id
    if lot_id is not None:
        data["lot_id"] = lot_id
    Event(summary=summary, type="inventory", data=data).save(conn)
    return movement_id


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
            """SELECT COUNT(*) AS qty
               FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = ? AND ii.status = 'available'""",
            (product_id,),
        ).fetchone()
        quantity = int(row["qty"] if row else 0)
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

        chip_id = normalize_price_chip(conn, product_id, body.price_chip_id)
        lot_id = create_lot_with_items(conn, product_id, chip_id, body.quantity)

        _log_stock_movement(
            conn,
            product_id,
            "restock",
            body.quantity,
            reason=body.note,
            price_chip_id=chip_id,
            lot_id=lot_id,
        )

        option_qty = available_quantity(conn, product_id, chip_id)
        total_qty = conn.execute(
            """SELECT COUNT(*) AS qty
               FROM inventory_items ii
               JOIN stock_lots sl ON sl.id = ii.lot_id
               WHERE sl.product_id = ? AND ii.status = 'available'""",
            (product_id,),
        ).fetchone()["qty"]

        return {
            "product_id": product_id,
            "price_chip_id": chip_id,
            "quantity": int(total_qty),
            "option_quantity": option_qty,
        }


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

        chip_id = normalize_price_chip(conn, product_id, body.price_chip_id)

        movement_id = _log_stock_movement(
            conn,
            product_id,
            "waste",
            -body.quantity,
            reason=body.reason,
            price_chip_id=chip_id,
        )
        consume_fifo_items(conn, product_id, chip_id, body.quantity, movement_id)

        option_qty = available_quantity(conn, product_id, chip_id)

        return {
            "product_id": product_id,
            "price_chip_id": chip_id,
            "quantity": option_qty,
        }


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

        chip_id = normalize_price_chip(conn, product_id, body.price_chip_id)
        old_qty = available_quantity(conn, product_id, chip_id)
        delta = body.quantity - old_qty
        if delta > 0:
            lot_id = create_lot_with_items(conn, product_id, chip_id, delta)
        else:
            lot_id = None

        movement_id = _log_stock_movement(
            conn,
            product_id,
            "adjustment",
            delta,
            reason=body.reason,
            price_chip_id=chip_id,
            lot_id=lot_id,
        )
        if delta < 0:
            consume_fifo_items(conn, product_id, chip_id, -delta, movement_id)

        return {
            "product_id": product_id,
            "price_chip_id": chip_id,
            "quantity": available_quantity(conn, product_id, chip_id),
        }


@router.get("/stock/overview", response_model=list[StockOverviewItem])
def stock_overview():
    """List all trưng bày products with current stock quantity."""
    with get_db() as conn:
        rows = conn.execute(
            """SELECT p.id AS product_id,
                      p.name AS product_name,
                      p.category,
                      sl.price_chip_id,
                      COUNT(ii.id) AS quantity
               FROM products p
               LEFT JOIN stock_lots sl ON p.id = sl.product_id
               LEFT JOIN inventory_items ii ON ii.lot_id = sl.id AND ii.status = 'available'
               WHERE p.active = 1
                  AND EXISTS (
                      SELECT 1 FROM product_attribute_values pav
                     WHERE pav.product_id = p.id
                       AND pav.attribute_type = 'trung_bay'
                        AND pav.value = 'true'
                  )
               GROUP BY p.id, p.name, p.category, sl.price_chip_id
               ORDER BY p.category, p.name, sl.price_chip_id""",
        ).fetchall()

        grouped: dict[int, StockOverviewItem] = {}
        for row in rows:
            pid = row["product_id"]
            if pid not in grouped:
                grouped[pid] = StockOverviewItem(
                    product_id=pid,
                    product_name=row["product_name"],
                    category=row["category"],
                    quantity=0,
                    per_chip=[],
                )
            qty = int(row["quantity"] or 0)
            grouped[pid].quantity += qty
            grouped[pid].per_chip.append(
                StockOverviewChipItem(
                    price_chip_id=row["price_chip_id"],
                    quantity=qty,
                )
            )

        return list(grouped.values())
