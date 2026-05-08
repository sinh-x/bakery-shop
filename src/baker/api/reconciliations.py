"""Reconciliation API routes for current-day stock counting."""

from datetime import date

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from baker.api.inventory_fifo import (
    consume_fifo_items,
    normalize_price_chip,
    normalize_price_value,
    resolve_price_bucket_chip_id,
)
from baker.api.orders import _auto_decrement_stock
from baker.db.connection import get_db
from baker.models.event import Event
from baker.models.order import Order, OrderItem
from baker.models.payment_transaction import PaymentTransaction
from baker.models.work_item import WorkItem


router = APIRouter(prefix="/api/reconciliations", tags=["reconciliations"])


class ReconciliationSaleRowIn(BaseModel):
    quantity: int
    unit_price: float
    payment_method: str


class ReconciliationLineIn(BaseModel):
    product_id: int
    normalized_price: int | None = None
    price_chip_id: int | None = None
    expected_qty: int
    counted_qty: int
    sale_qty: int = 0
    waste_qty: int = 0
    manual_unit_price: float | None = None
    waste_reason: str | None = None
    sale_rows: list[ReconciliationSaleRowIn] = Field(default_factory=list)


class ReconciliationSubmitIn(BaseModel):
    staff_name: str
    payment_method: str | None = None
    waste_reason: str | None = None
    lines: list[ReconciliationLineIn]


def _resolved_sale_qty(line: ReconciliationLineIn) -> int:
    if line.sale_rows:
        return sum(row.quantity for row in line.sale_rows)
    return line.sale_qty


def _load_display_products(conn) -> list[dict]:
    rows = conn.execute(
        """SELECT p.id, p.name, p.category, p.base_price
           FROM products p
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
    expected_by_option: dict[tuple[int, int | None], int] = {}

    if product_ids:
        placeholders = ",".join("?" * len(product_ids))
        expected_rows = conn.execute(
            """SELECT sl.product_id, sl.price_chip_id, COUNT(ii.id) AS quantity
               FROM stock_lots sl
               LEFT JOIN inventory_items ii
                 ON ii.lot_id = sl.id AND ii.status = 'available'
               WHERE sl.product_id IN ("""
            + placeholders
            + ") GROUP BY sl.product_id, sl.price_chip_id",
            product_ids,
        ).fetchall()
        for stock_row in expected_rows:
            expected_by_option[(stock_row["product_id"], stock_row["price_chip_id"])] = int(
                stock_row["quantity"] or 0
            )

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

    products: list[dict] = []
    for row in rows:
        product_id = row["id"]
        chips = chips_map.get(product_id, [])
        option_rows: list[dict] = []
        if chips:
            for chip in chips:
                option_rows.append(
                    {
                        "product_id": product_id,
                        "normalized_price": normalize_price_value(chip["price"]),
                        "price_chip_id": chip["id"],
                        "chip_label": chip["label"],
                        "source_chip_ids": [chip["id"]],
                        "expected_qty": expected_by_option.get((product_id, chip["id"]), 0),
                    }
                )
            base_qty = expected_by_option.get((product_id, None), 0)
            if base_qty > 0:
                option_rows.append(
                    {
                        "product_id": product_id,
                        "normalized_price": normalize_price_value(row["base_price"]),
                        "price_chip_id": None,
                        "chip_label": "Giá gốc",
                        "source_chip_ids": [],
                        "expected_qty": base_qty,
                    }
                )
        else:
            option_rows.append(
                {
                    "product_id": product_id,
                    "normalized_price": normalize_price_value(row["base_price"]),
                    "price_chip_id": None,
                    "chip_label": "Giá gốc",
                    "source_chip_ids": [],
                    "expected_qty": expected_by_option.get((product_id, None), 0),
                }
            )

        products.append(
            {
                "product_id": product_id,
                "name": row["name"],
                "category": row["category"],
                "expected_qty": sum(option["expected_qty"] for option in option_rows),
                "base_price": row["base_price"],
                "price_chips": chips,
                "options": option_rows,
            }
        )

    return products


def _validate_submit(payload: ReconciliationSubmitIn):
    if not payload.staff_name.strip():
        raise HTTPException(status_code=422, detail="Vui lòng chọn tên nhân viên")
    if not payload.lines:
        raise HTTPException(status_code=422, detail="Danh sách sản phẩm không được để trống")

    has_sale = False
    has_waste = False
    lines_missing_reason: list[int] = []

    for line in payload.lines:
        if line.expected_qty < 0 or line.counted_qty < 0:
            raise HTTPException(status_code=422, detail="Số lượng tồn không được âm")
        if line.sale_qty < 0 or line.waste_qty < 0:
            raise HTTPException(status_code=422, detail="Số lượng bán và hao hụt không được âm")

        if line.sale_rows:
            for row_index, sale_row in enumerate(line.sale_rows, start=1):
                if sale_row.quantity <= 0:
                    raise HTTPException(
                        status_code=422,
                        detail=f"Sản phẩm #{line.product_id}, dòng bán #{row_index}: số lượng phải lớn hơn 0",
                    )
                if sale_row.unit_price <= 0:
                    raise HTTPException(
                        status_code=422,
                        detail=f"Sản phẩm #{line.product_id}, dòng bán #{row_index}: đơn giá phải lớn hơn 0",
                    )
                if sale_row.payment_method not in {"cash", "transfer"}:
                    raise HTTPException(
                        status_code=422,
                        detail=f"Sản phẩm #{line.product_id}, dòng bán #{row_index}: phương thức thanh toán không hợp lệ",
                    )

        missing_qty = line.expected_qty - line.counted_qty
        resolved_sale_qty = _resolved_sale_qty(line)
        if missing_qty < 0:
            raise HTTPException(status_code=422, detail="Số đếm thực tế không được lớn hơn số tồn dự kiến")
        if missing_qty > 0 and line.waste_qty > missing_qty:
            raise HTTPException(
                status_code=422,
                detail="Số hao hụt vượt quá số thiếu. Vui lòng vào màn hình 'Nhập hàng' để bổ sung tồn kho trước.",
            )
        if missing_qty > 0 and resolved_sale_qty + line.waste_qty != missing_qty:
            raise HTTPException(
                status_code=422,
                detail=(
                    f"Sản phẩm #{line.product_id} thiếu phải tách đúng: "
                    "bán + hao hụt = số thiếu"
                ),
            )
        if missing_qty == 0 and (resolved_sale_qty > 0 or line.waste_qty > 0):
            raise HTTPException(status_code=422, detail="Sản phẩm không thiếu thì không được nhập bán hoặc hao hụt")

        if resolved_sale_qty > 0:
            has_sale = True
            if not line.sale_rows and (line.manual_unit_price is None or line.manual_unit_price <= 0):
                raise HTTPException(status_code=422, detail="Mỗi dòng bán phải có đơn giá nhập tay lớn hơn 0")
        if line.waste_qty > 0:
            has_waste = True
            if not (line.waste_reason or "").strip():
                lines_missing_reason.append(line.product_id)

    if has_sale:
        method = (payload.payment_method or "").strip()
        has_row_methods = any(line.sale_rows for line in payload.lines)
        if not has_row_methods and method not in {"cash", "transfer"}:
            raise HTTPException(status_code=422, detail="Vui lòng chọn phương thức thanh toán (tiền mặt hoặc chuyển khoản)")

    if lines_missing_reason:
        session_reason = (payload.waste_reason or "").strip()
        if not session_reason:
            raise HTTPException(status_code=422, detail="Sản phẩm có hao hụt phải nhập lý do")


def _create_sale_orders(
    conn,
    payload: ReconciliationSubmitIn,
    session_id: int,
    latest_by_key: dict[tuple[int, int | None], dict],
) -> list[list[dict]]:
    orders_by_line: list[list[dict]] = []

    for line in payload.lines:
        line_rows: list[dict] = []
        if line.sale_rows:
            row_payloads = [
                {
                    "quantity": sale_row.quantity,
                    "unit_price": float(sale_row.unit_price),
                    "payment_method": sale_row.payment_method,
                }
                for sale_row in line.sale_rows
            ]
        elif line.sale_qty > 0:
            row_payloads = [
                {
                    "quantity": line.sale_qty,
                    "unit_price": float(line.manual_unit_price or 0),
                    "payment_method": (payload.payment_method or "").strip(),
                }
            ]
        else:
            row_payloads = []

        for row_payload in row_payloads:
            if line.normalized_price is not None:
                chip_id = resolve_price_bucket_chip_id(conn, line.product_id, line.normalized_price)
            else:
                chip_id = normalize_price_chip(conn, line.product_id, line.price_chip_id)
            latest = latest_by_key[(line.product_id, chip_id)]
            order = Order(
                customer_name="Đối soát tồn kho",
                items=[
                    OrderItem(
                        product=latest["name"],
                        qty=row_payload["quantity"],
                        price=row_payload["unit_price"],
                        product_id=str(line.product_id),
                        price_chip_id=chip_id,
                    )
                ],
                status="new",
                source="reconciliation",
                notes=f"Đối soát phiên #{session_id}",
                created_by=payload.staff_name.strip(),
            )
            order.calculate_total()
            order.save(conn)

            work_item = WorkItem(
                order_id=order.id or 0,
                product_id=str(line.product_id),
                product_name=latest["name"],
                quantity=row_payload["quantity"],
                unit_price=row_payload["unit_price"],
                position=0,
                price_chip_id=chip_id,
            )
            work_item.save(conn)

            payment_txn = PaymentTransaction(
                order_id=order.id or 0,
                amount=float(order.total_price),
                type="payment",
                method=row_payload["payment_method"],
                note=f"Đối soát phiên #{session_id}",
            )
            payment_txn.save(conn)

            Order.update_status(conn, order.order_ref, "delivered", "")
            _auto_decrement_stock(conn, order.id or 0, order.order_ref)

            sale_movement = conn.execute(
                """SELECT id
                   FROM stock_movements
                   WHERE movement_type = 'sale' AND reference_id = ? AND product_id = ?
                     AND ((price_chip_id IS NULL AND ? IS NULL) OR price_chip_id = ?)
                   ORDER BY id DESC
                   LIMIT 1""",
                (order.order_ref, line.product_id, chip_id, chip_id),
            ).fetchone()

            line_rows.append(
                {
                    "quantity": row_payload["quantity"],
                    "unit_price": row_payload["unit_price"],
                    "payment_method": row_payload["payment_method"],
                    "order_ref": order.order_ref,
                    "payment_ref": str(payment_txn.id),
                    "order_item_id": work_item.id,
                    "sale_movement_id": sale_movement["id"] if sale_movement else None,
                    "price_chip_id": chip_id,
                }
            )

        orders_by_line.append(line_rows)

    return orders_by_line


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
        latest_by_key: dict[tuple[int, int | None], dict] = {}
        for item in latest_products:
            for option in item.get("options", []):
                latest_by_key[(item["product_id"], option["price_chip_id"])] = {
                    **option,
                    "name": item["name"],
                }

        for line in payload.lines:
            if line.normalized_price is not None:
                chip_id = resolve_price_bucket_chip_id(conn, line.product_id, line.normalized_price)
            else:
                chip_id = normalize_price_chip(conn, line.product_id, line.price_chip_id)
            latest = latest_by_key.get((line.product_id, chip_id))
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

        sale_rows_by_line = _create_sale_orders(
            conn,
            payload,
            session_id,
            latest_by_key,
        )

        waste_movement_ids_by_option: dict[tuple[int, int | None], int] = {}
        for line in payload.lines:
            if line.waste_qty <= 0:
                continue

            if line.normalized_price is not None:
                chip_id = resolve_price_bucket_chip_id(conn, line.product_id, line.normalized_price)
            else:
                chip_id = normalize_price_chip(conn, line.product_id, line.price_chip_id)

            per_line_reason = (line.waste_reason or "").strip() or (payload.waste_reason or "").strip()
            movement_cursor = conn.execute(
                """INSERT INTO stock_movements
                   (product_id, movement_type, quantity, reason, reference_id, price_chip_id)
                   VALUES (?, 'waste', ?, ?, ?, ?)""",
                (line.product_id, -line.waste_qty, per_line_reason, f"reconciliation:{session_id}", chip_id),
            )
            waste_movement_id = movement_cursor.lastrowid
            consume_fifo_items(conn, line.product_id, chip_id, line.waste_qty, waste_movement_id)
            lot_row = conn.execute(
                "SELECT lot_id FROM inventory_items WHERE consumed_by_movement_id = ? ORDER BY id ASC LIMIT 1",
                (waste_movement_id,),
            ).fetchone()
            if lot_row:
                conn.execute(
                    "UPDATE stock_movements SET lot_id = ? WHERE id = ?",
                    (lot_row["lot_id"], waste_movement_id),
                )
            waste_movement_ids_by_option[(line.product_id, chip_id)] = waste_movement_id

            product_name_row = conn.execute(
                "SELECT name FROM products WHERE id = ?",
                (line.product_id,),
            ).fetchone()
            product_name = product_name_row["name"] if product_name_row else f"product_id={line.product_id}"
            Event(
                summary=f"Hao hụt -{line.waste_qty} {product_name}",
                type="inventory",
                data={
                    "product_id": line.product_id,
                    "product_name": product_name,
                    "movement_type": "waste",
                    "quantity": -line.waste_qty,
                    "reason": per_line_reason,
                    "reference_id": f"reconciliation:{session_id}",
                    "price_chip_id": chip_id,
                },
            ).save(conn)

        first_sale_row = next(
            (sale_row for line_rows in sale_rows_by_line for sale_row in line_rows),
            None,
        )
        conn.execute(
            """UPDATE reconciliation_sessions
               SET linked_order_ref = ?, linked_payment_ref = ?
               WHERE id = ?""",
            (
                first_sale_row["order_ref"] if first_sale_row else None,
                first_sale_row["payment_ref"] if first_sale_row else None,
                session_id,
            ),
        )

        for line_index, line in enumerate(payload.lines):
            if line.normalized_price is not None:
                chip_id = resolve_price_bucket_chip_id(conn, line.product_id, line.normalized_price)
            else:
                chip_id = normalize_price_chip(conn, line.product_id, line.price_chip_id)
            per_line_reason = (line.waste_reason or "").strip() or (payload.waste_reason or "").strip()
            line_sale_rows = sale_rows_by_line[line_index]
            linked_order_item_id = line_sale_rows[0]["order_item_id"] if line_sale_rows else None
            linked_sale_movement_id = line_sale_rows[0]["sale_movement_id"] if line_sale_rows else None
            line_cursor = conn.execute(
                """INSERT INTO reconciliation_lines
                   (session_id, product_id, expected_qty, counted_qty, sale_qty, waste_qty, waste_reason, manual_unit_price,
                     price_chip_id, linked_order_item_id, linked_stock_movement_sale_id, linked_stock_movement_waste_id)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    session_id,
                    line.product_id,
                    line.expected_qty,
                    line.counted_qty,
                    _resolved_sale_qty(line),
                    line.waste_qty,
                    per_line_reason,
                    line.manual_unit_price,
                    chip_id,
                    linked_order_item_id,
                    linked_sale_movement_id,
                    waste_movement_ids_by_option.get((line.product_id, chip_id)),
                ),
            )
            line_id = line_cursor.lastrowid

            for row_index, sale_row in enumerate(line.sale_rows):
                row_link = line_sale_rows[row_index]
                conn.execute(
                    """INSERT INTO reconciliation_sale_rows
                       (line_id, quantity, unit_price, payment_method, linked_order_ref, linked_payment_ref)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (
                        line_id,
                        sale_row.quantity,
                        sale_row.unit_price,
                        sale_row.payment_method,
                        row_link["order_ref"],
                        row_link["payment_ref"],
                    ),
                )

        return {
            "id": session_id,
            "date": date.today().isoformat(),
            "message": "Đã lưu đối soát thành công",
        }


@router.get("/history")
def get_reconciliation_history(limit: int = 30):
    bounded_limit = max(1, min(limit, 200))
    with get_db() as conn:
        rows = conn.execute(
            """SELECT rs.id,
                      rs.reconciliation_date,
                      rs.staff_name,
                      rs.payment_method,
                      rs.waste_reason,
                      rs.linked_order_ref,
                      rs.created_at,
                      COUNT(rl.id) AS line_count
               FROM reconciliation_sessions rs
               LEFT JOIN reconciliation_lines rl ON rl.session_id = rs.id
               GROUP BY rs.id
               ORDER BY rs.id DESC
               LIMIT ?""",
            (bounded_limit,),
        ).fetchall()
        return {
            "sessions": [
                {
                    "id": row["id"],
                    "reconciliation_date": row["reconciliation_date"],
                    "staff_name": row["staff_name"],
                    "payment_method": row["payment_method"] or "",
                    "waste_reason": row["waste_reason"] or "",
                    "linked_order_ref": row["linked_order_ref"],
                    "created_at": row["created_at"],
                    "line_count": row["line_count"],
                }
                for row in rows
            ]
        }


@router.get("/history/{session_id}")
def get_reconciliation_history_detail(session_id: int):
    with get_db() as conn:
        session = conn.execute(
            """SELECT id,
                      reconciliation_date,
                      staff_name,
                      payment_method,
                      waste_reason,
                      linked_order_ref,
                      linked_payment_ref,
                      created_at
               FROM reconciliation_sessions
               WHERE id = ?""",
            (session_id,),
        ).fetchone()
        if session is None:
            raise HTTPException(status_code=404, detail="Không tìm thấy phiên đối soát")

        line_rows = conn.execute(
            """SELECT rl.id,
                      rl.product_id,
                       rl.price_chip_id,
                      CAST(ROUND(COALESCE(ppc.price, p.base_price)) AS INTEGER) AS normalized_price,
                      p.name AS product_name,
                      rl.expected_qty,
                      rl.counted_qty,
                      rl.sale_qty,
                      rl.waste_qty,
                      rl.waste_reason,
                      rl.manual_unit_price,
                      rl.linked_order_item_id,
                      rl.linked_stock_movement_sale_id,
                      rl.linked_stock_movement_waste_id
               FROM reconciliation_lines rl
               LEFT JOIN products p ON p.id = rl.product_id
               LEFT JOIN product_price_chips ppc ON ppc.id = rl.price_chip_id
               WHERE rl.session_id = ?
               ORDER BY p.name, COALESCE(ppc.position, 999), rl.price_chip_id, rl.id""",
            (session_id,),
        ).fetchall()

        sale_row_rows = conn.execute(
            """SELECT id,
                      line_id,
                      quantity,
                      unit_price,
                      payment_method,
                      linked_order_ref,
                      linked_payment_ref
               FROM reconciliation_sale_rows
               WHERE line_id IN (
                   SELECT id FROM reconciliation_lines WHERE session_id = ?
               )
               ORDER BY id""",
            (session_id,),
        ).fetchall()
        sale_rows_by_line_id: dict[int, list[dict]] = {}
        for row in sale_row_rows:
            sale_rows_by_line_id.setdefault(row["line_id"], []).append(
                {
                    "id": row["id"],
                    "quantity": row["quantity"],
                    "unit_price": row["unit_price"],
                    "payment_method": row["payment_method"],
                    "linked_order_ref": row["linked_order_ref"],
                    "linked_payment_ref": row["linked_payment_ref"],
                    "is_legacy": False,
                }
            )

        return {
            "id": session["id"],
            "reconciliation_date": session["reconciliation_date"],
            "staff_name": session["staff_name"],
            "payment_method": session["payment_method"] or "",
            "waste_reason": session["waste_reason"] or "",
            "linked_order_ref": session["linked_order_ref"],
            "linked_payment_ref": session["linked_payment_ref"],
            "created_at": session["created_at"],
            "lines": [
                {
                    "id": row["id"],
                    "product_id": row["product_id"],
                    "normalized_price": row["normalized_price"],
                    "price_chip_id": row["price_chip_id"],
                    "product_name": row["product_name"] or "",
                    "expected_qty": row["expected_qty"],
                    "counted_qty": row["counted_qty"],
                    "sale_qty": row["sale_qty"],
                    "waste_qty": row["waste_qty"],
                    "waste_reason": row["waste_reason"] or "",
                    "manual_unit_price": row["manual_unit_price"],
                    "linked_order_item_id": row["linked_order_item_id"],
                    "linked_stock_movement_sale_id": row["linked_stock_movement_sale_id"],
                    "linked_stock_movement_waste_id": row["linked_stock_movement_waste_id"],
                    "sale_rows": sale_rows_by_line_id.get(row["id"], [])
                    or (
                        [
                            {
                                "id": None,
                                "quantity": row["sale_qty"],
                                "unit_price": row["manual_unit_price"],
                                "payment_method": session["payment_method"] or "",
                                "linked_order_ref": session["linked_order_ref"],
                                "linked_payment_ref": session["linked_payment_ref"],
                                "is_legacy": True,
                            }
                        ]
                        if row["sale_qty"] > 0
                        else []
                    ),
                }
                for row in line_rows
            ],
        }
