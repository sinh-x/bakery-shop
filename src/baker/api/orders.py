"""Order management API routes."""

import json
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from baker.db.connection import get_db
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


class OrderEdit(BaseModel):
    customerName: Optional[str] = None
    customerPhone: Optional[str] = None
    items: Optional[list[OrderItemIn]] = None
    dueDate: Optional[str] = None
    dueTime: Optional[str] = None
    deliveryType: Optional[str] = None
    deliveryAddress: Optional[str] = None
    notes: Optional[str] = None


class StatusTransition(BaseModel):
    status: str
    reason: str = ""


class PaymentUpdate(BaseModel):
    amountPaid: float


def _item_in_to_model(item: OrderItemIn) -> OrderItem:
    return OrderItem(
        product=item.productName,
        qty=item.quantity,
        price=item.unitPrice,
        notes=item.notes,
        product_id=item.productId,
        is_birthday=item.isBirthday,
        age=item.age,
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

        return [Order.from_row(r).to_api_dict() for r in rows]


@router.post("", status_code=201)
def create_order(body: OrderCreate):
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
        )
        order.calculate_total()
        order.save(conn)

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
        }

        for camel, snake in field_map.items():
            if camel in data:
                updates.append(f"{snake} = ?")
                params.append(data[camel])

        if "items" in data:
            items = [_item_in_to_model(OrderItemIn(**i)) for i in data["items"]]
            total = sum(i.qty * i.price for i in items)
            items_json = json.dumps([i.to_dict() for i in items])
            updates.append("items = ?")
            updates.append("total_price = ?")
            params.append(items_json)
            params.append(total)

        if not updates:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        updates.append("updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime')")
        params.append(row["id"])
        conn.execute(
            f"UPDATE orders SET {', '.join(updates)} WHERE id = ?",
            params,
        )

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

        success = Order.update_status(conn, row["order_ref"], body.status, body.reason)
        if not success:
            raise HTTPException(status_code=422, detail="Không thể chuyển trạng thái")

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

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated)
