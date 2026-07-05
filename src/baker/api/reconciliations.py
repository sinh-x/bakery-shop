"""Reconciliation API routes for current-day stock counting."""

import logging
from datetime import date

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from baker.api.inventory_fifo import (
    available_quantity,
    consume_fifo_items,
    create_lot_with_items,
    net_available_quantity,
    normalize_price_value,
    resolve_price_bucket_option,
)
from baker.db.connection import get_db
from baker.models.event import Event
from baker.utils.time import now_utc
from baker.models.order import Order, OrderItem
from baker.models.payment_transaction import PaymentTransaction
from baker.models.work_item import WorkItem
from baker.services.order_stock import auto_decrement_stock

logger = logging.getLogger("baker.server")


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


def _resolve_line_chip_id(conn, line: ReconciliationLineIn) -> int | None:
    chip_id, _ = resolve_price_bucket_option(
        conn,
        line.product_id,
        line.normalized_price,
        line.price_chip_id,
    )
    return chip_id


def _format_price(value: int | float | None) -> str:
    return f"{normalize_price_value(value):,}".replace(",", ".") + "đ"


def _describe_submit_line(conn, line: ReconciliationLineIn, chip_id: int | None) -> str:
    product = conn.execute(
        "SELECT name, base_price FROM products WHERE id = ?",
        (line.product_id,),
    ).fetchone()
    product_name = product["name"] if product else "Không tìm thấy sản phẩm"

    parts = [f"{product_name} (ID {line.product_id})"]
    if chip_id is not None:
        chip = conn.execute(
            "SELECT label, price FROM product_price_chips WHERE id = ? AND product_id = ?",
            (chip_id, line.product_id),
        ).fetchone()
        if chip:
            parts.append(f"chip {chip['label']} - {_format_price(chip['price'])}")
        else:
            parts.append(f"chip ID {chip_id}")
    elif line.normalized_price is not None:
        parts.append(f"giá {_format_price(line.normalized_price)}")
    elif product:
        parts.append(f"giá gốc {_format_price(product['base_price'])}")

    return ", ".join(parts)


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

        # Gross available quantities per option (available items only, before
        # subtracting negative_balance). Surfaced to the Flutter client so the
        # surplus indicator matches the backend's gross surplus calculation
        # (counted_qty - available_quantity) instead of the net position
        # (counted_qty - expected_qty), which would inflate the displayed
        # surplus when a negative balance exists (DG-200 Phase 5.6-c1-fix, M-1).
        gross_available_by_option: dict[tuple[int, int | None], int] = {
            key: value for key, value in expected_by_option.items()
        }

        # Apply net position: subtract negative_balance per option (DG-200
        # Phase 3, FR-4). Draft surfaces negative positions to staff instead
        # of hiding them behind the available-only count.
        neg_rows = conn.execute(
            f"""SELECT product_id, price_chip_id, qty
               FROM negative_balance
               WHERE product_id IN ({placeholders})""",
            product_ids,
        ).fetchall()
        for neg_row in neg_rows:
            key = (neg_row["product_id"], neg_row["price_chip_id"])
            current = expected_by_option.get(key, 0)
            expected_by_option[key] = current - int(neg_row["qty"])

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
    else:
        gross_available_by_option: dict[tuple[int, int | None], int] = {}

    products: list[dict] = []
    for row in rows:
        product_id = row["id"]
        chips = chips_map.get(product_id, [])
        option_rows: list[dict] = []
        if chips:
            for chip in chips:
                chip_key = (product_id, chip["id"])
                option_rows.append(
                    {
                        "product_id": product_id,
                        "normalized_price": normalize_price_value(chip["price"]),
                        "price_chip_id": chip["id"],
                        "chip_label": chip["label"],
                        "source_chip_ids": [chip["id"]],
                        "expected_qty": expected_by_option.get(chip_key, 0),
                        "gross_available_qty": gross_available_by_option.get(chip_key, 0),
                    }
                )
            base_key = (product_id, None)
            base_qty = expected_by_option.get(base_key, 0)
            base_gross = gross_available_by_option.get(base_key, 0)
            if base_qty != 0:
                option_rows.append(
                    {
                        "product_id": product_id,
                        "normalized_price": normalize_price_value(row["base_price"]),
                        "price_chip_id": None,
                        "chip_label": "Giá gốc",
                        "source_chip_ids": [],
                        "expected_qty": base_qty,
                        "gross_available_qty": base_gross,
                    }
                )
        else:
            no_chip_key = (product_id, None)
            option_rows.append(
                {
                    "product_id": product_id,
                    "normalized_price": normalize_price_value(row["base_price"]),
                    "price_chip_id": None,
                    "chip_label": "Giá gốc",
                    "source_chip_ids": [],
                    "expected_qty": expected_by_option.get(no_chip_key, 0),
                    "gross_available_qty": gross_available_by_option.get(no_chip_key, 0),
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
        _validate_line_sale_rows(line)
        _validate_line_constraints(line)
        resolved_sale_qty = _resolved_sale_qty(line)

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


def _validate_line_sale_rows(line: ReconciliationLineIn) -> None:
    # expected_qty may be negative when a negative_balance exists (net
    # position, DG-200 Phase 3 FR-4). counted_qty must remain non-negative.
    if line.counted_qty < 0:
        raise HTTPException(status_code=422, detail="Số đếm thực tế không được âm")
    if line.sale_qty < 0 or line.waste_qty < 0:
        raise HTTPException(status_code=422, detail="Số lượng bán và hao hụt không được âm")

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


def _validate_line_constraints(line: ReconciliationLineIn) -> None:
    missing_qty = line.expected_qty - line.counted_qty
    resolved_sale_qty = _resolved_sale_qty(line)
    # Surplus (counted > expected) is accepted in Phase 3: surplus inflow is
    # handled in the submit flow (netting against negative balance, then
    # restock). No error raised here for missing_qty < 0 (DG-200 Phase 3, FR-5).
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
    if missing_qty < 0 and (resolved_sale_qty > 0 or line.waste_qty > 0):
        raise HTTPException(
            status_code=422,
            detail="Sản phẩm thừa (đếm > tồn dự kiến) thì không được nhập bán hoặc hao hụt",
        )


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
            chip_id = _resolve_line_chip_id(conn, line)
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
            auto_decrement_stock(conn, order.id or 0, order.order_ref)

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


def _process_surplus_inflow(
    conn,
    line: ReconciliationLineIn,
    chip_id: int | None,
    session_id: int,
) -> dict | None:
    """Handle reconciliation surplus (counted > expected) for one line.

    DG-200 Phase 3, FR-6:
    1. Compute surplus = counted_qty - expected_qty (positive only).
    2. Offset surplus against any existing negative_balance for the same
       (product_id, price_chip_id) — reduce negative first (netting).
    3. Remaining surplus (if any) creates a `restock` lot + items + movement
       and an Event.

    Returns a dict with restock movement metadata (or None when no surplus).
    All writes occur inside the caller's transaction (NFR-1).

    ``surplus`` is computed against the **available** stock (gross, not net)
    so that a negative-balance position does not inflate the inflow: e.g.
    available=0, negative=5, counted=2 → surplus=2 (offsets negative only),
    per AC-3.
    """
    available = available_quantity(conn, line.product_id, chip_id)
    surplus = line.counted_qty - available
    if surplus <= 0:
        return None

    # --- Netting against negative balance ---
    neg_row = conn.execute(
        """SELECT id, qty FROM negative_balance
           WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?""",
        (line.product_id, chip_id),
    ).fetchone()
    offset_qty = 0
    if neg_row and neg_row["qty"] > 0:
        offset_qty = min(surplus, int(neg_row["qty"]))
        new_neg_qty = int(neg_row["qty"]) - offset_qty
        if new_neg_qty <= 0:
            conn.execute(
                "DELETE FROM negative_balance WHERE id = ?",
                (neg_row["id"],),
            )
        else:
            conn.execute(
                "UPDATE negative_balance SET qty = ?, updated_at = ? WHERE id = ?",
                (new_neg_qty, now_utc(), neg_row["id"]),
            )

    # --- Restock the remaining surplus ---
    restock_qty = surplus - offset_qty
    restock_movement_id: int | None = None
    restock_lot_id: int | None = None
    if restock_qty > 0:
        restock_lot_id = create_lot_with_items(conn, line.product_id, chip_id, restock_qty)
        movement_cursor = conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id, price_chip_id, lot_id, created_at)
               VALUES (?, 'restock', ?, ?, ?, ?, ?, ?)""",
            (
                line.product_id,
                restock_qty,
                "reconciliation surplus inflow",
                f"reconciliation:{session_id}",
                chip_id,
                restock_lot_id,
                now_utc(),
            ),
        )
        restock_movement_id = movement_cursor.lastrowid

        product_row = conn.execute(
            "SELECT name FROM products WHERE id = ?",
            (line.product_id,),
        ).fetchone()
        product_name = product_row["name"] if product_row else f"product_id={line.product_id}"
        Event(
            summary=f"Nhập hàng +{restock_qty} {product_name}",
            type="inventory",
            data={
                "product_id": line.product_id,
                "product_name": product_name,
                "movement_type": "restock",
                "quantity": restock_qty,
                "reason": "reconciliation surplus inflow",
                "reference_id": f"reconciliation:{session_id}",
                "price_chip_id": chip_id,
                "lot_id": restock_lot_id,
            },
        ).save(conn)

        # DG-200 Phase 4, AC-9: Inventory debit journal entry for the
        # restocked surplus. Mirrors the waste COGS sync pattern (DR
        # Inventory / CR COGS). Fire-and-forget: accounting failures never
        # block the reconciliation submit (NFR1).
        #
        # Inline import (not module-level) is intentional: journal_sync
        # imports from baker.api.inventory_fifo, which is already a module-level
        # dependency of this file. Keeping journal_sync inline at call-site
        # preserves the same circular-dependency avoidance pattern used in
        # order_stock.py and limits the accounting coupling to the operation
        # that needs it (DG-200 Phase 5.6-c1-fix, Mn-1).
        from baker.services.journal_sync import (
            _sync_restock_inflow_journal,
            run_journal_sync,
        )

        run_journal_sync(
            _sync_restock_inflow_journal,
            conn, line.product_id, restock_movement_id, restock_qty,
            log_label=(
                f"restock inflow journal sync for movement {restock_movement_id}"
            ),
        )

    return {
        "surplus": surplus,
        "offset_qty": offset_qty,
        "restock_qty": restock_qty,
        "restock_movement_id": restock_movement_id,
        "restock_lot_id": restock_lot_id,
    }


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
            chip_id = _resolve_line_chip_id(conn, line)
            line_description = _describe_submit_line(conn, line, chip_id)
            latest = latest_by_key.get((line.product_id, chip_id))
            if latest is None:
                raise HTTPException(
                    status_code=422,
                    detail=(
                        "Có sản phẩm không còn trong danh sách trưng bày: "
                        f"{line_description}"
                    ),
                )
            if latest["expected_qty"] != line.expected_qty:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        "Số tồn đã thay đổi, vui lòng tải lại màn hình để cập nhật: "
                        f"{line_description}"
                    ),
                )

        session_cursor = conn.execute(
            """INSERT INTO reconciliation_sessions
               (reconciliation_date, staff_name, payment_method, waste_reason, created_at)
               VALUES (?, ?, ?, ?, ?)""",
            (
                date.today().isoformat(),
                payload.staff_name.strip(),
                (payload.payment_method or "").strip(),
                (payload.waste_reason or "").strip(),
                now_utc(),
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

            chip_id = _resolve_line_chip_id(conn, line)

            per_line_reason = (line.waste_reason or "").strip() or (payload.waste_reason or "").strip()
            movement_cursor = conn.execute(
                """INSERT INTO stock_movements
                   (product_id, movement_type, quantity, reason, reference_id, price_chip_id, created_at)
                   VALUES (?, 'waste', ?, ?, ?, ?, ?)""",
                (line.product_id, -line.waste_qty, per_line_reason, f"reconciliation:{session_id}", chip_id, now_utc()),
            )
            waste_movement_id = movement_cursor.lastrowid
            consume_fifo_items(conn, line.product_id, chip_id, line.waste_qty, waste_movement_id)

            # Inline import: same circular-dependency avoidance pattern as the
            # restock and negative-sale journal syncs (DG-200 Phase 5.6-c1-fix, Mn-1).
            from baker.services.journal_sync import _sync_waste_cogs_journal, run_journal_sync

            run_journal_sync(
                _sync_waste_cogs_journal,
                conn, line.product_id, waste_movement_id, line.waste_qty,
                log_label=f"waste cogs sync for movement {waste_movement_id}",
            )
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

        # --- Surplus inflow (DG-200 Phase 3, FR-6) ---
        # Process surplus (counted > expected) after sales/waste so the
        # expected_qty staleness check reflects pre-surplus state. Netting
        # against negative_balance happens first, then restock inflow.
        surplus_by_option: dict[tuple[int, int | None], dict] = {}
        for line in payload.lines:
            if line.counted_qty <= line.expected_qty:
                continue
            chip_id = _resolve_line_chip_id(conn, line)
            surplus_info = _process_surplus_inflow(conn, line, chip_id, session_id)
            if surplus_info is not None:
                surplus_by_option[(line.product_id, chip_id)] = surplus_info

        # --- Negative-balance clearing (DG-200 Phase 5.6-c1-fix, Sinh-1) ---
        # When a product has a negative balance (expected_qty < 0) and staff
        # submit counted_qty == 0, they confirm the negative was a data error.
        # Clear the negative_balance row so the system position resets to
        # zero. This runs after surplus inflow (which may have already reduced
        # the negative balance via netting).
        for line in payload.lines:
            if line.expected_qty >= 0 or line.counted_qty != 0:
                continue
            chip_id = _resolve_line_chip_id(conn, line)
            neg_row = conn.execute(
                """SELECT id, qty FROM negative_balance
                   WHERE product_id = ? AND price_chip_id IS NOT DISTINCT FROM ?""",
                (line.product_id, chip_id),
            ).fetchone()
            if neg_row and neg_row["qty"] > 0:
                conn.execute(
                    "DELETE FROM negative_balance WHERE id = ?",
                    (neg_row["id"],),
                )
                product_name_row = conn.execute(
                    "SELECT name FROM products WHERE id = ?",
                    (line.product_id,),
                ).fetchone()
                product_name = (
                    product_name_row["name"]
                    if product_name_row
                    else f"product_id={line.product_id}"
                )
                Event(
                    summary=f"Xoá âm tồn {product_name}",
                    type="inventory",
                    data={
                        "product_id": line.product_id,
                        "product_name": product_name,
                        "movement_type": "negative_balance_clear",
                        "quantity": 0,
                        "reason": "reconciliation confirmed zero count",
                        "reference_id": f"reconciliation:{session_id}",
                        "price_chip_id": chip_id,
                        "cleared_negative_qty": int(neg_row["qty"]),
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
            chip_id = _resolve_line_chip_id(conn, line)
            per_line_reason = (line.waste_reason or "").strip() or (payload.waste_reason or "").strip()
            line_sale_rows = sale_rows_by_line[line_index]
            linked_order_item_id = line_sale_rows[0]["order_item_id"] if line_sale_rows else None
            linked_sale_movement_id = line_sale_rows[0]["sale_movement_id"] if line_sale_rows else None
            line_cursor = conn.execute(
                """INSERT INTO reconciliation_lines
                   (session_id, product_id, expected_qty, counted_qty, sale_qty, waste_qty, waste_reason, manual_unit_price,
                     price_chip_id, linked_order_item_id, linked_stock_movement_sale_id, linked_stock_movement_waste_id, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
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
                    now_utc(),
                ),
            )
            line_id = line_cursor.lastrowid

            for row_index, sale_row in enumerate(line.sale_rows):
                row_link = line_sale_rows[row_index]
                conn.execute(
                    """INSERT INTO reconciliation_sale_rows
                       (line_id, quantity, unit_price, payment_method, linked_order_ref, linked_payment_ref, created_at)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        line_id,
                        sale_row.quantity,
                        sale_row.unit_price,
                        sale_row.payment_method,
                        row_link["order_ref"],
                        row_link["payment_ref"],
                        now_utc(),
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
