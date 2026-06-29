"""Order management API routes."""

import json
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field

from baker.db.connection import get_db
from baker.logging import log_context, logger
from baker.utils.time import now_iso
from baker.models.order import (
    PUBLIC_ORDER_CODE_MAX_REFERENCE_LEN,
    Order,
    OrderItem,
    delivery_type_to_public_suffix,
    generate_public_order_code_candidate,
    is_backward_transition,
    validate_transition,
)
from baker.models.payment_transaction import PaymentTransaction
from baker.models.work_item import WorkItem
from baker.services.order_stock import auto_decrement_stock, restore_stock_for_order


router = APIRouter(prefix="/api/orders", tags=["orders"])


def _day_bounds(date_str: str) -> tuple[str, str]:
    day = datetime.strptime(date_str, "%Y-%m-%d")
    next_day = day + timedelta(days=1)
    return f"{date_str}T00:00:00", next_day.strftime("%Y-%m-%dT00:00:00")


class OrderItemIn(BaseModel):
    productId: str = ""
    productName: str
    quantity: int = 1
    unitPrice: float = 0.0
    notes: str = ""
    isBirthday: bool = False
    age: Optional[int] = None
    isExtra: bool = False
    isGift: bool = False
    priceChipId: int | None = None
    attributes: dict = Field(default_factory=dict)


class DepositIn(BaseModel):
    amount: float
    method: str = "cash"


class OrderCreate(BaseModel):
    customerName: str
    customerPhone: str = ""
    items: list[OrderItemIn] = []
    dueDate: Optional[str] = None
    dueTime: Optional[str] = None
    deliveryType: str = "pickup"
    deliveryAddress: str = ""
    notes: str = ""
    source: str = ""
    deposit: Optional[DepositIn] = None
    createdBy: str = ""
    shippingFee: float = 0.0
    status: Optional[str] = None
    paymentMethod: Optional[str] = None


class OrderEdit(BaseModel):
    customerName: Optional[str] = None
    customerPhone: Optional[str] = None
    items: Optional[list[OrderItemIn]] = None
    dueDate: Optional[str] = None
    dueTime: Optional[str] = None
    deliveryType: Optional[str] = None
    deliveryAddress: Optional[str] = None
    notes: Optional[str] = None
    source: Optional[str] = None
    shippingFee: Optional[float] = None
    changedBy: str = ""
    workTicketPrintedAt: Optional[str] = None
    publicCodeDateChangeDecision: Optional[str] = None


class StatusTransition(BaseModel):
    status: str
    reason: str = ""
    changedBy: str = ""


class PaymentMethodUpdate(BaseModel):
    method: str  # 'cash' | 'transfer'


class PaymentUpdate(BaseModel):
    amountPaid: float
    changedBy: str = ""


def _log_order_history(conn, order_id, action_type, field_name="", old_value="", new_value="", changed_by=""):
    """Insert an audit log entry into the order_history table."""
    conn.execute(
        """INSERT INTO order_history (order_id, action_type, field_name, old_value, new_value, changed_by)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (order_id, action_type, field_name, old_value, new_value, changed_by),
    )


def _auto_decrement_stock(conn, order_id: int, order_ref: str):
    """Backward-compatible wrapper for stock decrement service."""
    auto_decrement_stock(conn, order_id, order_ref)


def _item_in_to_model(item: OrderItemIn) -> OrderItem:
    return OrderItem(
        product=item.productName,
        qty=item.quantity,
        price=item.unitPrice,
        notes=item.notes,
        product_id=item.productId,
        is_birthday=item.isBirthday,
        age=item.age,
        is_extra=item.isExtra,
        is_gift=item.isGift,
        attributes=item.attributes,
        price_chip_id=item.priceChipId,
    )


def _order_detail(conn, row) -> dict:
    """Build full order detail dict including work items and payment transactions."""
    order = Order.from_row(row, conn)
    result = order.to_api_dict()

    item_rows = conn.execute(
        "SELECT * FROM order_items WHERE order_id = ? ORDER BY position, id",
        (row["id"],),
    ).fetchall()
    result["workItems"] = [WorkItem.from_row(r).to_api_dict() for r in item_rows]

    txn_rows = conn.execute(
        "SELECT * FROM payment_transactions WHERE order_id = ? ORDER BY id",
        (row["id"],),
    ).fetchall()
    result["paymentTransactions"] = [PaymentTransaction.from_row(r).to_api_dict() for r in txn_rows]

    return result


def _generate_unique_public_order_code(conn, due_date: str, delivery_type: str) -> str:
    for reference_len in range(3, PUBLIC_ORDER_CODE_MAX_REFERENCE_LEN + 1):
        attempts = 30 if reference_len == 3 else 50
        for _ in range(attempts):
            candidate = generate_public_order_code_candidate(delivery_type, reference_len)
            exists = conn.execute(
                "SELECT 1 FROM orders WHERE due_date = ? AND public_order_code = ? LIMIT 1",
                (due_date, candidate),
            ).fetchone()
            if not exists:
                return candidate
    raise HTTPException(status_code=500, detail="Không thể tạo mã nhận bánh hợp lệ")


def _public_code_exists_for_due_date(conn, due_date: str, public_order_code: str, order_id: int) -> bool:
    existing = conn.execute(
        """SELECT 1 FROM orders
           WHERE due_date = ? AND public_order_code = ? AND id != ?
           LIMIT 1""",
        (due_date, public_order_code, order_id),
    ).fetchone()
    return bool(existing)


def _replace_public_code_suffix(public_order_code: str, delivery_type: str) -> str:
    if not public_order_code or "-" not in public_order_code:
        return public_order_code
    reference = public_order_code.split("-", 1)[0]
    return f"{reference}-{delivery_type_to_public_suffix(delivery_type)}"


def _log_status_transition_rejection(
    *,
    requested_ref: str,
    order_row,
    target_status: str,
    status_code: int,
    rejection_detail: str,
) -> None:
    order_ref = order_row["order_ref"] if order_row else requested_ref
    order_id = str(order_row["id"]) if order_row else ""
    logger.warning(
        "order_status_transition_rejected",
        extra={
            "extra_data": {
                "path": "/api/orders/{ref}/status",
                "order_ref": order_ref,
                "order_id": order_id,
                "target_status": target_status,
                "status_code": status_code,
                "rejection_detail": rejection_detail,
            }
        },
    )


def _raise_status_transition_rejection(
    *,
    requested_ref: str,
    order_row,
    target_status: str,
    status_code: int,
    rejection_detail: str,
) -> None:
    _log_status_transition_rejection(
        requested_ref=requested_ref,
        order_row=order_row,
        target_status=target_status,
        status_code=status_code,
        rejection_detail=rejection_detail,
    )
    raise HTTPException(status_code=status_code, detail=rejection_detail)


@router.get("")
def list_orders(
    status: Optional[str] = Query(None, description="Lọc theo trạng thái"),
    due_date: Optional[str] = Query(None, description="Lọc theo ngày giao (YYYY-MM-DD)"),
    due_date_from: Optional[str] = Query(None, description="Lọc theo ngày giao bắt đầu (YYYY-MM-DD)"),
    due_date_to: Optional[str] = Query(None, description="Lọc theo ngày giao kết thúc (YYYY-MM-DD)"),
    limit: int = Query(50, description="Số lượng tối đa"),
    offset: int = Query(0, description="Bỏ qua N đơn đầu"),
    active_only: bool = Query(False, description="Chỉ lấy đơn hàng đang hoạt động (không hoàn thành/hủy)"),
):
    """Danh sách đơn hàng."""
    with get_db() as conn:
        conditions = []
        params: list = []

        if active_only:
            active_statuses = ["new", "confirmed", "in_progress", "ready", "delivered"]
            placeholders = ",".join("?" for _ in active_statuses)
            conditions.append(f"status IN ({placeholders})")
            params.extend(active_statuses)
        elif status:
            conditions.append("status = ?")
            params.append(status)

        if due_date:
            created_at_from, created_at_to = _day_bounds(due_date)
            conditions.append(
                """(
                    due_date = ?
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source = ?
                        AND created_at >= ?
                        AND created_at < ?
                    )
                )"""
            )
            params.extend([due_date, "Tại tiệm - POS", created_at_from, created_at_to])
        elif due_date_from and due_date_to:
            created_at_from, _ = _day_bounds(due_date_from)
            _, created_at_to = _day_bounds(due_date_to)
            conditions.append(
                """(
                    (due_date >= ? AND due_date <= ?)
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source = ?
                        AND created_at >= ?
                        AND created_at < ?
                    )
                )"""
            )
            params.extend([due_date_from, due_date_to, "Tại tiệm - POS", created_at_from, created_at_to])
        elif due_date_from:
            created_at_from, _ = _day_bounds(due_date_from)
            conditions.append(
                """(
                    due_date >= ?
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source = ?
                        AND created_at >= ?
                    )
                )"""
            )
            params.extend([due_date_from, "Tại tiệm - POS", created_at_from])
        elif due_date_to:
            _, created_at_to = _day_bounds(due_date_to)
            conditions.append(
                """(
                    due_date <= ?
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source = ?
                        AND created_at < ?
                    )
                )"""
            )
            params.extend([due_date_to, "Tại tiệm - POS", created_at_to])

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        if active_only:
            rows = conn.execute(
                f"SELECT * FROM orders {where} ORDER BY id DESC",
                params,
            ).fetchall()
            result = []
            for r in rows:
                order = Order.from_row(r, conn)
                if order.status == "delivered" and order.amount_paid >= order.total_price:
                    continue
                result.append(order.to_api_dict())
            return result

        active_statuses = {"new", "confirmed", "in_progress", "ready", "delivered"}
        if status and status in active_statuses:
            rows = conn.execute(
                f"SELECT * FROM orders {where} ORDER BY id DESC",
                params,
            ).fetchall()
            result = []
            for r in rows:
                order = Order.from_row(r, conn)
                if order.status == "delivered" and order.amount_paid >= order.total_price:
                    continue
                result.append(order.to_api_dict())
            return result

        rows = conn.execute(
            f"SELECT * FROM orders {where} ORDER BY id DESC LIMIT ? OFFSET ?",
            params + [limit, offset],
        ).fetchall()

        return [Order.from_row(r, conn).to_api_dict() for r in rows]


@router.post("", status_code=201)
def create_order(body: OrderCreate, request: Request):
    """Tạo đơn hàng mới."""
    if body.dueDate is None or body.dueDate.strip() == "":
        raise HTTPException(status_code=422, detail="Vui lòng chọn ngày nhận/giao bánh")

    with get_db() as conn:
        public_order_code = _generate_unique_public_order_code(conn, body.dueDate, body.deliveryType)
        order = Order(
            customer_name=body.customerName,
            customer_phone=body.customerPhone,
            items=[_item_in_to_model(i) for i in body.items],
            due_date=body.dueDate,
            due_time=body.dueTime,
            delivery_type=body.deliveryType,
            delivery_address=body.deliveryAddress,
            notes=body.notes,
            source=body.source,
            created_by=body.createdBy,
            shipping_fee=body.shippingFee,
            public_order_code=public_order_code,
        )
        order.calculate_total()
        order.save(conn)

        _log_order_history(conn, order.id, "created", changed_by=body.createdBy)

        # Create order_items rows so work item IDs are available for photo linking
        for position, item in enumerate(body.items):
            work_item = WorkItem(
                order_id=order.id,
                product_id=item.productId,
                product_name=item.productName,
                quantity=item.quantity,
                unit_price=item.unitPrice,
                notes=item.notes,
                position=position,
                is_birthday=item.isBirthday,
                age=item.age,
                is_extra=item.isExtra,
                is_gift=item.isGift,
                attributes=item.attributes,
                price_chip_id=item.priceChipId,
            )
            work_item.save(conn)

        if body.deposit and body.deposit.amount > 0:
            txn = PaymentTransaction(
                order_id=order.id,
                amount=body.deposit.amount,
                type="deposit",
                method=body.deposit.method,
            )
            txn.save(conn)

        # POS quick-sale: always record payment if paymentMethod is provided
        if body.paymentMethod and body.paymentMethod != "none":
            total_price = float(order.total_price)
            if total_price > 0:
                txn = PaymentTransaction(
                    order_id=order.id,
                    amount=total_price,
                    type="payment",
                    method=body.paymentMethod,
                )
                txn.save(conn)
                _log_order_history(conn, order.id, "payment", "amount",
                                   old_value="", new_value=str(total_price),
                                   changed_by=body.createdBy)

        # If status='delivered', also update order status and decrement stock
        if body.status == "delivered":
            Order.update_status(conn, order.order_ref, "delivered", "")
            _log_order_history(conn, order.id, "status_change", "status",
                               "new", "delivered", body.createdBy)
            auto_decrement_stock(conn, order.id, order.order_ref)

            # Auto-generate revenue conversion + COGS journal entries (DG-175).
            from baker.services.journal_sync import _sync_delivered_order_journal, run_journal_sync
            run_journal_sync(
                _sync_delivered_order_journal,
                conn, order.id, order.order_ref,
                log_label=f"delivered order journal sync for order {order.id}",
            )

        log_context(request, ref_type="order", ref_id=order.id)
        row = conn.execute("SELECT * FROM orders WHERE id = ?", (order.id,)).fetchone()
        return _order_detail(conn, row)


@router.get("/{ref}/events")
def get_order_events(ref: str):
    """Danh sách sự kiện liên kết với đơn hàng, sắp xếp mới nhất trước."""
    with get_db() as conn:
        order_row = conn.execute(
            "SELECT id FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not order_row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        rows = conn.execute(
            "SELECT * FROM events WHERE order_id = ? ORDER BY timestamp DESC",
            (order_row["id"],),
        ).fetchall()

        from baker.api.events import _row_to_dict
        return [_row_to_dict(r) for r in rows]


@router.get("/{ref}")
def get_order(ref: str):
    """Chi tiết đơn hàng theo order_ref hoặc id."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
        return _order_detail(conn, row)


@router.patch("/{ref}")
def edit_order(ref: str, body: OrderEdit):
    """Cập nhật thông tin đơn hàng."""
    data = body.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        updates = []
        params: list = []
        public_code_update = None

        field_map = {
            "customerName": "customer_name",
            "customerPhone": "customer_phone",
            "dueDate": "due_date",
            "dueTime": "due_time",
            "deliveryType": "delivery_type",
            "deliveryAddress": "delivery_address",
            "notes": "notes",
            "source": "source",
            "shippingFee": "shipping_fee",
            "workTicketPrintedAt": "work_ticket_printed_at",
        }

        new_due_date = data.get("dueDate", row["due_date"])
        new_delivery_type = data.get("deliveryType", row["delivery_type"])
        due_date_changed = "dueDate" in data and data["dueDate"] != row["due_date"]
        delivery_type_changed = "deliveryType" in data and data["deliveryType"] != row["delivery_type"]
        current_public_code = row["public_order_code"] or ""

        if due_date_changed and current_public_code:
            decision = data.get("publicCodeDateChangeDecision")
            if decision not in {"keep", "regenerate"}:
                raise HTTPException(
                    status_code=422,
                    detail="Vui lòng chọn giữ mã hoặc tạo mã mới khi đổi ngày nhận/giao",
                )

            if decision == "regenerate":
                new_public_code = _generate_unique_public_order_code(conn, new_due_date, new_delivery_type)
                updates.append("public_order_code = ?")
                params.append(new_public_code)
                public_code_update = {
                    "action": "regenerated",
                    "reason": "due_date_changed",
                    "previousCode": current_public_code,
                    "currentCode": new_public_code,
                }
                current_public_code = new_public_code
            else:
                if _public_code_exists_for_due_date(conn, new_due_date, current_public_code, row["id"]):
                    new_public_code = _generate_unique_public_order_code(conn, new_due_date, new_delivery_type)
                    updates.append("public_order_code = ?")
                    params.append(new_public_code)
                    public_code_update = {
                        "action": "regenerated",
                        "reason": "due_date_conflict_after_keep",
                        "previousCode": current_public_code,
                        "currentCode": new_public_code,
                    }
                    current_public_code = new_public_code
                else:
                    public_code_update = {
                        "action": "kept",
                        "reason": "due_date_changed",
                        "previousCode": current_public_code,
                        "currentCode": current_public_code,
                    }

        if delivery_type_changed and current_public_code:
            suffix_updated_code = _replace_public_code_suffix(current_public_code, new_delivery_type)
            if _public_code_exists_for_due_date(conn, new_due_date, suffix_updated_code, row["id"]):
                suffix_updated_code = _generate_unique_public_order_code(conn, new_due_date, new_delivery_type)
                action = "suffix_updated_regenerated"
                reason = "delivery_type_conflict"
            else:
                action = "suffix_updated"
                reason = "delivery_type_changed"

            if suffix_updated_code != current_public_code:
                updates.append("public_order_code = ?")
                params.append(suffix_updated_code)
                public_code_update = {
                    "action": action,
                    "reason": reason,
                    "previousCode": current_public_code,
                    "currentCode": suffix_updated_code,
                }
                current_public_code = suffix_updated_code

        for camel, snake in field_map.items():
            if camel in data:
                updates.append(f"{snake} = ?")
                params.append(data[camel])

        items_changed = "items" in data
        shipping_fee_changed = "shippingFee" in data
        if items_changed or shipping_fee_changed:
            if items_changed:
                items = [_item_in_to_model(OrderItemIn(**i)) for i in data["items"]]
                items_json = json.dumps([i.to_dict() for i in items])
                updates.append("items = ?")
                params.append(items_json)
            else:
                # Read existing items directly from DB JSON for total recalculation
                raw_items = json.loads(row["items"])
            current_shipping_fee = data.get("shippingFee", row["shipping_fee"])
            if items_changed:
                subtotal = sum(i.qty * i.price for i in items if not i.is_gift)
                cash_fee = sum(
                    float(i.attributes.get("cash_fee", 0))
                    for i in items
                    if i.attributes.get("rut_tien") == "true" and i.attributes.get("cash_fee")
                )
            else:
                subtotal = sum(
                    i.get("quantity", i.get("qty", 1)) * i.get("unit_price", i.get("price", 0))
                    for i in raw_items if not i.get("is_gift", False)
                )
                cash_fee = 0
                for i in raw_items:
                    attrs = i.get("attributes") or {}
                    if attrs.get("rut_tien") == "true" and attrs.get("cash_fee"):
                        try:
                            cash_fee += float(attrs["cash_fee"])
                        except (TypeError, ValueError):
                            pass
            total = subtotal + cash_fee + current_shipping_fee
            updates.append("total_price = ?")
            params.append(total)

        if not updates:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        updates.append("updated_at = ?")
        params.append(now_iso())
        params.append(row["id"])
        conn.execute(
            f"UPDATE orders SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        # Re-sync payment journal entries when shipping_fee changes on a bus order (DG-191 Phase 4).
        if (shipping_fee_changed or delivery_type_changed) and row["delivery_type"] == "bus":
            from baker.services.journal_sync import _sync_payment_journal, run_journal_sync

            txn_rows = conn.execute(
                "SELECT id, amount, type, method FROM payment_transactions WHERE order_id = ?",
                (row["id"],),
            ).fetchall()
            for txn_row in txn_rows:
                run_journal_sync(
                    _sync_payment_journal,
                    conn,
                    txn_row["id"],
                    float(txn_row["amount"]),
                    txn_row["type"],
                    txn_row["method"],
                    order_id=row["id"],
                    log_label=f"payment journal re-sync for order {row['id']} after shipping_fee edit",
                )

        # Log each changed field with old/new values
        changed_by = data.get("changedBy", "")
        for camel, snake in field_map.items():
            if camel in data:
                _log_order_history(conn, row["id"], "field_edit", snake, str(row[snake]), str(data[camel]), changed_by)
        if items_changed:
            _log_order_history(conn, row["id"], "field_edit", "items", row["items"], items_json, changed_by)
        if public_code_update and public_code_update["previousCode"] != public_code_update["currentCode"]:
            _log_order_history(
                conn,
                row["id"],
                "field_edit",
                "public_order_code",
                public_code_update["previousCode"],
                public_code_update["currentCode"],
                changed_by,
            )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        response = _order_detail(conn, updated)
        response["publicOrderCodeUpdate"] = public_code_update or {
            "action": "unchanged",
            "reason": "none",
            "previousCode": row["public_order_code"] or "",
            "currentCode": updated["public_order_code"] or "",
        }
        return response


@router.post("/{ref}/status")
def transition_status(ref: str, body: StatusTransition):
    """Chuyển trạng thái đơn hàng. Lý do bắt buộc khi lùi trạng thái."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            _raise_status_transition_rejection(
                requested_ref=ref,
                order_row=None,
                target_status=body.status,
                status_code=404,
                rejection_detail="Không tìm thấy đơn hàng",
            )

        if is_backward_transition(row["status"], body.status) and not body.reason.strip():
            _raise_status_transition_rejection(
                requested_ref=ref,
                order_row=row,
                target_status=body.status,
                status_code=422,
                rejection_detail="Lý do là bắt buộc khi lùi trạng thái",
            )

        # Block completion if not fully paid
        if body.status == "completed":
            total_paid = PaymentTransaction.total_paid_excl_outflows(conn, row["id"])
            total_price = float(row["total_price"])
            if total_paid < total_price:
                remaining = total_price - total_paid
                _raise_status_transition_rejection(
                    requested_ref=ref,
                    order_row=row,
                    target_status=body.status,
                    status_code=422,
                    rejection_detail=f"Chưa thanh toán đủ để hoàn thành đơn hàng — còn thiếu {remaining:,.0f}đ",
                )

        # Auto-decrement stock for trưng bày products when order is confirmed
        # (POS already handles this in create_order for status=delivered)
        if body.status == "confirmed":
            auto_decrement_stock(conn, row["id"], row["order_ref"])

        if body.status == "cancelled":
            restore_stock_for_order(conn, row["id"], row["order_ref"])

        success = Order.update_status(conn, row["order_ref"], body.status, body.reason)
        if not success:
            _raise_status_transition_rejection(
                requested_ref=ref,
                order_row=row,
                target_status=body.status,
                status_code=422,
                rejection_detail="Không thể chuyển trạng thái",
            )

        _log_order_history(conn, row["id"], "status_change", "status", row["status"], body.status, body.changedBy)

        # When transitioning TO delivered, generate revenue conversion + COGS journal (DG-175).
        if body.status == "delivered" and row["status"] != "delivered":
            from baker.services.journal_sync import _sync_delivered_order_journal, run_journal_sync
            run_journal_sync(
                _sync_delivered_order_journal,
                conn, row["id"], row["order_ref"],
                log_label=f"delivered order journal sync for order {row['id']}",
            )

        # Auto-cascade confirmed order status to main items (non-extra, non-gift) at pending (F5)
        if body.status == "confirmed":
            conn.execute(
                "UPDATE order_items SET status = 'confirmed' WHERE order_id = ? AND is_extra = 0 AND is_gift = 0 AND status = 'pending'",
                (row["id"],),
            )

        # Auto-sync extras/gifts to match the new order status (F4, F5)
        from baker.api.work_items import sync_extras_to_order_status
        sync_extras_to_order_status(conn, row["id"], body.status)

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated)


@router.patch("/{ref}/payment-method")
def update_payment_method(ref: str, body: PaymentMethodUpdate):
    """Cập nhật hình thức thanh toán trên giao dịch mới nhất."""
    if body.method not in ("cash", "transfer"):
        raise HTTPException(status_code=422, detail="Hình thức thanh toán không hợp lệ")

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        # Update the latest payment transaction's method
        txn_row = conn.execute(
            "SELECT id, amount, type FROM payment_transactions WHERE order_id = ? ORDER BY id DESC LIMIT 1",
            (row["id"],),
        ).fetchone()
        if not txn_row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch thanh toán")

        conn.execute(
            "UPDATE payment_transactions SET method = ? WHERE id = ?",
            (body.method, txn_row["id"]),
        )
        _log_order_history(conn, row["id"], "field_edit", "payment_method", "", body.method, "")

        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync

        run_journal_sync(
            _sync_payment_journal,
            conn, txn_row["id"], txn_row["amount"], txn_row["type"], body.method,
            order_id=row["id"],
            log_label=f"payment journal re-sync after method change for txn {txn_row['id']}",
        )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated)


@router.patch("/{ref}/payment")
def update_payment(ref: str, body: PaymentUpdate):
    """Ghi nhận thanh toán (tạo giao dịch mới nếu số tiền > 0)."""
    if body.amountPaid < 0:
        raise HTTPException(status_code=422, detail="Số tiền thanh toán không được âm")

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        if body.amountPaid > 0:
            txn = PaymentTransaction(
                order_id=row["id"],
                amount=body.amountPaid,
                type="payment",
                method="cash",
            )
            txn.save(conn)
            _log_order_history(
                conn, row["id"], "payment", "amount",
                old_value="", new_value=str(body.amountPaid), changed_by=body.changedBy,
            )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated)
