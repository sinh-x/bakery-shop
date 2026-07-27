from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from baker.utils.time import now_utc


class WorkItemStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    WORKING = "working"
    READY = "ready"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


@dataclass
class BlankAssignment:
    """A blank assigned to a work item via the ``order_item_blanks`` junction
    table (DG-294). Many blanks may be assigned to a single work item, each
    with its own ``quantity`` and ``notes``."""

    blank_id: int
    order_item_id: Optional[int] = None
    quantity: float = 1.0
    notes: str = ""
    id: Optional[int] = None
    created_at: Optional[str] = None

    @staticmethod
    def from_row(row) -> "BlankAssignment":
        keys = row.keys() if hasattr(row, "keys") else []
        return BlankAssignment(
            id=row["id"] if "id" in keys else None,
            order_item_id=row["order_item_id"] if "order_item_id" in keys else None,
            blank_id=row["blank_id"],
            quantity=float(row["quantity"]) if "quantity" in keys else 1.0,
            notes=row["notes"] if "notes" in keys else "",
            created_at=row["created_at"] if "created_at" in keys else None,
        )

    def to_api_dict(self) -> dict:
        return {
            "id": self.id,
            "orderItemId": self.order_item_id,
            "blankId": self.blank_id,
            "quantity": self.quantity,
            "notes": self.notes,
            "createdAt": self.created_at,
        }


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
    is_extra: bool = False
    is_gift: bool = False
    attributes: dict = field(default_factory=dict)
    price_chip_id: Optional[int] = None
    blanks: list = field(default_factory=list)
    assigned_price: Optional[float] = None
    id: Optional[int] = None
    created_at: Optional[str] = None

    def save(self, conn) -> int:
        import json
        attrs_json = json.dumps(self.attributes)
        # ``assigned_price`` was added in migration v84 (DG-296 Phase 1).
        # Older databases that have not yet reached v84 do not have the
        # column yet — detect it and omit it from the INSERT so writes
        # succeed at every migration stage (FR8 backward compatibility,
        # parity with journal_sync.py and accounting_validation.py).
        oi_columns = {
            r[1] for r in conn.execute("PRAGMA table_info(order_items)").fetchall()
        }
        has_assigned_price = "assigned_price" in oi_columns
        if has_assigned_price:
            cursor = conn.execute(
                """INSERT INTO order_items
                   (order_id, product_id, product_name, quantity, unit_price, notes, position, status, is_birthday, age, is_extra, is_gift, attributes, price_chip_id, assigned_price, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
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
                    1 if self.is_extra else 0,
                    1 if self.is_gift else 0,
                    attrs_json,
                    self.price_chip_id,
                    self.assigned_price,
                    now_utc(),
                ),
            )
        else:
            cursor = conn.execute(
                """INSERT INTO order_items
                   (order_id, product_id, product_name, quantity, unit_price, notes, position, status, is_birthday, age, is_extra, is_gift, attributes, price_chip_id, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
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
                    1 if self.is_extra else 0,
                    1 if self.is_gift else 0,
                    attrs_json,
                    self.price_chip_id,
                    now_utc(),
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
        import json
        keys = row.keys() if hasattr(row, "keys") else []
        attrs = {}
        if "attributes" in keys and row["attributes"]:
            try:
                attrs = json.loads(row["attributes"]) if isinstance(row["attributes"], str) else row["attributes"]
            except (json.JSONDecodeError, TypeError):
                attrs = {}
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
            is_extra=bool(row["is_extra"]) if "is_extra" in keys else False,
            is_gift=bool(row["is_gift"]) if "is_gift" in keys else False,
            attributes=attrs,
            price_chip_id=row["price_chip_id"] if "price_chip_id" in keys else None,
            blanks=[],
            assigned_price=row["assigned_price"] if "assigned_price" in keys else None,
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
            "isExtra": self.is_extra,
            "isGift": self.is_gift,
            "attributes": self.attributes,
            "priceChipId": self.price_chip_id,
            "blanks": [b.to_api_dict() if isinstance(b, BlankAssignment) else b for b in self.blanks],
            "assignedPrice": self.assigned_price,
            "createdAt": self.created_at,
        }
