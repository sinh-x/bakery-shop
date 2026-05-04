"""Reconciliation API routes for current-day stock counting."""

from datetime import date

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db


router = APIRouter(prefix="/api/reconciliations", tags=["reconciliations"])


class ReconciliationLineIn(BaseModel):
    product_id: int
    expected_qty: int
    counted_qty: int
    sale_qty: int = 0
    waste_qty: int = 0
    manual_unit_price: float | None = None


class ReconciliationSubmitIn(BaseModel):
    staff_name: str
    payment_method: str | None = None
    waste_reason: str | None = None
    lines: list[ReconciliationLineIn]


def _load_display_products(conn) -> list[dict]:
    rows = conn.execute(
        """SELECT p.id, p.name, p.category, p.base_price,
                  COALESCE(ps.quantity, 0) AS expected_qty
           FROM products p
           LEFT JOIN product_stock ps ON ps.product_id = p.id
           WHERE p.active = 1
             AND EXISTS (
                 SELECT 1 FROM product_attribute_values pav
                 WHERE pav.product_id = p.id
                   AND pav.attribute_type = 'trung_bay'
                   AND pav.value = 'true'
             )
           ORDER BY p.category, p.name"""
    ).fetchall()

    product_ids = [row["id"] for row in rows]
    chips_map: dict[int, list[dict]] = {pid: [] for pid in product_ids}
    if product_ids:
        placeholders = ",".join("?" * len(product_ids))
        chip_rows = conn.execute(
            "SELECT id, product_id, label, price, position "
            f"FROM product_price_chips WHERE product_id IN ({placeholders}) "
            "ORDER BY product_id, position, id",
            product_ids,
        ).fetchall()
        for chip in chip_rows:
            chips_map[chip["product_id"]].append(
                {
                    "id": chip["id"],
                    "label": chip["label"],
                    "price": chip["price"],
                    "position": chip["position"],
                }
            )

    return [
        {
            "product_id": row["id"],
            "name": row["name"],
            "category": row["category"],
            "expected_qty": row["expected_qty"],
            "base_price": row["base_price"],
            "price_chips": chips_map.get(row["id"], []),
        }
        for row in rows
    ]


def _validate_submit(payload: ReconciliationSubmitIn):
    if not payload.staff_name.strip():
        raise HTTPException(status_code=422, detail="Vui lòng chọn tên nhân viên")
    if not payload.lines:
        raise HTTPException(status_code=422, detail="Danh sách sản phẩm không được để trống")

    has_sale = False
    has_waste = False

    for line in payload.lines:
        if line.expected_qty < 0 or line.counted_qty < 0:
            raise HTTPException(status_code=422, detail="Số lượng tồn không được âm")
        if line.sale_qty < 0 or line.waste_qty < 0:
            raise HTTPException(status_code=422, detail="Số lượng bán và hao hụt không được âm")

        missing_qty = line.expected_qty - line.counted_qty
        if missing_qty < 0:
            raise HTTPException(status_code=422, detail="Số đếm thực tế không được lớn hơn số tồn dự kiến")
        if missing_qty > 0 and line.sale_qty + line.waste_qty != missing_qty:
            raise HTTPException(status_code=422, detail="Sản phẩm thiếu phải tách đúng: bán + hao hụt = số thiếu")
        if missing_qty == 0 and (line.sale_qty > 0 or line.waste_qty > 0):
            raise HTTPException(status_code=422, detail="Sản phẩm không thiếu thì không được nhập bán hoặc hao hụt")

        if line.sale_qty > 0:
            has_sale = True
            if line.manual_unit_price is None or line.manual_unit_price <= 0:
                raise HTTPException(status_code=422, detail="Mỗi dòng bán phải có đơn giá nhập tay lớn hơn 0")
        if line.waste_qty > 0:
            has_waste = True

    if has_sale:
        method = (payload.payment_method or "").strip()
        if method not in {"cash", "transfer"}:
            raise HTTPException(status_code=422, detail="Vui lòng chọn phương thức thanh toán (tiền mặt hoặc chuyển khoản)")

    if has_waste and not (payload.waste_reason or "").strip():
        raise HTTPException(status_code=422, detail="Vui lòng nhập lý do hao hụt")


@router.get("/draft")
def get_reconciliation_draft():
    with get_db() as conn:
        return {
            "date": date.today().isoformat(),
            "products": _load_display_products(conn),
        }


@router.post("/submit", status_code=201)
def submit_reconciliation(payload: ReconciliationSubmitIn):
    with get_db() as conn:
        _validate_submit(payload)

        latest_products = _load_display_products(conn)
        latest_by_id = {item["product_id"]: item for item in latest_products}

        for line in payload.lines:
            latest = latest_by_id.get(line.product_id)
            if latest is None:
                raise HTTPException(status_code=422, detail="Có sản phẩm không còn trong danh sách trưng bày")
            if latest["expected_qty"] != line.expected_qty:
                raise HTTPException(status_code=409, detail="Số tồn đã thay đổi, vui lòng tải lại màn hình để cập nhật")

        session_cursor = conn.execute(
            """INSERT INTO reconciliation_sessions
               (reconciliation_date, staff_name, payment_method, waste_reason)
               VALUES (?, ?, ?, ?)""",
            (
                date.today().isoformat(),
                payload.staff_name.strip(),
                (payload.payment_method or "").strip(),
                (payload.waste_reason or "").strip(),
            ),
        )
        session_id = session_cursor.lastrowid

        for line in payload.lines:
            conn.execute(
                """INSERT INTO reconciliation_lines
                   (session_id, product_id, expected_qty, counted_qty, sale_qty, waste_qty, manual_unit_price)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    session_id,
                    line.product_id,
                    line.expected_qty,
                    line.counted_qty,
                    line.sale_qty,
                    line.waste_qty,
                    line.manual_unit_price,
                ),
            )

        return {
            "id": session_id,
            "date": date.today().isoformat(),
            "message": "Đã lưu đối soát thành công",
        }
