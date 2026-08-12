"""Order management API routes."""

import json
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field, field_validator, model_validator

from baker.db.connection import get_db
from baker.db.schema import _order_year, _recompute_customer_year_summary
from baker.logging import log_context, logger
from baker.config import get_delivery_critical_threshold
from baker.models.order import (
    PUBLIC_ORDER_CODE_MAX_REFERENCE_LEN,
    Order,
    OrderItem,
    OrderStatus,
    delivery_type_to_public_suffix,
    generate_public_order_code_candidate,
    is_backward_transition,
    validate_transition,
)
from baker.models.order import _ORDER_STATUS_RANK
from baker.models.payment_transaction import PaymentTransaction
from baker.models.work_item import WorkItem
from baker.services.customer_resolver import (
    WALK_IN_SHARED_CUSTOMER_NAME,
    _get_or_create_walk_in_customer_id,
    _resolve_customer_id_by_phone,
    _resolve_or_create_customer_id,
)
from baker.services.order_stock import auto_decrement_stock, reverse_order_stock_for_edit
from baker.api.auth import resolve_actor, resolve_staff_name, resolve_staff_record
from baker.utils.time import now_utc


router = APIRouter(prefix="/api/orders", tags=["orders"])


# POS source label — orders with empty due_date are matched by created_at.
_POS_SOURCE = "Tại tiệm - POS"

# Reconciliation source label — same fallback scope as POS for NULL due_date
# (DG-384 Phase 2: include reconciliation orders in order history date filter).
_RECONCILIATION_SOURCE = "reconciliation"

# Sources that fall back to created_at when due_date is NULL/empty.
_FALLBACK_SOURCES = (_POS_SOURCE, _RECONCILIATION_SOURCE)

# DG-384 Phase 3 (FR5/NFR2): correlated subquery that returns the distinct
# payment methods for each order in a single query (no N+1). Embedded as a
# computed column in the list_orders SELECT. ``invalidated_at IS NULL``
# excludes soft-deleted transactions; the column always exists at runtime
# (migrations run at startup, v53 added it).
_PAYMENT_METHODS_SUBQUERY = (
    "(SELECT GROUP_CONCAT(DISTINCT method) FROM payment_transactions "
    "WHERE order_id = orders.id AND invalidated_at IS NULL)"
)


def _parse_payment_methods(concat: Optional[str]) -> list[str]:
    """Split a ``GROUP_CONCAT``-produced comma-separated string into a list.

    Returns an empty list when the concat is NULL/empty (e.g. an order with
    no payment transactions). Preserves the DISTINCT methods; order follows
    SQLite's GROUP_CONCAT (encounter order, not guaranteed) — callers that
    need a deterministic order should sort the result.
    """
    if not concat:
        return []
    return [m for m in concat.split(",") if m]


def _day_bounds(date_str: str) -> tuple[str, str]:
    day = datetime.strptime(date_str, "%Y-%m-%d")
    next_day = day + timedelta(days=1)
    return f"{date_str}T00:00:00", next_day.strftime("%Y-%m-%dT00:00:00")


def _is_delivered_and_fully_paid(conn, row) -> tuple[bool, Optional[float]]:
    """Return (is_fully_paid, amount_paid) for a delivered order row.

    DG-274 review-auto c1 (CQ-1): deduplicates the delivered+paid filter used
    in both ``active_only`` and ``status`` branches of ``list_orders``.
    Computes ``amount_paid`` once via ``PaymentTransaction.total_paid_excl_outflows``
    and returns it so the caller can forward it to ``Order.from_row`` via
    ``amount_paid=`` and avoid a duplicate query for partially-paid delivered
    orders. Non-delivered rows return ``(False, None)`` — the amount_paid
    is not precomputed because the filter never skips these rows, and
    ``Order.from_row`` will compute it lazily when ``amount_paid is None``
    (CQ-2 clarifies the lazy-cache contract).
    """
    if row["status"] != "delivered":
        return (False, None)
    amount_paid = PaymentTransaction.total_paid_excl_outflows(conn, row["id"])
    return (amount_paid >= float(row["total_price"]), amount_paid)


class OrderItemIn(BaseModel):
    productId: str = ""
    productName: str = Field(max_length=200)
    quantity: int = 1
    unitPrice: float = 0.0
    notes: str = Field(default="", max_length=2000)
    isBirthday: bool = False
    age: Optional[int] = None
    isExtra: bool = False
    isGift: bool = False
    priceChipId: int | None = None
    attributes: dict = Field(default_factory=dict)
    assignedPrice: Optional[float] = None

    @model_validator(mode="after")
    def _validate_assigned_price_le_unit_price(self):
        # Defense-in-depth (DG-296 CQ-4 / review-remediation): the trưng bày
        # markup flow requires unitPrice (selling price) to be >= assignedPrice
        # (COGS anchor). The frontend clamps at every entry point (POS chip
        # picker, wizard Stage 1 editor, cart write-back); this is the backend
        # safety net that clamps unitPrice upward to assignedPrice when a
        # legacy or buggy client submits a below-floor value, so the invariant
        # is preserved even when the client clamp is bypassed. A warning is
        # logged so the violation is observable in production logs (matches the
        # evidence pattern from order M52-T / order_item #5206).
        if self.assignedPrice is not None and self.unitPrice < self.assignedPrice:
            logger.warning(
                "OrderItemIn: clamping unitPrice %.2f up to assignedPrice %.2f "
                "for product %r (markup invariant violated; client clamp bypassed)",
                self.unitPrice,
                self.assignedPrice,
                self.productName,
            )
            # Use object.__setattr__ because the model is otherwise treated as
            # mutable in pydantic v2 validators; assigning the field directly
            # would raise a TypeError on frozen models.
            object.__setattr__(self, "unitPrice", self.assignedPrice)
        return self


class DepositIn(BaseModel):
    amount: float
    method: str = "cash"


def _validate_google_maps_url(value: Optional[str]) -> Optional[str]:
    """Validate googleMapsUrl is an https:// (or http://) URL when provided.

    DG-303 review-auto SEC-2: prevents arbitrary javascript:/data:/file: URIs
    from being stored and later launched by the Flutter client. Empty strings
    are normalized to None so callers can rely on a truthy-or-None contract.
    """
    if value is None:
        return None
    stripped = value.strip()
    if not stripped:
        return None
    lowered = stripped.lower()
    if not (lowered.startswith("https://") or lowered.startswith("http://")):
        raise ValueError("googleMapsUrl must be an http(s) URL")
    return stripped


class OrderCreate(BaseModel):
    customerName: str = Field(max_length=200)
    customerPhone: str = Field(default="", max_length=20)
    deliveryPhone: str = Field(default="", max_length=20)
    customerId: Optional[int] = None
    items: list[OrderItemIn] = []
    dueDate: Optional[str] = None
    dueTime: Optional[str] = None
    deliveryType: str = "pickup"
    deliveryAddress: str = Field(default="", max_length=1000)
    notes: str = Field(default="", max_length=10000)
    source: str = Field(default="", max_length=100)
    deposit: Optional[DepositIn] = None
    createdBy: str = Field(default="", max_length=100)
    shippingFee: float = 0.0
    status: Optional[str] = None
    paymentMethod: Optional[str] = None
    # DG-303 Phase 4.2 (FR1/FR2/FR3/NFR2): door delivery GPS + schedule.
    # Pydantic Field bounds produce HTTP 422 on out-of-range values (NFR2).
    # None is allowed so bus/pickup orders leave these unset.
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    googleMapsUrl: Optional[str] = None
    deliveryTimeSlot: Optional[str] = None

    @field_validator("googleMapsUrl", mode="before")
    @classmethod
    def _validate_google_maps_url_create(cls, v):
        return _validate_google_maps_url(v)


class OrderEdit(BaseModel):
    customerName: Optional[str] = Field(default=None, max_length=200)
    customerPhone: Optional[str] = Field(default=None, max_length=20)
    deliveryPhone: Optional[str] = Field(default=None, max_length=20)
    customerId: Optional[int] = None
    items: Optional[list[OrderItemIn]] = None
    dueDate: Optional[str] = None
    dueTime: Optional[str] = None
    deliveryType: Optional[str] = None
    deliveryAddress: Optional[str] = Field(default=None, max_length=1000)
    notes: Optional[str] = Field(default=None, max_length=10000)
    source: Optional[str] = Field(default=None, max_length=100)
    shippingFee: Optional[float] = None
    changedBy: str = Field(default="", max_length=100)
    workTicketPrintedAt: Optional[str] = None
    publicCodeDateChangeDecision: Optional[str] = None
    # DG-303 Phase 4.2 (FR1/FR2/FR3/NFR2): door delivery GPS + schedule.
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    googleMapsUrl: Optional[str] = None
    deliveryTimeSlot: Optional[str] = None
    # DG-304 Phase 2 (FR6/FR7): admin assignment via PATCH /api/orders/{ref}.
    # Nullable — clearing the field unassigns the order. The column is TEXT
    # (v089), so the value is stored as the staff id string.
    assignedStaffId: Optional[str] = None

    @field_validator("googleMapsUrl", mode="before")
    @classmethod
    def _validate_google_maps_url_edit(cls, v):
        return _validate_google_maps_url(v)


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
        """INSERT INTO order_history (order_id, action_type, field_name, old_value, new_value, changed_by, timestamp)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (order_id, action_type, field_name, old_value, new_value, changed_by, now_utc()),
    )


def _auto_decrement_stock(conn, order_id: int, order_ref: str):
    """Backward-compatible wrapper for stock decrement service."""
    auto_decrement_stock(conn, order_id, order_ref)


def _sync_order_items_table(conn, order_id: int, items: list[OrderItem]) -> None:
    """Sync ``order_items`` table rows to match the new JSON ``items`` list.

    DG-342 Phase 3 (FR9/AC7): when ``edit_order`` replaces the ``orders.items``
    JSON column, the denormalized ``order_items`` table rows must be reconciled
    within the same transaction so work-item IDs, photo links, and blanks stay
    consistent. The strategy is:

    1. Load existing ``order_items`` rows for the order.
    2. Update rows in-place when a new item maps to the same position (keep
       the existing ``id`` so ``order_photos.work_item_id`` /
       ``order_item_blanks.order_item_id`` links survive).
    3. Delete surplus rows (positions beyond the new list). Linked
       ``order_photos.work_item_id`` is NULLed first to avoid FK constraint
       failure (the column has no ``ON DELETE SET NULL`` clause); the
       ``order_item_blanks`` junction cascades via ``ON DELETE CASCADE``.
    4. Insert new rows for positions not already present.

    All mutations run within the caller's ``get_db()`` transaction (NFR3).
    """
    existing_rows = conn.execute(
        "SELECT id, position FROM order_items WHERE order_id = ? ORDER BY position, id",
        (order_id,),
    ).fetchall()
    existing_by_pos: dict[int, int] = {r["position"]: r["id"] for r in existing_rows}

    for position, item in enumerate(items):
        item_id = existing_by_pos.get(position)
        if item_id is not None:
            # Update in-place to preserve photo/blank links.
            conn.execute(
                """UPDATE order_items SET
                   product_id = ?, product_name = ?, quantity = ?, unit_price = ?,
                   notes = ?, position = ?, is_birthday = ?, age = ?,
                   is_extra = ?, is_gift = ?, attributes = ?, price_chip_id = ?,
                   assigned_price = ?
                   WHERE id = ?""",
                (
                    item.product_id,
                    item.product,
                    item.qty,
                    item.price,
                    item.notes,
                    position,
                    1 if item.is_birthday else 0,
                    item.age,
                    1 if item.is_extra else 0,
                    1 if item.is_gift else 0,
                    json.dumps(item.attributes),
                    item.price_chip_id,
                    item.assigned_price,
                    item_id,
                ),
            )
        else:
            work_item = WorkItem(
                order_id=order_id,
                product_id=item.product_id,
                product_name=item.product,
                quantity=item.qty,
                unit_price=item.price,
                notes=item.notes,
                position=position,
                is_birthday=item.is_birthday,
                age=item.age,
                is_extra=item.is_extra,
                is_gift=item.is_gift,
                attributes=item.attributes,
                price_chip_id=item.price_chip_id,
                assigned_price=item.assigned_price,
            )
            work_item.save(conn)

    # Delete surplus rows (positions beyond the new list). Null
    # ``order_photos.work_item_id`` for these rows first to avoid FK
    # constraint failure (no ON DELETE SET NULL on the column).
    new_positions = set(range(len(items)))
    surplus_ids = [rid for pos, rid in existing_by_pos.items() if pos not in new_positions]
    if surplus_ids:
        placeholders = ",".join("?" * len(surplus_ids))
        conn.execute(
            f"UPDATE order_photos SET work_item_id = NULL "
            f"WHERE work_item_id IN ({placeholders})",
            surplus_ids,
        )
        conn.execute(
            f"DELETE FROM order_items WHERE id IN ({placeholders})",
            surplus_ids,
        )


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
        assigned_price=item.assignedPrice,
    )


def _order_detail(conn, row, threshold_minutes: Optional[int] = None) -> dict:
    """Build full order detail dict including work items and payment transactions.

    ``threshold_minutes`` is forwarded to ``Order.to_api_dict`` so the DB
    override from ``get_delivery_critical_threshold(conn)`` (NFR1) is applied
    to the urgency tier. Resolved once per request by the caller.
    """
    order = Order.from_row(row, conn)
    result = order.to_api_dict(threshold_minutes=threshold_minutes)

    item_rows = conn.execute(
        "SELECT * FROM order_items WHERE order_id = ? ORDER BY position, id",
        (row["id"],),
    ).fetchall()
    items = [WorkItem.from_row(r) for r in item_rows]
    # Attach blanks lists via the order_item_blanks junction (DG-294)
    from baker.api.work_items import _attach_blanks
    _attach_blanks(conn, items)
    result["workItems"] = [it.to_api_dict() for it in items]

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
                        AND source IN (?, ?)
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )"""
            )
            params.extend([due_date, *_FALLBACK_SOURCES, created_at_from, created_at_to])
        elif due_date_from and due_date_to:
            created_at_from, _ = _day_bounds(due_date_from)
            _, created_at_to = _day_bounds(due_date_to)
            conditions.append(
                """(
                    (due_date >= ? AND due_date <= ?)
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source IN (?, ?)
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )"""
            )
            params.extend([due_date_from, due_date_to, *_FALLBACK_SOURCES, created_at_from, created_at_to])
        elif due_date_from:
            created_at_from, _ = _day_bounds(due_date_from)
            conditions.append(
                """(
                    due_date >= ?
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source IN (?, ?)
                        AND orders.created_at >= ?
                    )
                )"""
            )
            params.extend([due_date_from, *_FALLBACK_SOURCES, created_at_from])
        elif due_date_to:
            _, created_at_to = _day_bounds(due_date_to)
            conditions.append(
                """(
                    due_date <= ?
                    OR (
                        (due_date IS NULL OR due_date = '')
                        AND source IN (?, ?)
                        AND orders.created_at < ?
                    )
                )"""
            )
            params.extend([due_date_to, *_FALLBACK_SOURCES, created_at_to])

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        # NFR1 (DG-253 Phase 5.6-c1): resolve DB override once per request so
        # Settings-screen changes take effect on the next call without a
        # server restart.
        threshold_minutes = get_delivery_critical_threshold(conn)

        if active_only:
            rows = conn.execute(
                f"SELECT orders.*, s.name AS assigned_staff_name, "
                f"{_PAYMENT_METHODS_SUBQUERY} AS payment_methods_concat "
                f"FROM orders LEFT JOIN staff AS s ON s.id = orders.assigned_staff_id "
                f"{where} ORDER BY orders.id DESC",
                params,
            ).fetchall()
            result = []
            for r in rows:
                # DG-274 Phase 3 (FR3) / review-auto c1 (CQ-1): filter
                # delivered+fully-paid orders out of the active view using
                # the live-computed amount_paid (stored column was dropped in
                # v80). The cached amount_paid is forwarded to from_row so we
                # don't re-query total_paid_excl_outflows for the rows we keep.
                # DG-311 review-uat c1 / CQ-1: staff name is JOINed once here
                # and forwarded to from_row to avoid an N+1 per-order SELECT.
                fully_paid, amount_paid = _is_delivered_and_fully_paid(conn, r)
                if fully_paid:
                    continue
                staff_name = r["assigned_staff_name"] if r["assigned_staff_name"] is not None else ""
                order = Order.from_row(r, conn, amount_paid=amount_paid, assigned_staff_name=staff_name)
                order_dict = order.to_api_dict(threshold_minutes=threshold_minutes)
                # DG-384 Phase 3 (FR5/NFR2): attach distinct payment methods via
                # the correlated subquery column (no N+1 per-order query).
                order_dict["paymentMethods"] = _parse_payment_methods(r["payment_methods_concat"])
                result.append(order_dict)
            return result

        active_statuses = {"new", "confirmed", "in_progress", "ready", "delivered"}
        if status and status in active_statuses:
            rows = conn.execute(
                f"SELECT orders.*, s.name AS assigned_staff_name, "
                f"{_PAYMENT_METHODS_SUBQUERY} AS payment_methods_concat "
                f"FROM orders LEFT JOIN staff AS s ON s.id = orders.assigned_staff_id "
                f"{where} ORDER BY orders.id DESC",
                params,
            ).fetchall()
            result = []
            for r in rows:
                # DG-274 Phase 3 (FR3) / review-auto c1 (CQ-1): same
                # delivered+paid filter as the active_only branch above.
                # DG-311 review-uat c1 / CQ-1: staff name JOINed above.
                fully_paid, amount_paid = _is_delivered_and_fully_paid(conn, r)
                if fully_paid:
                    continue
                staff_name = r["assigned_staff_name"] if r["assigned_staff_name"] is not None else ""
                order = Order.from_row(r, conn, amount_paid=amount_paid, assigned_staff_name=staff_name)
                order_dict = order.to_api_dict(threshold_minutes=threshold_minutes)
                order_dict["paymentMethods"] = _parse_payment_methods(r["payment_methods_concat"])
                result.append(order_dict)
            return result

        rows = conn.execute(
            f"SELECT orders.*, s.name AS assigned_staff_name, "
            f"{_PAYMENT_METHODS_SUBQUERY} AS payment_methods_concat "
            f"FROM orders LEFT JOIN staff AS s ON s.id = orders.assigned_staff_id "
            f"{where} ORDER BY orders.id DESC LIMIT ? OFFSET ?",
            params + [limit, offset],
        ).fetchall()

        result = []
        for r in rows:
            order = Order.from_row(
                r,
                conn,
                assigned_staff_name=(r["assigned_staff_name"] if r["assigned_staff_name"] is not None else ""),
            )
            order_dict = order.to_api_dict(threshold_minutes=threshold_minutes)
            order_dict["paymentMethods"] = _parse_payment_methods(r["payment_methods_concat"])
            result.append(order_dict)
        return result


@router.post("", status_code=201)
def create_order(body: OrderCreate, request: Request):
    """Tạo đơn hàng mới."""
    if body.dueDate is None or body.dueDate.strip() == "":
        raise HTTPException(status_code=422, detail="Vui lòng chọn ngày nhận/giao bánh")

    with get_db() as conn:
        actor = resolve_actor(request, body.createdBy)
        created_staff_name = resolve_staff_name(request)

        if body.customerId is not None:
            exists = conn.execute("SELECT 1 FROM customers WHERE id = ?", (body.customerId,)).fetchone()
            if not exists:
                raise HTTPException(status_code=422, detail="Khách hàng không tồn tại")
        else:
            # DG-205 Phase 3 (FR8): resolve customer_id from customerPhone via
            # customer_phones when the caller did not pass an explicit customerId.
            # DG-227 Phase 1: pass customerName for name-based fallback.
            # DG-252 Phase 1 (FR1/FR2/AC1): guarantee a non-NULL customer_id —
            # resolve → auto-create → shared "Khách lẻ" walk-in record.
            body.customerId = _resolve_or_create_customer_id(
                conn, body.customerPhone, body.customerName
            )
        public_order_code = _generate_unique_public_order_code(conn, body.dueDate, body.deliveryType)
        order = Order(
            customer_name=body.customerName,
            customer_phone=body.customerPhone,
            delivery_phone=body.deliveryPhone,
            customer_id=body.customerId,
            items=[_item_in_to_model(i) for i in body.items],
            due_date=body.dueDate,
            due_time=body.dueTime,
            delivery_type=body.deliveryType,
            delivery_address=body.deliveryAddress,
            notes=body.notes,
            source=body.source,
            created_by=actor,
            created_staff_name=created_staff_name,
            shipping_fee=body.shippingFee,
            public_order_code=public_order_code,
            latitude=body.latitude,
            longitude=body.longitude,
            google_maps_url=body.googleMapsUrl,
            delivery_time_slot=body.deliveryTimeSlot,
        )
        order.calculate_total()
        order.save(conn)

        _log_order_history(conn, order.id, "created", changed_by=actor)

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
                assigned_price=item.assignedPrice,
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

        # POS quick-sale: record payment if paymentMethod is provided, but skip
        # for POS source (Flutter creates the transaction client-side).
        if body.source != "Tại tiệm - POS" and body.paymentMethod and body.paymentMethod != "none":
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
                                   changed_by=actor)

        # If status='delivered', also update order status and decrement stock
        accounting_sync_warning = None
        if body.status == "delivered":
            Order.update_status(conn, order.order_ref, "delivered", "")
            _log_order_history(conn, order.id, "status_change", "status",
                               "new", "delivered", actor)
            auto_decrement_stock(conn, order.id, order.order_ref)

            # Auto-generate revenue conversion + COGS journal entries (DG-175).
            from baker.services.journal_sync import _sync_delivered_order_journal, run_journal_sync, sync_status_to_warning
            sync_status = run_journal_sync(
                _sync_delivered_order_journal,
                conn, order.id, order.order_ref,
                log_label=f"delivered order journal sync for order {order.id}",
                source_type="order",
                source_id=order.id,
            )
            accounting_sync_warning = sync_status_to_warning(sync_status)

        log_context(request, ref_type="order", ref_id=order.id)
        # DG-206 FR6/NFR2: keep customer_year_summary in sync within the same
        # order transaction (single UPSERT-equivalent recompute, <50ms overhead).
        if body.customerId is not None:
            _recompute_customer_year_summary(
                conn, body.customerId, _order_year(order.created_at or now_utc())
            )
        row = conn.execute("SELECT * FROM orders WHERE id = ?", (order.id,)).fetchone()
        response = _order_detail(conn, row, threshold_minutes=get_delivery_critical_threshold(conn))
        if accounting_sync_warning is not None:
            response["accountingSyncWarning"] = accounting_sync_warning
        return response


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
        return _order_detail(conn, row, threshold_minutes=get_delivery_critical_threshold(conn))


@router.post("/{ref}/acknowledge")
def acknowledge_order(ref: str):
    """Ghi nhận đã xem đơn hàng (đặt acknowledged_at nếu đang null)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        if row["acknowledged_at"] is None:
            conn.execute(
                "UPDATE orders SET acknowledged_at = ?, updated_at = ? WHERE id = ?",
                (now_utc(), now_utc(), row["id"]),
            )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))


@router.patch("/{ref}")
def edit_order(ref: str, body: OrderEdit, request: Request):
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

        # DG-342 Phase 3 (FR8/AC6): status guard — block edits on cancelled
        # orders before any mutation. Cancelled orders are terminal and must
        # not be mutated through the edit endpoint; downstream stock/COGS/
        # revenue side effects (Phases 4-5) assume a non-cancelled order.
        if row["status"] == OrderStatus.CANCELLED.value:
            raise HTTPException(
                status_code=422,
                detail="Không thể sửa đơn hàng đã hủy",
            )

        if "customerId" in data and data["customerId"] is not None:
            exists = conn.execute("SELECT 1 FROM customers WHERE id = ?", (data["customerId"],)).fetchone()
            if not exists:
                raise HTTPException(status_code=422, detail="Khách hàng không tồn tại")
        elif "customerId" in data and data["customerId"] is None:
            # DG-252 Phase 1 (FR3): explicit ``customerId: null`` no longer
            # leaves the order unlinked. Re-resolve from the (possibly new)
            # phone/name in the patch body via the resolve → auto-create →
            # "Khách lẻ" walk-in chain. Falls back to the row's existing
            # phone/name when the patch does not supply them.
            phone_for_resolve = data.get("customerPhone")
            if phone_for_resolve is None:
                phone_for_resolve = row["customer_phone"] or ""
            name_for_resolve = data.get("customerName")
            if name_for_resolve is None:
                name_for_resolve = row["customer_name"] or ""
            data["customerId"] = _resolve_or_create_customer_id(
                conn, phone_for_resolve, name_for_resolve
            )
        elif "customerPhone" in data and data["customerPhone"] is not None:
            # DG-227 Phase 1 (FR8): customerId was not touched in the patch
            # but customerPhone changed — re-resolve the customer link from
            # phone + name. Pass customer_name so the name-based fallback can
            # match when the phone fails to resolve.
            # DG-252 Phase 1 (FR3): the re-resolution chain now guarantees a
            # non-NULL customer_id (resolve → auto-create → "Khách lẻ").
            name_for_resolve = data.get("customerName")
            if name_for_resolve is None:
                name_for_resolve = row["customer_name"] or ""
            data["customerId"] = _resolve_or_create_customer_id(
                conn, data["customerPhone"], name_for_resolve
            )

        updates = []
        params: list = []
        public_code_update = None

        field_map = {
            "customerName": "customer_name",
            "customerPhone": "customer_phone",
            "deliveryPhone": "delivery_phone",
            "customerId": "customer_id",
            "dueDate": "due_date",
            "dueTime": "due_time",
            "deliveryType": "delivery_type",
            "deliveryAddress": "delivery_address",
            "notes": "notes",
            "source": "source",
            "shippingFee": "shipping_fee",
            "workTicketPrintedAt": "work_ticket_printed_at",
            "latitude": "latitude",
            "longitude": "longitude",
            "googleMapsUrl": "google_maps_url",
            "deliveryTimeSlot": "delivery_time_slot",
            "assignedStaffId": "assigned_staff_id",
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
        params.append(now_utc())
        params.append(row["id"])
        conn.execute(
            f"UPDATE orders SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        # DG-342 Phase 3 (FR9/AC7): sync the ``order_items`` table rows to
        # match the new ``items`` JSON within the same transaction. Keeps
        # work-item IDs, photo links, and blanks consistent (NFR3).
        if items_changed:
            _sync_order_items_table(conn, row["id"], items)

        # DG-342 Phase 4 (FR5, FR10, NFR1, NFR2, NFR3, AC3): when items
        # change on a confirmed+ order, reverse the old stock deductions
        # (un-consume FIFO items, reverse negative_sale + its COGS journal,
        # delete old sale/negative_sale movements) and re-deduct for the
        # new items. Both steps run within this same ``get_db()``
        # transaction so a failure rolls back the whole edit (NFR3). Stock
        # errors are logged but never crash the order update (NFR1,
        # mirroring the ``run_journal_sync`` fire-and-forget pattern).
        # OPS-1: capture failures and surface an ``accountingSyncWarning``
        # on the edit response (mirroring the ``create_order`` pattern) so
        # the client can warn the user instead of silently dropping the
        # failure.
        edit_sync_warning = None
        if items_changed and _ORDER_STATUS_RANK.get(
            OrderStatus(row["status"]), 0
        ) >= _ORDER_STATUS_RANK[OrderStatus.CONFIRMED]:
            try:
                reverse_order_stock_for_edit(conn, row["id"], row["order_ref"])
                auto_decrement_stock(conn, row["id"], row["order_ref"])
            except Exception:
                logger.exception(
                    "edit_order stock reversal/re-deduction failed for order %s (%s)",
                    row["id"], row["order_ref"],
                )
                edit_sync_warning = "journal_sync_failed"

        # DG-342 Phase 5 (FR6, FR7, FR10, NFR1, NFR3, AC4, AC5): when items
        # or prices change on a delivered/completed order, the existing COGS
        # journal entries (``order_cogs`` + ``order_gift_cogs``) must be
        # reversed and re-created to reflect the new items/prices, and the
        # revenue journal entries reconciled to the new total. Both
        # ``_sync_order_cogs_entry`` and ``_sync_order_gift_cogs_entry`` are
        # idempotent (skip when an entry already exists), so the old entries
        # must be removed first — mirroring the ``_sync_cancelled_order_journal``
        # pattern via ``_replace_order_entry`` (delete when unlocked, reverse
        # when locked). ``_reconcile_order_revenue_entry`` already handles
        # update detection via ``REVENUE_UPDATE_TOLERANCE`` (reverse-and-recreate
        # when amounts diverge), so it is called directly. All journal
        # mutations run within this same ``get_db()`` transaction (NFR3);
        # journal errors are logged but never crash the order update (NFR1,
        # mirroring the ``run_journal_sync`` fire-and-forget pattern).
        is_delivered_or_completed = row["status"] in (
            OrderStatus.DELIVERED.value,
            OrderStatus.COMPLETED.value,
        )
        if is_delivered_or_completed and (items_changed or shipping_fee_changed):
            try:
                from baker.services.journal_sync import (
                    _find_journal_entry,
                    _reconcile_order_revenue_entry,
                    _sync_order_gift_cogs_entry,
                    _sync_order_cogs_entry,
                )
                from baker.services.journal_sync.order import _replace_order_entry
                # Reverse/delete the old COGS entries so the idempotent
                # re-creation below produces entries reflecting the new
                # items/prices (FR6/AC4). COGS only depends on items, so
                # this runs only when items changed.
                if items_changed:
                    for cogs_source_type in ("order_cogs", "order_gift_cogs"):
                        old_cogs_id = _find_journal_entry(conn, cogs_source_type, row["id"])
                        if old_cogs_id is not None:
                            _replace_order_entry(conn, old_cogs_id, respect_locks=True)
                    _sync_order_cogs_entry(conn, row["id"], row["order_ref"])
                    _sync_order_gift_cogs_entry(conn, row["id"], row["order_ref"])
                # Reconcile revenue entries to the new total_price (FR7/AC5)
                # — handles reverse-and-recreate via REVENUE_UPDATE_TOLERANCE.
                # Runs on any total_price change (items or shipping fee).
                _reconcile_order_revenue_entry(
                    conn, row["id"], row["order_ref"], respect_locks=True
                )
            except Exception:
                logger.exception(
                    "edit_order COGS/revenue journal adjustment failed for order %s (%s)",
                    row["id"], row["order_ref"],
                )
                edit_sync_warning = "journal_sync_failed"

        # DG-259: when workTicketPrintedAt is patched, also manage work_ticket_printed_by and work_ticket_printed_staff_name
        if "workTicketPrintedAt" in data:
            printed_val = data["workTicketPrintedAt"]
            if printed_val is not None and printed_val != "":
                mark_actor = resolve_actor(request, data.get("changedBy", ""))
                print_staff_name = resolve_staff_name(request)
                old_printed_at = row["work_ticket_printed_at"]
                old_printed_by = row["work_ticket_printed_by"] or ""
                old_printed_staff_name = row["work_ticket_printed_staff_name"] or ""
                if old_printed_at is None or (not old_printed_by and mark_actor):
                    conn.execute(
                        "UPDATE orders SET work_ticket_printed_by = ? WHERE id = ?",
                        (mark_actor, row["id"]),
                    )
                    _log_order_history(conn, row["id"], "field_edit", "work_ticket_printed_by", old_printed_by, mark_actor, mark_actor)
                if not old_printed_staff_name:
                    conn.execute(
                        "UPDATE orders SET work_ticket_printed_staff_name = ? WHERE id = ?",
                        (print_staff_name, row["id"]),
                    )
                    if old_printed_staff_name != print_staff_name:
                        _log_order_history(conn, row["id"], "field_edit", "work_ticket_printed_staff_name", old_printed_staff_name, print_staff_name, mark_actor)
            else:
                old_printed_by = row["work_ticket_printed_by"] or ""
                old_printed_staff_name = row["work_ticket_printed_staff_name"] or ""
                conn.execute(
                    "UPDATE orders SET work_ticket_printed_by = ?, work_ticket_printed_staff_name = ? WHERE id = ?",
                    ("", "", row["id"]),
                )
                changed_by = resolve_actor(request, data.get("changedBy", ""))
                _log_order_history(conn, row["id"], "field_edit", "work_ticket_printed_by", old_printed_by, "", changed_by)
                if old_printed_staff_name:
                    _log_order_history(conn, row["id"], "field_edit", "work_ticket_printed_staff_name", old_printed_staff_name, "", changed_by)

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
        changed_by = resolve_actor(request, data.get("changedBy", ""))
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

        # DG-206 FR6/NFR2: recompute customer_year_summary when the order's
        # customer link or total volume may have changed. Recompute both the
        # old and new (customer_id, year) rows within the same transaction.
        old_customer_id = row["customer_id"]
        old_year = _order_year(row["created_at"] or "")
        new_customer_id = data.get("customerId", old_customer_id)
        # customerId may be sent as null to unlink — treat absent as unchanged.
        if "customerId" not in data:
            new_customer_id = old_customer_id
        # Recompute the affected rows. items/shipping_fee changes affect the
        # order's own (customer_id, year) row; a customer_id change affects both
        # the old and new customer rows for the order's year.
        if (
            items_changed
            or shipping_fee_changed
            or ("customerId" in data)
        ):
            if old_customer_id is not None and old_year is not None:
                _recompute_customer_year_summary(conn, old_customer_id, old_year)
            if (
                new_customer_id is not None
                and new_customer_id != old_customer_id
                and old_year is not None
            ):
                _recompute_customer_year_summary(conn, new_customer_id, old_year)

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        response = _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))
        response["publicOrderCodeUpdate"] = public_code_update or {
            "action": "unchanged",
            "reason": "none",
            "previousCode": row["public_order_code"] or "",
            "currentCode": updated["public_order_code"] or "",
        }
        if edit_sync_warning is not None:
            response["accountingSyncWarning"] = edit_sync_warning
        return response


@router.post("/{ref}/status")
def transition_status(ref: str, body: StatusTransition, request: Request):
    """Chuyển trạng thái đơn hàng. Lý do bắt buộc khi lùi trạng thái."""
    # DG-308 Phase 5 (FR-ARCH-3): status-machine side effects (stock, journal
    # sync, item cascade, extras sync) are orchestrated by
    # services.order_lifecycle. The handler keeps HTTP validation/rejection.
    from baker.services.order_lifecycle import (
        apply_post_update_side_effects,
        apply_pre_update_side_effects,
    )

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

        # Pre-update side effects (stock decrement/restore + cancellation
        # journal sync) must run before Order.update_status.
        prior_warning = apply_pre_update_side_effects(
            conn, row["id"], row["order_ref"], body.status
        )

        success = Order.update_status(conn, row["order_ref"], body.status, body.reason)
        if not success:
            _raise_status_transition_rejection(
                requested_ref=ref,
                order_row=row,
                target_status=body.status,
                status_code=422,
                rejection_detail="Không thể chuyển trạng thái",
            )

        _log_order_history(conn, row["id"], "status_change", "status", row["status"], body.status, resolve_actor(request, body.changedBy))

        # Post-update side effects (delivered/completed journal sync, item
        # cascade, extras sync) run after the status row is updated.
        accounting_sync_warning = apply_post_update_side_effects(
            conn, row["id"], row["order_ref"], row["status"], body.status, prior_warning
        )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        response = _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))
        if accounting_sync_warning is not None:
            response["accountingSyncWarning"] = accounting_sync_warning
        return response


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
        return _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))


@router.patch("/{ref}/payment")
def update_payment(ref: str, body: PaymentUpdate, request: Request):
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
                old_value="", new_value=str(body.amountPaid), changed_by=resolve_actor(request, body.changedBy),
            )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))


# ---------------------------------------------------------------------------
# Delivery staff claiming — assign / unassign (DG-310 Phase 3, FR5/FR6)
#
# ``POST /api/orders/{ref}/assign``    — any linked staff member claims a
#   non-terminal delivery order. Single-assignee is enforced
#   via a check-and-set UPDATE (race-safe under SQLite's serializable writes):
#   the UPDATE only matches rows where ``assigned_staff_id IS NULL``, so a
#   concurrent claim by staff B sees 0 affected rows and is rejected (AC10).
# ``POST /api/orders/{ref}/unassign``  — the assigned staff (or an admin)
#   releases the claim by setting ``assigned_staff_id`` back to NULL (FR6).
#
# Both endpoints return the updated order via ``_order_detail`` so the
# response carries ``assignedStaffName`` for the client (FR7, AC6/AC8). The
# order lifecycle service is untouched — status transitions are unchanged.
# ---------------------------------------------------------------------------

# Terminal statuses: a delivery order cannot be claimed once it has reached a
# final state (delivered / completed / cancelled).
_TERMINAL_STATUSES = {
    OrderStatus.DELIVERED.value,
    OrderStatus.COMPLETED.value,
    OrderStatus.CANCELLED.value,
}


@router.post("/{ref}/assign")
def assign_order(ref: str, request: Request):
    """Gán đơn hàng giao cho nhân viên đang đăng nhập (FR5, AC6, AC10).

    Resolves the acting staff from the JWT via ``resolve_staff_record``.
    The staff must be a linked staff member and the order must be
    non-terminal and not already claimed. Single-assignee is enforced by the
    conditional UPDATE (``assigned_staff_id IS NULL``).
    """
    staff = resolve_staff_record(request)
    if staff is None:
        raise HTTPException(
            status_code=403,
            detail="Không xác định được nhân viên từ phiên đăng nhập.",
        )

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        if row["status"] in _TERMINAL_STATUSES:
            raise HTTPException(
                status_code=422,
                detail="Không thể nhận đơn đã hoàn thành hoặc đã hủy.",
            )

        if row["assigned_staff_id"] is not None:
            raise HTTPException(
                status_code=409,
                detail="Đơn hàng đã được nhân viên khác nhận.",
            )

        # Race-safe check-and-set: only update rows that are still unclaimed.
        # Under SQLite's serializable write isolation a concurrent assign sees
        # 0 affected rows here and is rejected below (AC10, NFR3 < 500ms).
        cursor = conn.execute(
            "UPDATE orders SET assigned_staff_id = ?, updated_at = ? "
            "WHERE id = ? AND assigned_staff_id IS NULL",
            (str(staff["staff_id"]), now_utc(), row["id"]),
        )
        if cursor.rowcount == 0:
            raise HTTPException(
                status_code=409,
                detail="Đơn hàng đã được nhân viên khác nhận.",
            )

        _log_order_history(
            conn,
            row["id"],
            "assign",
            "assigned_staff_id",
            old_value="",
            new_value=str(staff["staff_id"]),
            changed_by=resolve_actor(request, staff["name"]),
        )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))


@router.post("/{ref}/unassign")
def unassign_order(ref: str, request: Request):
    """Hủy gán đơn hàng giao (FR6, AC8).

    Releases the claim on a delivery order. Only the assigned staff or an
    admin may unclaim. Sets ``assigned_staff_id`` back to NULL.
    """
    staff = resolve_staff_record(request)
    if staff is None:
        raise HTTPException(
            status_code=403,
            detail="Không xác định được nhân viên từ phiên đăng nhập.",
        )

    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
            (ref, ref),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

        if row["assigned_staff_id"] is None:
            raise HTTPException(
                status_code=422,
                detail="Đơn hàng chưa được gán cho ai.",
            )

        # Only the assigned staff or an admin may unclaim (FR6).
        is_admin = getattr(request.state, "auth_role", None) == "admin"
        if not is_admin and str(staff["staff_id"]) != str(row["assigned_staff_id"]):
            raise HTTPException(
                status_code=403,
                detail="Chỉ nhân viên đã nhận đơn hoặc quản lý mới được hủy gán.",
            )

        conn.execute(
            "UPDATE orders SET assigned_staff_id = NULL, updated_at = ? WHERE id = ?",
            (now_utc(), row["id"]),
        )

        _log_order_history(
            conn,
            row["id"],
            "unassign",
            "assigned_staff_id",
            old_value=str(row["assigned_staff_id"]),
            new_value="",
            changed_by=resolve_actor(request, staff["name"]),
        )

        updated = conn.execute("SELECT * FROM orders WHERE id = ?", (row["id"],)).fetchone()
        return _order_detail(conn, updated, threshold_minutes=get_delivery_critical_threshold(conn))
