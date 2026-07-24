"""Blanks API — phôi bánh CRUD, BOM mapping, stock, and demand endpoints.

Routes:
* ``GET    /api/blanks``                       — list blanks (FR1)
* ``POST   /api/blanks``                       — create blank (FR1)
* ``PATCH  /api/blanks/{blank_id}``            — update blank (FR1)
* ``DELETE /api/blanks/{blank_id}``            — delete blank (FR1)
* ``GET    /api/price-chips/{chip_id}/blanks`` — list BOM mappings (FR2)
* ``POST   /api/price-chips/{chip_id}/blanks`` — create BOM mapping (FR2)
* ``PATCH  /api/price-chips/{chip_id}/blanks/{bom_id}`` — update quantity (FR2)
* ``DELETE /api/price-chips/{chip_id}/blanks/{bom_id}`` — delete BOM mapping (FR2)
* ``GET    /api/blanks/stock``                 — current stock per blank (FR4)
* ``POST   /api/blanks/stock``                 — record production/usage (FR4, FR5)
* ``GET    /api/blanks/demand``                — demand vs stock per blank (FR3, FR6)

Demand calc: JOIN orders → order_items → product_blank_bom → blanks
aggregating BOM.quantity × order_items.quantity grouped by blank_id.
Orders with status ``delivered`` or ``cancelled`` are excluded. When an
order_item has no ``price_chip_id`` the BOM falls back to ``product_id``
(see FR2). ``shortage = max(0, demand - stock)`` (FR6).
"""

from typing import Optional

from fastapi import APIRouter, HTTPException, Path, Query
from pydantic import BaseModel, Field

from baker.db.connection import get_db
from baker.models.blank import Blank, BlankStock, BlankStockLog, ProductBlankBom
from baker.utils.time import now_utc


router = APIRouter(prefix="/api", tags=["blanks"])


# --- Pydantic request schemas -------------------------------------------------


class BlankCreate(BaseModel):
    name: str
    category: str = ""
    unit: str = ""
    notes: str = ""


class BlankUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[str] = None
    unit: Optional[str] = None
    notes: Optional[str] = None


class BomCreate(BaseModel):
    blankId: int
    quantity: float = Field(default=1.0, ge=0)


class BomUpdate(BaseModel):
    quantity: float = Field(default=1.0, ge=0)


class StockCreate(BaseModel):
    blankId: int
    quantity: float
    type: str  # "production" | "usage"
    producedDate: str = ""
    expiryDate: Optional[str] = None


# --- helpers ------------------------------------------------------------------


_EXCLUDED_ORDER_STATUSES = ("delivered", "cancelled")


def _ensure_blank_exists(conn, blank_id: int) -> Blank:
    row = conn.execute("SELECT * FROM blanks WHERE id = ?", (blank_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy phôi")
    return Blank.from_row(row)


def _ensure_chip_exists(conn, chip_id: int) -> None:
    row = conn.execute(
        "SELECT 1 FROM product_price_chips WHERE id = ?", (chip_id,)
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy mức giá")


def _ensure_bom_exists(conn, chip_id: int, bom_id: int) -> ProductBlankBom:
    row = conn.execute(
        "SELECT * FROM product_blank_bom WHERE id = ? AND price_chip_id = ?",
        (bom_id, chip_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy BOM mapping")
    return ProductBlankBom.from_row(row)


def _current_stock(conn, blank_id: int) -> float:
    """Aggregate net stock for a blank: production (+), usage (−)."""
    row = conn.execute(
        """SELECT
               COALESCE(SUM(CASE WHEN type = 'production' THEN quantity ELSE -quantity END), 0)
               AS net
           FROM blank_stock WHERE blank_id = ?""",
        (blank_id,),
    ).fetchone()
    return float(row["net"] or 0)


# --- Blank CRUD (FR1) ---------------------------------------------------------


@router.get("/blanks")
def list_blanks(category: Optional[str] = Query(None)):
    """List all blanks, optionally filtered by category."""
    with get_db() as conn:
        if category:
            rows = conn.execute(
                "SELECT * FROM blanks WHERE category = ? ORDER BY id", (category,)
            ).fetchall()
        else:
            rows = conn.execute("SELECT * FROM blanks ORDER BY id").fetchall()
        return [Blank.from_row(r).to_api_dict() for r in rows]


@router.post("/blanks", status_code=201)
def create_blank(body: BlankCreate):
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Tên phôi không được để trống")
    with get_db() as conn:
        blank = Blank(name=name, category=body.category, unit=body.unit, notes=body.notes)
        blank.save(conn)
        row = conn.execute("SELECT * FROM blanks WHERE id = ?", (blank.id,)).fetchone()
        return Blank.from_row(row).to_api_dict()


@router.patch("/blanks/{blank_id}")
def update_blank(body: BlankUpdate, blank_id: int = Path(ge=0)):
    with get_db() as conn:
        blank = _ensure_blank_exists(conn, blank_id)
        data = body.model_dump(exclude_unset=True)
        if not data:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")
        if "name" in data:
            name = (data["name"] or "").strip()
            if not name:
                raise HTTPException(status_code=400, detail="Tên phôi không được để trống")
            blank.name = name
        if "category" in data:
            blank.category = data["category"] or ""
        if "unit" in data:
            blank.unit = data["unit"] or ""
        if "notes" in data:
            blank.notes = data["notes"] or ""
        blank.update(conn)
        row = conn.execute("SELECT * FROM blanks WHERE id = ?", (blank_id,)).fetchone()
        return Blank.from_row(row).to_api_dict()


@router.delete("/blanks/{blank_id}", status_code=204)
def delete_blank(blank_id: int = Path(ge=0)):
    with get_db() as conn:
        _ensure_blank_exists(conn, blank_id)
        conn.execute("DELETE FROM blanks WHERE id = ?", (blank_id,))


# --- BOM CRUD via price_chip (FR2) -------------------------------------------


@router.get("/price-chips/{chip_id}/blanks")
def list_chip_bom(chip_id: int = Path(ge=0)):
    """List all BOM mappings for a price chip."""
    with get_db() as conn:
        _ensure_chip_exists(conn, chip_id)
        rows = conn.execute(
            "SELECT * FROM product_blank_bom WHERE price_chip_id = ? ORDER BY id",
            (chip_id,),
        ).fetchall()
        return [ProductBlankBom.from_row(r).to_api_dict() for r in rows]


@router.post("/price-chips/{chip_id}/blanks", status_code=201)
def create_chip_bom(body: BomCreate, chip_id: int = Path(ge=0)):
    with get_db() as conn:
        _ensure_chip_exists(conn, chip_id)
        _ensure_blank_exists(conn, body.blankId)
        # Resolve product_id from the price_chip so demand fallback to
        # product_id can still match this BOM row when an order_item has
        # no price_chip_id (FR2 fallback).
        chip_row = conn.execute(
            "SELECT product_id FROM product_price_chips WHERE id = ?", (chip_id,)
        ).fetchone()
        bom = ProductBlankBom(
            product_id=chip_row["product_id"],
            price_chip_id=chip_id,
            blank_id=body.blankId,
            quantity=body.quantity,
        )
        bom.save(conn)
        row = conn.execute(
            "SELECT * FROM product_blank_bom WHERE id = ?", (bom.id,)
        ).fetchone()
        return ProductBlankBom.from_row(row).to_api_dict()


@router.patch("/price-chips/{chip_id}/blanks/{bom_id}")
def update_chip_bom(
    body: BomUpdate,
    chip_id: int = Path(ge=0),
    bom_id: int = Path(ge=0),
):
    with get_db() as conn:
        bom = _ensure_bom_exists(conn, chip_id, bom_id)
        bom.quantity = body.quantity
        bom.update(conn)
        row = conn.execute(
            "SELECT * FROM product_blank_bom WHERE id = ?", (bom_id,)
        ).fetchone()
        return ProductBlankBom.from_row(row).to_api_dict()


@router.delete("/price-chips/{chip_id}/blanks/{bom_id}", status_code=204)
def delete_chip_bom(
    chip_id: int = Path(ge=0),
    bom_id: int = Path(ge=0),
):
    with get_db() as conn:
        _ensure_bom_exists(conn, chip_id, bom_id)
        conn.execute("DELETE FROM product_blank_bom WHERE id = ?", (bom_id,))


# --- Stock (FR4, FR5) --------------------------------------------------------


@router.get("/blanks/stock")
def list_stock():
    """Current net stock per blank across all production/usage lots."""
    with get_db() as conn:
        rows = conn.execute(
            """SELECT b.id AS blank_id, b.name, b.category, b.unit,
                      COALESCE(SUM(
                          CASE WHEN s.type = 'production' THEN s.quantity ELSE -s.quantity END
                      ), 0) AS net_stock
               FROM blanks b
               LEFT JOIN blank_stock s ON s.blank_id = b.id
               GROUP BY b.id
               ORDER BY b.id"""
        ).fetchall()
        return [
            {
                "blankId": r["blank_id"],
                "name": r["name"],
                "category": r["category"],
                "unit": r["unit"],
                "stock": float(r["net_stock"] or 0),
            }
            for r in rows
        ]


@router.post("/blanks/stock", status_code=201)
def record_stock(body: StockCreate):
    """Record a stock change: production (+) or usage (−).

    Writes a ``blank_stock`` row and a ``blank_stock_log`` audit entry
    (FR5). ``quantity`` is stored as a positive magnitude; the sign is
    derived from ``type`` (production = +, usage = −).
    """
    if body.type not in ("production", "usage"):
        raise HTTPException(
            status_code=400, detail="type phải là 'production' hoặc 'usage'"
        )
    if body.quantity == 0:
        raise HTTPException(status_code=400, detail="quantity phải khác 0")
    with get_db() as conn:
        _ensure_blank_exists(conn, body.blankId)
        stock = BlankStock(
            blank_id=body.blankId,
            quantity=abs(body.quantity),
            produced_date=body.producedDate,
            expiry_date=body.expiryDate,
            type=body.type,
        )
        stock.save(conn)
        change = abs(body.quantity) if body.type == "production" else -abs(body.quantity)
        log = BlankStockLog(
            blank_id=body.blankId,
            quantity_change=change,
            type=body.type,
            produced_date=body.producedDate or None,
            expiry_date=body.expiryDate,
        )
        log.save(conn)
        row = conn.execute(
            "SELECT * FROM blank_stock WHERE id = ?", (stock.id,)
        ).fetchone()
        return BlankStock.from_row(row).to_api_dict()


# --- Demand (FR3, FR6) -------------------------------------------------------


@router.get("/blanks/demand")
def list_demand():
    """Demand from pending orders compared to stock, per blank.

    For each blank, aggregates ``BOM.quantity × order_items.quantity``
    across pending orders (status not in delivered/cancelled). When an
    order_item has a ``price_chip_id`` the BOM is matched by
    ``price_chip_id``; otherwise the BOM is matched by ``product_id``
    (FR2 fallback). ``shortage = max(0, demand - stock)`` (FR6).
    """
    with get_db() as conn:
        rows = conn.execute(
            f"""
            SELECT b.id AS blank_id,
                   b.name,
                   b.category,
                   b.unit,
                   COALESCE(d.demand, 0) AS demand
            FROM blanks b
            LEFT JOIN (
                SELECT pb.blank_id AS blank_id,
                       SUM(pb.quantity * oi.quantity) AS demand
                FROM product_blank_bom pb
                JOIN order_items oi
                   ON (
                       (oi.price_chip_id IS NOT NULL
                        AND oi.price_chip_id = pb.price_chip_id)
                       OR
                       (oi.price_chip_id IS NULL
                        AND oi.product_id IS NOT NULL
                        AND oi.product_id != ''
                        AND pb.product_id IS NOT NULL
                        AND CAST(oi.product_id AS INTEGER) = pb.product_id)
                   )
                JOIN orders o ON o.id = oi.order_id
                WHERE o.status NOT IN ({",".join("?" * len(_EXCLUDED_ORDER_STATUSES))})
                GROUP BY pb.blank_id
            ) d ON d.blank_id = b.id
            ORDER BY b.id
            """,
            list(_EXCLUDED_ORDER_STATUSES),
        ).fetchall()

        # Stock lookup in a single pass to avoid N+1 queries (NFR2).
        stock_rows = conn.execute(
            """SELECT blank_id,
                      COALESCE(SUM(
                          CASE WHEN type = 'production' THEN quantity ELSE -quantity END
                      ), 0) AS net
               FROM blank_stock GROUP BY blank_id"""
        ).fetchall()
        stock_map = {r["blank_id"]: float(r["net"] or 0) for r in stock_rows}

        result = []
        for r in rows:
            demand = float(r["demand"] or 0)
            stock = stock_map.get(r["blank_id"], 0.0)
            shortage = max(0.0, demand - stock)
            result.append(
                {
                    "blankId": r["blank_id"],
                    "name": r["name"],
                    "category": r["category"],
                    "unit": r["unit"],
                    "demand": demand,
                    "stock": stock,
                    "shortage": shortage,
                }
            )
        return result