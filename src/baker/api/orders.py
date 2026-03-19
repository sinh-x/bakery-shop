"""Order management API routes."""

from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.order import Order, OrderItem, allowed_transitions, validate_transition


router = APIRouter(prefix="/api/orders", tags=["orders"])


class OrderItemIn(BaseModel):
    productId: str = ""
    productName: str
    quantity: int = 1
    unitPrice: float = 0.0
    notes: str = ""


class OrderCreate(BaseModel):
    customerName: str
    customerPhone: str = ""
    items: list[OrderItemIn] = []
    dueDate: Optional[str] = None
    dueTime: Optional[str] = None
    deliveryType: str = "pickup"
    deliveryAddress: str = ""
    notes: str = ""


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
    )


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
        )
        order.calculate_total()
        order.save(conn)

        row = conn.execute("SELECT * FROM orders WHERE id = ?", (order.id,)).fetchone()
        return Order.from_row(row).to_api_dict()


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
        return Order.from_row(row).to_api_dict()


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
            items_json = __import__("json").dumps([i.to_dict() for i in items])
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
        return Order.from_row(updated).to_api_dict()


@router.post("/{ref}/status")
def transition_status(ref: str, body: StatusTransition):
    """Chuyển trạng thái đơn hàng."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        current = row["status"]
        if not validate_transition(current, body.status):
            allowed = allowed_transitions(current)
            raise HTTPException(
                status_code=422,
                detail=f"Không thể chuyển từ '{current}' sang '{body.status}'. Cho phép: {allowed}",
            )

        success = Order.update_status(conn, row["order_ref"], body.status, body.reason)
        if not success:
            raise HTTPException(status_code=422, detail="Không thể chuyển trạng thái")

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return Order.from_row(updated).to_api_dict()


@router.patch("/{ref}/payment")
def update_payment(ref: str, body: PaymentUpdate):
    """Cập nhật số tiền đã thanh toán."""
    if body.amountPaid < 0:
        raise HTTPException(status_code=422, detail="Số tiền thanh toán không được âm")

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        conn.execute(
            "UPDATE orders SET amount_paid = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime') WHERE id = ?",
            (body.amountPaid, row["id"]),
        )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return Order.from_row(updated).to_api_dict()
