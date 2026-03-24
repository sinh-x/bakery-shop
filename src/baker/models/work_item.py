from dataclasses import dataclass
from enum import Enum
from typing import Optional


class WorkItemStatus(str, Enum):
    PENDING = "pending"
    WORKING = "working"
    READY = "ready"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


@dataclass
class WorkItem:
    order_id: int
    product_name: str
    quantity: int = 1
    unit_price: float = 0.0
    notes: str = ""
    product_id: str = ""
    position: int = 0
    status: str = "pending"
    is_birthday: bool = False
    age: Optional[int] = None
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        cursor = conn.execute(
            """INSERT INTO order_items
               (order_id, product_id, product_name, quantity, unit_price, notes, position, status, is_birthday, age)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                self.order_id,
                self.product_id,
                self.product_name,
                self.quantity,
                self.unit_price,
                self.notes,
                self.position,
                self.status,
                1 if self.is_birthday else 0,
                self.age,
            ),
        )
        self.id = cursor.lastrowid
        return self.id

    def update_status(self, conn, new_status: str) -> bool:
        if new_status not in [s.value for s in WorkItemStatus]:
            return False
        conn.execute(
            "UPDATE order_items SET status = ? WHERE id = ?",
            (new_status, self.id),
        )
        self.status = new_status
        return True

    @staticmethod
    def from_row(row) -> "WorkItem":
        keys = row.keys() if hasattr(row, "keys") else []
        return WorkItem(
            id=row["id"],
            order_id=row["order_id"],
            product_id=row["product_id"] or "",
            product_name=row["product_name"],
            quantity=row["quantity"],
            unit_price=row["unit_price"],
            notes=row["notes"] or "",
            position=row["position"],
            status=row["status"],
            is_birthday=bool(row["is_birthday"]) if "is_birthday" in keys else False,
            age=row["age"] if "age" in keys else None,
            created_at=row["created_at"],
        )

    def to_api_dict(self) -> dict:
        return {
            "id": str(self.id),
            "orderId": str(self.order_id),
            "productId": self.product_id,
            "productName": self.product_name,
            "quantity": self.quantity,
            "unitPrice": self.unit_price,
            "notes": self.notes,
            "position": self.position,
            "status": self.status,
            "isBirthday": self.is_birthday,
            "age": self.age,
            "createdAt": self.created_at,
        }
