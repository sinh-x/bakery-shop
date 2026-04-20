"""Order management API routes."""

import json
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field

from baker.db.connection import get_db
from baker.logging import log_context
from baker.models.order import Order, OrderItem, is_backward_transition, validate_transition
from baker.models.payment_transaction import PaymentTransaction
from baker.models.work_item import WorkItem


router = APIRouter(prefix="/api/orders", tags=["orders"])


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
    """Auto-decrement stock for trưng bày products when order completes."""
    from baker.models.event import Event

    order_items = conn.execute(
        """SELECT oi.product_id, oi.product_name, oi.quantity
           FROM order_items oi
           WHERE oi.order_id = ?
             AND oi.product_id != ''
             AND oi.is_gift = 0""",
        (order_id,),
    ).fetchall()

    for item in order_items:
        code_or_id = item["product_id"]
        product_row = conn.execute(
            "SELECT id FROM products WHERE product_code = ?",
            (code_or_id,),
        ).fetchone()
        if not product_row:
            try:
                product_row = conn.execute(
                    "SELECT id FROM products WHERE id = ?",
                    (int(code_or_id),),
                ).fetchone()
            except (ValueError, TypeError):
                continue
        if not product_row:
            continue

        product_id = product_row["id"]
        qty = item["quantity"]

        attr_row = conn.execute(
            """SELECT value FROM product_attribute_values
               WHERE product_id = ? AND attribute_type = 'trung_bay'""",
            (product_id,),
        ).fetchone()
        if not attr_row or attr_row["value"] != "true":
            continue

        stock_row = conn.execute(
            "SELECT quantity FROM product_stock WHERE product_id = ?",
            (product_id,),
        ).fetchone()
        if stock_row:
            conn.execute(
                "UPDATE product_stock SET quantity = ? WHERE product_id = ?",
                (max(0, stock_row["quantity"] - qty), product_id),
            )
        else:
            conn.execute(
                "INSERT INTO product_stock (product_id, quantity) VALUES (?, 0)",
                (product_id,),
            )

        conn.execute(
            """INSERT INTO stock_movements
               (product_id, movement_type, quantity, reason, reference_id)
               VALUES (?, 'sale', ?, ?, ?)""",
            (product_id, -qty, f"Order {order_ref}", order_ref),
        )
        Event(
            summary=f"Bán hàng -{qty} {item['product_name']}",
            type="inventory",
            data={
                "product_id": product_id,
                "product_name": item["product_name"],
                "movement_type": "sale",
                "quantity": -qty,
                "reference_id": order_ref,
            },
        ).save(conn)


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


@router.get("")
def list_orders(
    status: Optional[str] = Query(None, description="Lọc theo trạng thái"),
    due_date: Optional[str] = Query(None, description="Lọc theo ngày giao (YYYY-MM-DD)"),
    limit: int = Query(50, description="Số lượng tối đa"),
    offset: int = Query(0, description="Bỏ qua N đơn đầu"),
):
    """Danh sách đơn hàng."""
    with get_db() as conn:
        conditions = []
        params: list = []

        if status:
            conditions.append("status = ?")
            params.append(status)

        if due_date:
            conditions.append("due_date = ?")
            params.append(due_date)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        rows = conn.execute(
            f"SELECT * FROM orders {where} ORDER BY id DESC LIMIT ? OFFSET ?",
            params + [limit, offset],
        ).fetchall()

        return [Order.from_row(r, conn).to_api_dict() for r in rows]


@router.post("", status_code=201)
def create_order(body: OrderCreate, request: Request):
    """Tạo đơn hàng mới."""
    with get_db() as conn:
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
            _auto_decrement_stock(conn, order.id, order.order_ref)

        log_context(request, ref_type="order", ref_id=order.id)
        row = conn.execute("SELECT * FROM orders WHERE id = ?", (order.id,)).fetchone()
        return _order_detail(conn, row)


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

        updates.append("updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')")
        params.append(row["id"])
        conn.execute(
            f"UPDATE orders SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        # Log each changed field with old/new values
        changed_by = data.get("changedBy", "")
        for camel, snake in field_map.items():
            if camel in data:
                _log_order_history(conn, row["id"], "field_edit", snake, str(row[snake]), str(data[camel]), changed_by)
        if items_changed:
            _log_order_history(conn, row["id"], "field_edit", "items", row["items"], items_json, changed_by)

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated)


@router.post("/{ref}/status")
def transition_status(ref: str, body: StatusTransition):
    """Chuyển trạng thái đơn hàng. Lý do bắt buộc khi lùi trạng thái."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        if is_backward_transition(row["status"], body.status) and not body.reason.strip():
            raise HTTPException(
                status_code=422, detail="Lý do là bắt buộc khi lùi trạng thái"
            )

        # Block completion if not fully paid
        if body.status == "completed":
            total_paid = PaymentTransaction.total_paid_excl_tien_rut(conn, row["id"])
            total_price = float(row["total_price"])
            if total_paid < total_price:
                remaining = total_price - total_paid
                raise HTTPException(
                    status_code=422,
                    detail=f"Chưa thanh toán đủ để hoàn thành đơn hàng — còn thiếu {remaining:,.0f}đ",
                )

        # Auto-decrement stock for trưng bày products when order completes
        if body.status == "completed":
            _auto_decrement_stock(conn, row["id"], row["order_ref"])

        success = Order.update_status(conn, row["order_ref"], body.status, body.reason)
        if not success:
            raise HTTPException(status_code=422, detail="Không thể chuyển trạng thái")

        _log_order_history(conn, row["id"], "status_change", "status", row["status"], body.status, body.changedBy)

        # Auto-cascade confirmed order status to main items (non-extra, non-gift) at pending (F5)
        if body.status == "confirmed":
            conn.execute(
                "UPDATE order_items SET status = 'confirmed' WHERE order_id = ? AND is_extra = 0 AND is_gift = 0 AND status = 'pending'",
                (row["id"],),
            )

        # Auto-sync extras/gifts to match the new order status (F4, F5)
        from baker.api.work_items import _sync_extras_to_order_status
        _sync_extras_to_order_status(conn, row["id"], body.status)

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
            "SELECT id FROM payment_transactions WHERE order_id = ? ORDER BY id DESC LIMIT 1",
            (row["id"],),
        ).fetchone()
        if not txn_row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch thanh toán")

        conn.execute(
            "UPDATE payment_transactions SET method = ? WHERE id = ?",
            (body.method, txn_row["id"]),
        )
        _log_order_history(conn, row["id"], "field_edit", "payment_method", "", body.method, "")

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
