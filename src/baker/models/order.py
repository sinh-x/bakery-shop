import json
import random
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from enum import Enum
from typing import Optional

from baker import config
from baker.models.event import Event
from baker.utils.time import now_utc

# Delivery types that use the early critical threshold (FR2/FR6).
# Shared between compute_urgency() and Order.compute_completeness() so the
# transit set stays in sync (MINOR-2, DG-253 Phase 5.6-c1).
TRANSIT_DELIVERY_TYPES = ("delivery", "bus", "door")


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


class UrgencyTier(str, Enum):
    CRITICAL = "critical"
    URGENT = "urgent"
    NORMAL = "normal"


class CompletenessTier(str, Enum):
    COMPLETE = "complete"
    INCOMPLETE = "incomplete"


WALK_IN_CUSTOMER_NAME = "Khách"


def is_junk_phone(phone: str) -> bool:
    """Detect junk/placeholder phone numbers.

    Strip non-digits; flag if:
    - length < 10, OR
    - all same digit, OR
    - sequential ascending (e.g. 0123456789), OR
    - sequential descending (e.g. 9876543210), OR
    - fewer than 4 unique digits.
    """
    digits = "".join(ch for ch in phone if ch.isdigit())
    if not digits or len(digits) < 10:
        return True
    if len(set(digits)) == 1:
        return True
    if all(int(digits[i]) == int(digits[i - 1]) + 1 for i in range(1, len(digits))):
        return True
    if all(int(digits[i]) == int(digits[i - 1]) - 1 for i in range(1, len(digits))):
        return True
    if len(set(digits)) < 4:
        return True
    return False


def compute_urgency(
    due_date: Optional[str],
    due_time: Optional[str],
    status: str,
    acknowledged_at: Optional[str],
    delivery_type: str = "pickup",
    threshold_minutes: Optional[int] = None,
) -> str:
    """Compute the urgency tier for an order.

    Rules (FR-1):
    - ``critical`` = past due datetime and not delivered/completed/cancelled,
      OR (delivery/bus/door only) due within the configurable early critical
      threshold (default 60 min) — prep/transit buffer.
    - ``urgent`` = due ≤ 2h from now, OR status='new' and unacknowledged,
      OR status in (new, confirmed) and due today.
    - ``normal`` = everything else.

    ``delivery_type`` defaults to ``"pickup"`` for backward compatibility.
    Only delivery/bus/door orders get the early critical threshold; pickup
    orders fall through to the existing rules.

    ``threshold_minutes`` lets callers with a DB connection pass the runtime
    override from ``get_delivery_critical_threshold(conn)`` (NFR1). When
    ``None`` (default), falls back to the module-level env var default
    ``config.DELIVERY_CRITICAL_THRESHOLD_MINUTES``. Reading via ``config.``
    (not a top-level ``TIMEZONE`` import) keeps the value live across
    ``config.reload(--config)`` (MINOR-1, DG-253 Phase 5.6-c1).
    """
    terminal = {"delivered", "completed", "cancelled"}
    if status in terminal:
        return UrgencyTier.NORMAL.value

    now = datetime.now(timezone.utc)

    # Build due datetime
    due_dt = None
    if due_date:
        try:
            if due_time:
                due_dt = datetime.strptime(f"{due_date}T{due_time}", "%Y-%m-%dT%H:%M")
                due_dt = due_dt.replace(tzinfo=config.TIMEZONE).astimezone(timezone.utc)
            else:
                due_dt = datetime.strptime(due_date, "%Y-%m-%d")
                due_dt = due_dt.replace(tzinfo=config.TIMEZONE).astimezone(timezone.utc)
        except (ValueError, TypeError):
            pass

    if due_dt:
        if due_dt < now:
            return UrgencyTier.CRITICAL.value
        # Early critical threshold for delivery/bus/door orders (FR2, FR6).
        # Caller may pass the DB override (NFR1); otherwise fall back to the
        # env-var default from baker.config so reload() stays live (MINOR-1).
        if delivery_type in TRANSIT_DELIVERY_TYPES:
            effective_threshold = (
                threshold_minutes
                if threshold_minutes is not None
                else config.DELIVERY_CRITICAL_THRESHOLD_MINUTES
            )
            # Defensive cap (DG-253 review-auto r2 MAJOR): clamp to 10080 min
            # (7 days) so an out-of-range value can never reach timedelta and
            # raise OverflowError, which would 500 all order list/detail reads.
            if effective_threshold > 10080:
                effective_threshold = 10080
            if effective_threshold < 1:
                effective_threshold = 1
            if due_dt - now <= timedelta(minutes=effective_threshold):
                return UrgencyTier.CRITICAL.value
        if due_dt - now <= timedelta(hours=2):
            return UrgencyTier.URGENT.value

    if status == "new" and not acknowledged_at:
        return UrgencyTier.URGENT.value

    if status in ("new", "confirmed") and due_date:
        today_str = datetime.now(config.TIMEZONE).strftime("%Y-%m-%d")
        if due_date == today_str:
            return UrgencyTier.URGENT.value

    return UrgencyTier.NORMAL.value


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


PUBLIC_ORDER_CODE_LETTERS = "ABCDLMNV"
PUBLIC_ORDER_CODE_DIGITS = "0123456789"
PUBLIC_ORDER_CODE_MAX_REFERENCE_LEN = 6


def delivery_type_to_public_suffix(delivery_type: str) -> str:
    suffix_map = {
        "pickup": "T",
        "bus": "B",
        "delivery": "S",
    }
    return suffix_map.get(delivery_type, "S")


def generate_public_order_code_candidate(delivery_type: str, reference_len: int = 3) -> str:
    if reference_len < 3:
        reference_len = 3
    if reference_len > PUBLIC_ORDER_CODE_MAX_REFERENCE_LEN:
        reference_len = PUBLIC_ORDER_CODE_MAX_REFERENCE_LEN

    randomizer = random.SystemRandom()
    letter = randomizer.choice(PUBLIC_ORDER_CODE_LETTERS)
    digits_count = reference_len - 1
    digits = "".join(randomizer.choice(PUBLIC_ORDER_CODE_DIGITS) for _ in range(digits_count))
    return f"{letter}{digits}-{delivery_type_to_public_suffix(delivery_type)}"


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
    price_chip_id: Optional[int] = None
    attributes: dict = field(default_factory=dict)

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
            "price_chip_id": self.price_chip_id,
            "attributes": self.attributes,
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
            "priceChipId": self.price_chip_id,
            "attributes": self.attributes,
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
    delivery_phone: str = ""
    notes: str = ""
    source: str = ""
    created_by: str = ""
    shipping_fee: float = 0.0
    public_order_code: str = ""
    customer_id: Optional[int] = None
    id: Optional[int] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    work_ticket_printed_at: Optional[str] = None
    work_ticket_printed_by: str = ""
    acknowledged_at: Optional[str] = None
    created_staff_name: str = ""
    work_ticket_printed_staff_name: str = ""

    amount_paid = 0.0

    @staticmethod
    def exists(order_id: int, conn=None) -> bool:
        from baker.db.connection import get_db
        if conn is None:
            with get_db() as conn:
                row = conn.execute("SELECT 1 FROM orders WHERE id = ?", (order_id,)).fetchone()
                return row is not None
        row = conn.execute("SELECT 1 FROM orders WHERE id = ?", (order_id,)).fetchone()
        return row is not None

    def calculate_total(self):
        # Sum only non-gift items + cash_fee from attributes + shipping_fee
        subtotal = sum(item.qty * item.price for item in self.items if not item.is_gift)
        # Extract cash_fee from attributes only when rut_tien is active
        cash_fee = sum(
            float(item.attributes.get("cash_fee", 0))
            for item in self.items
            if item.attributes.get("rut_tien") == "true" and item.attributes.get("cash_fee")
        )
        self.total_price = subtotal + cash_fee + self.shipping_fee

    def save(self, conn) -> int:
        if not self.order_ref:
            self.order_ref = generate_order_ref(conn)
        if not self.total_price:
            self.calculate_total()

        items_json = json.dumps([i.to_dict() for i in self.items])
        cursor = conn.execute(
            """INSERT INTO orders (order_ref, customer_name, customer_phone, delivery_phone, items,
               total_price, status, due_date, due_time, delivery_type,
               delivery_address, notes, source, created_by, shipping_fee, public_order_code,
               customer_id, created_at, updated_at, created_staff_name)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (self.order_ref, self.customer_name, self.customer_phone, self.delivery_phone,
              items_json, self.total_price, self.status, self.due_date,
              self.due_time, self.delivery_type, self.delivery_address, self.notes,
              self.source, self.created_by, self.shipping_fee, self.public_order_code,
              self.customer_id, now_utc(), now_utc(), self.created_staff_name),
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
            "UPDATE orders SET status = ?, updated_at = ? WHERE id = ?",
            (new_status, now_utc(), row["id"]),
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
    def from_row(row, conn, *, amount_paid: Optional[float] = None) -> "Order":
        """Build an ``Order`` from a DB row.

        ``conn`` is required (v80+ dropped the stored ``amount_paid`` column
        fallback, so the value must always be recomputed via
        ``PaymentTransaction.total_paid_excl_outflows``).

        ``amount_paid`` (keyword-only, optional) — a precomputed
        ``total_paid_excl_outflows`` value for this order. When ``None``
        (default), it is lazily computed here via
        ``PaymentTransaction.total_paid_excl_outflows(conn, row["id"])``.
        Callers that already computed it (e.g. ``list_orders`` filter checks
        in ``api/orders.py`` via ``_is_delivered_and_fully_paid``) may pass it
        via ``amount_paid=`` to avoid a duplicate query (DG-274 review-auto
        c1 / CQ-1, CQ-2). The value is cached on the returned ``Order``
        instance as ``order.amount_paid``.
        """
        items_data = json.loads(row["items"]) if row["items"] else []
        items = [OrderItem(**i) for i in items_data]

        from baker.models.payment_transaction import PaymentTransaction
        if amount_paid is None:
            amount_paid = PaymentTransaction.total_paid_excl_outflows(conn, row["id"])

        order = Order(
            id=row["id"], order_ref=row["order_ref"],
            customer_name=row["customer_name"], customer_phone=row["customer_phone"],
            delivery_phone=(row["delivery_phone"] if "delivery_phone" in row.keys() and row["delivery_phone"] is not None else ""),
            items=items, total_price=row["total_price"], status=row["status"],
            due_date=row["due_date"], due_time=row["due_time"],
            delivery_type=row["delivery_type"], delivery_address=row["delivery_address"],
            notes=row["notes"],
            source=row["source"] or "",
            created_by=row["created_by"] if "created_by" in row.keys() else "",
            shipping_fee=row["shipping_fee"] if "shipping_fee" in row.keys() else 0.0,
            public_order_code=row["public_order_code"] if "public_order_code" in row.keys() else "",
            customer_id=row["customer_id"] if "customer_id" in row.keys() else None,
            created_at=row["created_at"], updated_at=row["updated_at"],
            work_ticket_printed_at=row["work_ticket_printed_at"] if "work_ticket_printed_at" in row.keys() else None,
            work_ticket_printed_by=row["work_ticket_printed_by"] if "work_ticket_printed_by" in row.keys() else "",
            acknowledged_at=row["acknowledged_at"] if "acknowledged_at" in row.keys() else None,
            created_staff_name=row["created_staff_name"] if "created_staff_name" in row.keys() else "",
            work_ticket_printed_staff_name=row["work_ticket_printed_staff_name"] if "work_ticket_printed_staff_name" in row.keys() else "",
        )
        order.amount_paid = amount_paid
        return order

    def compute_completeness(self) -> tuple[list[str], str]:
        """Check required fields and return (missing_fields, completeness_tier).

        Required: customer_name, items, total_price, due_date, due_time,
        delivery_address (door/bus only), customer_phone, delivery_phone, source.
        """
        missing: list[str] = []

        if not self.customer_name or self.customer_name.strip() == WALK_IN_CUSTOMER_NAME:
            missing.append("customer_name")

        if not self.items or len(self.items) == 0:
            missing.append("items")

        if not self.total_price or self.total_price <= 0:
            missing.append("total_price")

        if not self.due_date:
            missing.append("due_date")

        if not self.due_time:
            missing.append("due_time")

        if self.delivery_type in TRANSIT_DELIVERY_TYPES and not self.delivery_address:
            missing.append("delivery_address")

        if not self.customer_phone or is_junk_phone(self.customer_phone):
            missing.append("customer_phone")

        if not self.delivery_phone or is_junk_phone(self.delivery_phone):
            if not self.customer_phone or is_junk_phone(self.customer_phone):
                missing.append("delivery_phone")

        if not self.source:
            missing.append("source")

        tier = CompletenessTier.INCOMPLETE.value if missing else CompletenessTier.COMPLETE.value
        return (missing, tier)

    def to_api_dict(self, threshold_minutes: Optional[int] = None) -> dict:
        """Return Dart-compatible camelCase JSON representation.

        ``threshold_minutes`` is forwarded to ``compute_urgency`` so callers
        with a DB connection can apply the runtime override from
        ``get_delivery_critical_threshold(conn)`` (NFR1, DG-253 Phase 5.6-c1).
        """
        missing_fields, completeness = self.compute_completeness()
        return {
            "id": str(self.id),
            "orderRef": self.order_ref,
            "customerName": self.customer_name,
            "customerPhone": self.customer_phone,
            "deliveryPhone": self.delivery_phone,
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
            "publicOrderCode": self.public_order_code,
            "customerId": self.customer_id,
            "isPaid": self.amount_paid > 0 and self.amount_paid >= self.total_price,
            "packingChecklist": [],
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
            "workTicketPrintedAt": self.work_ticket_printed_at,
            "workTicketPrintedBy": self.work_ticket_printed_by,
            "workTicketPrintedStaffName": self.work_ticket_printed_staff_name,
            "acknowledgedAt": self.acknowledged_at,
            "createdStaffName": self.created_staff_name,
            "urgency": compute_urgency(
                self.due_date,
                self.due_time,
                self.status,
                self.acknowledged_at,
                delivery_type=self.delivery_type,
                threshold_minutes=threshold_minutes,
            ),
            "missingFields": missing_fields,
            "completeness": completeness,
        }
