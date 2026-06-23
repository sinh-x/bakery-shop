"""Stock management API routes for trưng bày product inventory."""

from fastapi import APIRouter, HTTPException

from pydantic import BaseModel, Field

from baker.api.inventory_fifo import (
    available_quantity,
    consume_fifo_items,
    create_lot_with_items,
    normalize_price_value,
    resolve_price_bucket_option,
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
    normalized_price: int | None = None
    price_chip_id: int | None = None


class WasteRequest(BaseModel):
    quantity: int
    reason: str = ""
    normalized_price: int | None = None
    price_chip_id: int | None = None


class AdjustRequest(BaseModel):
    quantity: int
    reason: str = ""
    normalized_price: int | None = None
    price_chip_id: int | None = None


class StockOverviewChipItem(BaseModel):
    normalized_price: int
    price_chip_id: int | None
    quantity: int
    chip_labels: list[str] = Field(default_factory=list)
    source_chip_ids: list[int] = Field(default_factory=list)
    chip_label: str | None = None


class StockOverviewItem(BaseModel):
    product_id: int
    product_name: str
    category: str
    quantity: int
    base_price: float | None = None
    per_chip: list[StockOverviewChipItem]


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

        chip_id, normalized_price = resolve_price_bucket_option(
            conn,
            product_id,
            body.normalized_price,
            body.price_chip_id,
        )
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
            "normalized_price": normalized_price,
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

        chip_id, normalized_price = resolve_price_bucket_option(
            conn,
            product_id,
            body.normalized_price,
            body.price_chip_id,
        )

        movement_id = _log_stock_movement(
            conn,
            product_id,
            "waste",
            -body.quantity,
            reason=body.reason,
            price_chip_id=chip_id,
        )
        consume_fifo_items(conn, product_id, chip_id, body.quantity, movement_id)

        from baker.api.accounts import _sync_waste_cogs_journal

        _sync_waste_cogs_journal(conn, product_id, movement_id, body.quantity)

        option_qty = available_quantity(conn, product_id, chip_id)

        return {
            "product_id": product_id,
            "normalized_price": normalized_price,
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

        chip_id, normalized_price = resolve_price_bucket_option(
            conn,
            product_id,
            body.normalized_price,
            body.price_chip_id,
        )
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
            "normalized_price": normalized_price,
            "price_chip_id": chip_id,
            "quantity": available_quantity(conn, product_id, chip_id),
        }


@router.get("/stock/overview", response_model=list[StockOverviewItem])
def stock_overview():
    """List all trưng bày products with current stock quantity and configured price chips."""
    with get_db() as conn:
        # Get all trưng bày products
        products = conn.execute(
            """SELECT p.id, p.name, p.category, p.base_price
               FROM products p
               WHERE p.active = 1
                 AND EXISTS (
                     SELECT 1 FROM product_attribute_values pav
                    WHERE pav.product_id = p.id
                      AND pav.attribute_type = 'trung_bay'
                       AND pav.value = 'true'
                 )
               ORDER BY p.category, p.name""",
        ).fetchall()

        # Get per-chip stock quantities from stock_lots + inventory_items
        stock_rows = conn.execute(
            """SELECT sl.product_id, sl.price_chip_id, COUNT(ii.id) AS quantity
               FROM stock_lots sl
               LEFT JOIN inventory_items ii ON ii.lot_id = sl.id AND ii.status = 'available'
               GROUP BY sl.product_id, sl.price_chip_id""",
        ).fetchall()
        stock_map: dict[tuple[int, int | None], int] = {}
        for sr in stock_rows:
            stock_map[(sr["product_id"], sr["price_chip_id"])] = int(sr["quantity"] or 0)

        # Get all configured price chips for these products
        all_chips = conn.execute(
            """SELECT pc.product_id, pc.id AS chip_id, pc.label, pc.price, pc.position
               FROM product_price_chips pc
               JOIN products p ON p.id = pc.product_id
               WHERE p.active = 1
                 AND EXISTS (
                     SELECT 1 FROM product_attribute_values pav
                    WHERE pav.product_id = p.id
                      AND pav.attribute_type = 'trung_bay'
                       AND pav.value = 'true'
                 )
               ORDER BY pc.product_id, pc.position, pc.id""",
        ).fetchall()

        chips_map: dict[int, list[dict]] = {}
        for c in all_chips:
            chips_map.setdefault(c["product_id"], []).append(c)

        result: list[StockOverviewItem] = []
        for p in products:
            pid = p["id"]
            buckets: dict[int, dict] = {}

            base_price = normalize_price_value(p["base_price"])
            base_qty = stock_map.get((pid, None), 0)
            buckets[base_price] = {
                "normalized_price": base_price,
                "price_chip_id": None,
                "quantity": base_qty,
                "chip_labels": ["Giá gốc"],
                "source_chip_ids": [],
            }

            for c in chips_map.get(pid, []):
                qty = stock_map.get((pid, c["chip_id"]), 0)
                normalized_price = normalize_price_value(c["price"])
                bucket = buckets.get(normalized_price)
                if bucket is None:
                    bucket = {
                        "normalized_price": normalized_price,
                        "price_chip_id": c["chip_id"],
                        "quantity": 0,
                        "chip_labels": [],
                        "source_chip_ids": [],
                    }
                    buckets[normalized_price] = bucket
                bucket["quantity"] += qty
                bucket["chip_labels"].append(c["label"])
                bucket["source_chip_ids"].append(c["chip_id"])

            chips = [
                StockOverviewChipItem(
                    normalized_price=b["normalized_price"],
                    price_chip_id=b["price_chip_id"],
                    quantity=b["quantity"],
                    chip_labels=b["chip_labels"],
                    source_chip_ids=b["source_chip_ids"],
                    chip_label=", ".join(b["chip_labels"]) if b["chip_labels"] else None,
                )
                for b in sorted(buckets.values(), key=lambda x: x["normalized_price"])
            ]
            total_qty = sum(item.quantity for item in chips)

            result.append(StockOverviewItem(
                product_id=pid,
                product_name=p["name"],
                category=p["category"],
                quantity=total_qty,
                base_price=p["base_price"],
                per_chip=chips,
            ))

        return result
