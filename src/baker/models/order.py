import json
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional

from baker.models.event import Event


class OrderStatus(str, Enum):
    NEW = "new"
    CONFIRMED = "confirmed"
    IN_PROGRESS = "in_progress"
    READY = "ready"
    DELIVERED = "delivered"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


TRANSITIONS = {
    OrderStatus.NEW: [OrderStatus.CONFIRMED, OrderStatus.CANCELLED],
    OrderStatus.CONFIRMED: [OrderStatus.IN_PROGRESS, OrderStatus.CANCELLED],
    OrderStatus.IN_PROGRESS: [OrderStatus.READY, OrderStatus.CANCELLED],
    OrderStatus.READY: [OrderStatus.DELIVERED, OrderStatus.COMPLETED, OrderStatus.CANCELLED],
    OrderStatus.DELIVERED: [OrderStatus.COMPLETED],
    OrderStatus.COMPLETED: [],
    OrderStatus.CANCELLED: [],
}

# Ordered for determining forward vs backward transitions
_ORDER_STATUS_RANK = {
    OrderStatus.NEW: 0,
    OrderStatus.CONFIRMED: 1,
    OrderStatus.IN_PROGRESS: 2,
    OrderStatus.READY: 3,
    OrderStatus.DELIVERED: 4,
    OrderStatus.COMPLETED: 5,
    OrderStatus.CANCELLED: 5,
}


def is_backward_transition(current: str, target: str) -> bool:
    """Return True if transitioning to a lower-ranked status."""
    try:
        return _ORDER_STATUS_RANK[OrderStatus(target)] < _ORDER_STATUS_RANK[OrderStatus(current)]
    except (ValueError, KeyError):
        return False


def validate_transition(current: str, target: str) -> bool:
    try:
        return OrderStatus(target) in TRANSITIONS.get(OrderStatus(current), [])
    except ValueError:
        return False


def allowed_transitions(current: str) -> list[str]:
    try:
        return [s.value for s in TRANSITIONS.get(OrderStatus(current), [])]
    except ValueError:
        return []


def generate_order_ref(conn) -> str:
    today = datetime.now().strftime("%y%m%d")
    prefix = f"ORD-{today}-"
    cursor = conn.execute(
        "SELECT order_ref FROM orders WHERE order_ref LIKE ? ORDER BY id DESC LIMIT 1",
        (f"{prefix}%",),
    )
    row = cursor.fetchone()
    if row:
        last_num = int(row["order_ref"].split("-")[-1])
        next_num = last_num + 1
    else:
        next_num = 1
    return f"{prefix}{next_num:03d}"


@dataclass
class OrderItem:
    product: str
    qty: int = 1
    price: float = 0.0
    notes: str = ""
    product_id: str = ""
    is_birthday: bool = False
    age: Optional[int] = None
    is_extra: bool = False
    is_gift: bool = False

    def to_dict(self):
        return {
            "product": self.product,
            "qty": self.qty,
            "price": self.price,
            "notes": self.notes,
            "product_id": self.product_id,
            "is_birthday": self.is_birthday,
            "age": self.age,
            "is_extra": self.is_extra,
            "is_gift": self.is_gift,
        }

    def to_api_dict(self) -> dict:
        return {
            "productId": self.product_id,
            "productName": self.product,
            "quantity": self.qty,
            "unitPrice": self.price,
            "notes": self.notes,
            "isBirthday": self.is_birthday,
            "age": self.age,
            "isExtra": self.is_extra,
            "isGift": self.is_gift,
        }

    @staticmethod
    def parse(spec: str) -> "OrderItem":
        """Parse 'Product Name x2 @45.00' format."""
        parts = spec.strip()
        price = 0.0
        qty = 1

        if "@" in parts:
            parts, price_str = parts.rsplit("@", 1)
            price = float(price_str.strip())

        parts = parts.strip()
        if " x" in parts.lower():
            idx = parts.lower().rfind(" x")
            try:
                qty = int(parts[idx + 2:].strip())
                parts = parts[:idx].strip()
            except ValueError:
                pass

        return OrderItem(product=parts, qty=qty, price=price)


@dataclass
class Order:
    customer_name: str
    items: list[OrderItem] = field(default_factory=list)
    order_ref: str = ""
    total_price: float = 0.0
    status: str = "new"
    due_date: Optional[str] = None
    due_time: Optional[str] = None
    delivery_type: str = "pickup"
    delivery_address: str = ""
    customer_phone: str = ""
    notes: str = ""
    amount_paid: float = 0.0
    source: str = ""
    created_by: str = ""
    shipping_fee: float = 0.0
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    def calculate_total(self):
        # Sum only non-gift items + shipping_fee
        subtotal = sum(item.qty * item.price for item in self.items if not item.is_gift)
        self.total_price = subtotal + self.shipping_fee

    def save(self, conn) -> int:
        if not self.order_ref:
            self.order_ref = generate_order_ref(conn)
        if not self.total_price:
            self.calculate_total()

        items_json = json.dumps([i.to_dict() for i in self.items])
        cursor = conn.execute(
            """INSERT INTO orders (order_ref, customer_name, customer_phone, items,
               total_price, status, due_date, due_time, delivery_type,
               delivery_address, notes, amount_paid, source, created_by, shipping_fee)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (self.order_ref, self.customer_name, self.customer_phone,
             items_json, self.total_price, self.status, self.due_date,
             self.due_time, self.delivery_type, self.delivery_address, self.notes,
             self.amount_paid, self.source, self.created_by, self.shipping_fee),
        )
        self.id = cursor.lastrowid

        Event(
            summary=f"Order {self.order_ref} created for {self.customer_name}",
            type="order",
            data={"order_ref": self.order_ref, "action": "created",
                  "customer": self.customer_name, "total": self.total_price},
        ).save(conn)

        return self.id

    @staticmethod
    def update_status(conn, order_ref: str, new_status: str, reason: str) -> bool:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (order_ref, order_ref),
        ).fetchone()
        if not row:
            return False

        current = row["status"]

        # Validate target is a known status value
        try:
            OrderStatus(new_status)
        except ValueError:
            return False

        # Backward transitions require a reason
        if is_backward_transition(current, new_status) and not reason:
            return False

        conn.execute(
            "UPDATE orders SET status = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime') WHERE id = ?",
            (new_status, row["id"]),
        )

        data = {"order_ref": row["order_ref"], "from_status": current, "to_status": new_status}
        if reason:
            data["reason"] = reason
        Event(
            summary=f"Order {row['order_ref']} status: {current} -> {new_status}",
            type="order",
            data=data,
        ).save(conn)

        return True

    @staticmethod
    def from_row(row, conn=None) -> "Order":
        items_data = json.loads(row["items"]) if row["items"] else []
        items = [OrderItem(**i) for i in items_data]

        if conn is not None:
            from baker.models.payment_transaction import PaymentTransaction
            amount_paid = PaymentTransaction.total_for_order(conn, row["id"])
        else:
            amount_paid = row["amount_paid"] or 0.0

        return Order(
            id=row["id"], order_ref=row["order_ref"],
            customer_name=row["customer_name"], customer_phone=row["customer_phone"],
            items=items, total_price=row["total_price"], status=row["status"],
            due_date=row["due_date"], due_time=row["due_time"],
            delivery_type=row["delivery_type"], delivery_address=row["delivery_address"],
            notes=row["notes"], amount_paid=amount_paid,
            source=row["source"] or "",
            created_by=row["created_by"] if "created_by" in row.keys() else "",
            shipping_fee=row["shipping_fee"] if "shipping_fee" in row.keys() else 0.0,
            created_at=row["created_at"], updated_at=row["updated_at"],
        )

    def to_api_dict(self) -> dict:
        """Return Dart-compatible camelCase JSON representation."""
        return {
            "id": str(self.id),
            "orderRef": self.order_ref,
            "customerName": self.customer_name,
            "customerPhone": self.customer_phone,
            "items": [i.to_api_dict() for i in self.items],
            "totalPrice": self.total_price,
            "status": self.status,
            "dueDate": self.due_date,
            "dueTime": self.due_time,
            "deliveryType": self.delivery_type,
            "deliveryAddress": self.delivery_address,
            "notes": self.notes,
            "source": self.source,
            "createdBy": self.created_by,
            "amountPaid": self.amount_paid,
            "shippingFee": self.shipping_fee,
            "isPaid": self.amount_paid > 0 and self.amount_paid >= self.total_price,
            "packingChecklist": [],
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }
