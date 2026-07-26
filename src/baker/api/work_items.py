"""Work item API routes — per-order production tasks."""

import json
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, model_validator

from baker.db.connection import get_db
from baker.models.order import is_backward_transition
from baker.models.work_item import BlankAssignment, WorkItem, WorkItemStatus
from baker.utils.time import now_utc

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/orders", tags=["work-items"])

_WORK_ITEM_RANK = {
    WorkItemStatus.PENDING: 0,
    WorkItemStatus.CONFIRMED: 1,
    WorkItemStatus.WORKING: 2,
    WorkItemStatus.READY: 3,
    WorkItemStatus.DELIVERED: 4,
    WorkItemStatus.CANCELLED: 5,
}

# Mapping from work item status to order status (F2)
_WORK_ITEM_TO_ORDER_STATUS = {
    WorkItemStatus.PENDING.value: "new",
    WorkItemStatus.CONFIRMED.value: "confirmed",
    WorkItemStatus.WORKING.value: "in_progress",
    WorkItemStatus.READY.value: "ready",
    WorkItemStatus.DELIVERED.value: "delivered",
    WorkItemStatus.CANCELLED.value: "cancelled",
}

# Mapping from order status to work item status for extras sync (F4)
_ORDER_TO_WORK_ITEM_STATUS = {
    "new": "pending",
    "confirmed": "confirmed",
    "in_progress": "working",
    "ready": "ready",
    "delivered": "delivered",
    "cancelled": "cancelled",
}

_AUTO_SYNC_REASON = "Tự động cập nhật theo trạng thái sản phẩm"


def _is_backward(current: str, target: str) -> bool:
    try:
        return _WORK_ITEM_RANK[WorkItemStatus(target)] < _WORK_ITEM_RANK[WorkItemStatus(current)]
    except (ValueError, KeyError):
        return False


class WorkItemCreate(BaseModel):
    productId: str = ""
    productName: str
    quantity: int = 1
    unitPrice: float = 0.0
    notes: str = ""
    position: int = 0
    isBirthday: bool = False
    age: Optional[int] = None
    isExtra: bool = False
    isGift: bool = False
    attributes: dict = Field(default_factory=dict)
    priceChipId: int | None = None
    assignedPrice: Optional[float] = None

    @model_validator(mode="after")
    def _validate_assigned_price_le_unit_price(self):
        # Defense-in-depth (DG-296 CQ-4): the trưng bày markup flow requires
        # unitPrice (selling price) to be >= assignedPrice (COGS anchor).
        # Soft validation — log a warning only, do not reject, so existing
        # clients with historical data remain backward compatible.
        if self.assignedPrice is not None and self.unitPrice < self.assignedPrice:
            logger.warning(
                "WorkItemCreate: unitPrice %.2f < assignedPrice %.2f for product %r "
                "(markup invariant violated; accepting for backward compatibility)",
                self.unitPrice,
                self.assignedPrice,
                self.productName,
            )
        return self


class WorkItemUpdate(BaseModel):
    productName: Optional[str] = None
    quantity: Optional[int] = None
    unitPrice: Optional[float] = None
    notes: Optional[str] = None
    position: Optional[int] = None
    isBirthday: Optional[bool] = None
    age: Optional[int] = None
    isExtra: Optional[bool] = None
    isGift: Optional[bool] = None
    attributes: Optional[dict] = None
    assignedPrice: Optional[float] = None

    @model_validator(mode="after")
    def _validate_assigned_price_le_unit_price(self):
        # Defense-in-depth (DG-296 CQ-4): when both fields are supplied in the
        # same PATCH, unitPrice must be >= assignedPrice. Soft validation —
        # log a warning only, do not reject, for backward compatibility.
        if (
            self.assignedPrice is not None
            and self.unitPrice is not None
            and self.unitPrice < self.assignedPrice
        ):
            logger.warning(
                "WorkItemUpdate: unitPrice %.2f < assignedPrice %.2f "
                "(markup invariant violated; accepting for backward compatibility)",
                self.unitPrice,
                self.assignedPrice,
            )
        return self


class WorkItemStatusTransition(BaseModel):
    status: str
    reason: str


class BlankAssignmentCreate(BaseModel):
    blankId: int
    quantity: float = 1.0
    notes: str = ""


class BlankAssignmentUpdate(BaseModel):
    quantity: Optional[float] = None
    notes: Optional[str] = None


def _load_blanks_for_item(conn, order_item_id: int) -> list:
    """Return all BlankAssignment rows linked to a work item, ordered by id."""
    rows = conn.execute(
        "SELECT * FROM order_item_blanks WHERE order_item_id = ? ORDER BY id",
        (order_item_id,),
    ).fetchall()
    return [BlankAssignment.from_row(r) for r in rows]


def _attach_blanks(conn, items: list) -> None:
    """Attach blanks lists to a list of WorkItem objects (in-place)."""
    if not items:
        return
    ids = [it.id for it in items if it.id is not None]
    if not ids:
        return
    placeholders = ",".join("?" * len(ids))
    rows = conn.execute(
        f"SELECT * FROM order_item_blanks WHERE order_item_id IN ({placeholders}) ORDER BY id",
        ids,
    ).fetchall()
    by_item: dict[int, list] = {}
    for r in rows:
        by_item.setdefault(r["order_item_id"], []).append(BlankAssignment.from_row(r))
    for it in items:
        it.blanks = by_item.get(it.id, [])


def _sync_order_items_json(conn, order_id: int) -> None:
    """Regenerate orders.items JSON from order_items table and recalculate total_price."""
    # ``assigned_price`` was added in migration v84 (DG-296 Phase 1). Older
    # databases that have not yet reached v84 do not have the column yet —
    # detect it and fall back to NULL so the SELECT works at every migration
    # stage (FR8 backward compatibility, parity with journal_sync.py and
    # accounting_validation.py).
    oi_columns = {
        r[1] for r in conn.execute("PRAGMA table_info(order_items)").fetchall()
    }
    has_assigned_price = "assigned_price" in oi_columns
    rows = conn.execute(
        "SELECT id, product_name, quantity, unit_price, notes, product_id, is_extra, is_gift, attributes"
        + (", assigned_price " if has_assigned_price else ", NULL AS assigned_price ")
        + "FROM order_items WHERE order_id = ?",
        (order_id,),
    ).fetchall()
    item_ids = [r["id"] for r in rows]
    blanks_by_item: dict[int, list] = {}
    if item_ids:
        placeholders = ",".join("?" * len(item_ids))
        blank_rows = conn.execute(
            f"SELECT order_item_id, blank_id, quantity, notes FROM order_item_blanks WHERE order_item_id IN ({placeholders}) ORDER BY id",
            item_ids,
        ).fetchall()
        for br in blank_rows:
            blanks_by_item.setdefault(br["order_item_id"], []).append({
                "blankId": br["blank_id"],
                "quantity": float(br["quantity"]),
                "notes": br["notes"] or "",
            })
    items_json = json.dumps([
        {
            "product": r["product_name"],
            "qty": r["quantity"],
            "price": r["unit_price"],
            "notes": r["notes"] or "",
            "product_id": r["product_id"] or "",
            "is_extra": bool(r["is_extra"]),
            "is_gift": bool(r["is_gift"]),
            "attributes": json.loads(r["attributes"]) if r["attributes"] and r["attributes"] != '{}' else {},
            "blanks": blanks_by_item.get(r["id"], []),
            "assigned_price": r["assigned_price"],
        }
        for r in rows
    ])
    # Exclude gift items from total price calculation; include shipping_fee + cash_fee
    subtotal = sum(r["quantity"] * r["unit_price"] for r in rows if not r["is_gift"])
    # Extract cash_fee from attributes JSON only when tien_rut is active
    cash_fee = 0
    for r in rows:
        if r["attributes"]:
            try:
                attrs = json.loads(r["attributes"]) if isinstance(r["attributes"], str) else (r["attributes"] or {})
                if attrs.get("rut_tien") == "true":
                    fee = attrs.get("cash_fee")
                    if fee:
                        cash_fee += float(fee)
            except (json.JSONDecodeError, TypeError, ValueError):
                pass
    shipping_fee = conn.execute(
        "SELECT shipping_fee FROM orders WHERE id = ?", (order_id,),
    ).fetchone()["shipping_fee"] or 0
    conn.execute(
        "UPDATE orders SET items = ?, total_price = ? WHERE id = ?",
        (items_json, subtotal + cash_fee + shipping_fee, order_id),
    )


def _derive_order_status(conn, order_id: int) -> Optional[str]:
    """Derive order status from main items (is_extra=0 AND is_gift=0) using min-rank logic.

    Returns None if no main items exist.
    Returns 'cancelled' if all main items are cancelled (AC6).
    """
    rows = conn.execute(
        "SELECT status FROM order_items WHERE order_id = ? AND is_extra = 0 AND is_gift = 0",
        (order_id,),
    ).fetchall()
    if not rows:
        return None

    # If all main items are cancelled, derive 'cancelled'
    non_cancelled = [s for s in rows if s["status"] != WorkItemStatus.CANCELLED.value]
    if not non_cancelled:
        return _WORK_ITEM_TO_ORDER_STATUS[WorkItemStatus.CANCELLED.value]

    # Find min rank among non-cancelled main items
    min_rank = min(_WORK_ITEM_RANK.get(WorkItemStatus(s["status"]), float("inf")) for s in non_cancelled)
    # Map rank back to work item status
    status_map = {v: k for k, v in _WORK_ITEM_RANK.items()}
    if min_rank not in status_map:
        return None
    derived_wi_status = status_map[min_rank].value
    return _WORK_ITEM_TO_ORDER_STATUS.get(derived_wi_status)


def sync_extras_to_order_status(conn, order_id: int, order_status: str) -> None:
    """Auto-transition each non-cancelled extra/gift item to match the order status.

    Skips extras that are already at target status, cancelled, or ahead of target (F5).
    Uses ORDER_TO_WORK_ITEM_STATUS mapping (F4).
    """
    target_wi_status = _ORDER_TO_WORK_ITEM_STATUS.get(order_status)
    if not target_wi_status:
        return

    target_rank = _WORK_ITEM_RANK.get(WorkItemStatus(target_wi_status), float("inf"))

    extras = conn.execute(
        "SELECT id, status FROM order_items WHERE order_id = ? AND (is_extra = 1 OR is_gift = 1) AND status != ?",
        (order_id, WorkItemStatus.CANCELLED.value),
    ).fetchall()

    for extra in extras:
        extra_rank = _WORK_ITEM_RANK.get(WorkItemStatus(extra["status"]), float("inf"))
        if extra_rank >= target_rank:
            # Skip if already at or ahead of target (avoid backward transitions on extras)
            continue
        conn.execute(
            "UPDATE order_items SET status = ? WHERE id = ?",
            (target_wi_status, extra["id"]),
        )


def _resolve_order_id(conn, ref: str) -> int:
    row = conn.execute(
        "SELECT id FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
        (ref, ref),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
    return row["id"]


@router.get("/{ref}/items")
def list_work_items(ref: str):
    """Danh sách công việc theo đơn hàng."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        rows = conn.execute(
            "SELECT * FROM order_items WHERE order_id = ? ORDER BY position, id",
            (order_id,),
        ).fetchall()
        items = [WorkItem.from_row(r) for r in rows]
        _attach_blanks(conn, items)
        return [it.to_api_dict() for it in items]


@router.post("/{ref}/items", status_code=201)
def create_work_item(ref: str, body: WorkItemCreate):
    """Thêm công việc vào đơn hàng."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        item = WorkItem(
            order_id=order_id,
            product_id=body.productId,
            product_name=body.productName,
            quantity=body.quantity,
            unit_price=body.unitPrice,
            notes=body.notes,
            position=body.position,
            is_birthday=body.isBirthday,
            age=body.age,
            is_extra=body.isExtra,
            is_gift=body.isGift,
            attributes=body.attributes,
            price_chip_id=body.priceChipId,
            assigned_price=body.assignedPrice,
        )
        item.save(conn)
        row = conn.execute("SELECT * FROM order_items WHERE id = ?", (item.id,)).fetchone()
        _sync_order_items_json(conn, order_id)
        wi = WorkItem.from_row(row)
        wi.blanks = _load_blanks_for_item(conn, wi.id)
        return wi.to_api_dict()


@router.patch("/{ref}/items/{item_id}")
def update_work_item(ref: str, item_id: int, body: WorkItemUpdate):
    """Cập nhật thông tin công việc."""
    data = body.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM order_items WHERE id = ? AND order_id = ?",
            (item_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy công việc")

        field_map = {
            "productName": "product_name",
            "quantity": "quantity",
            "unitPrice": "unit_price",
            "notes": "notes",
            "position": "position",
            "isBirthday": "is_birthday",
            "age": "age",
            "isExtra": "is_extra",
            "isGift": "is_gift",
            "attributes": "attributes",
            "assignedPrice": "assigned_price",
        }
        updates = []
        params: list = []
        for camel, snake in field_map.items():
            if camel in data:
                updates.append(f"{snake} = ?")
                val = data[camel]
                # Serialize attributes dict as JSON string for DB
                if snake == "attributes" and isinstance(val, dict):
                    val = json.dumps(val)
                params.append(val)

        if not updates:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        params.append(item_id)
        conn.execute(
            f"UPDATE order_items SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        updated = conn.execute("SELECT * FROM order_items WHERE id = ?", (item_id,)).fetchone()
        _sync_order_items_json(conn, order_id)
        wi = WorkItem.from_row(updated)
        wi.blanks = _load_blanks_for_item(conn, wi.id)
        return wi.to_api_dict()


@router.delete("/{ref}/items/{item_id}", status_code=204)
def delete_work_item(ref: str, item_id: int):
    """Xóa công việc khỏi đơn hàng."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT id FROM order_items WHERE id = ? AND order_id = ?",
            (item_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy công việc")
        conn.execute("DELETE FROM order_items WHERE id = ?", (item_id,))
        # Recalculate total_price and sync orders.items JSON after deletion
        _sync_order_items_json(conn, order_id)
        conn.execute(
            "UPDATE orders SET updated_at = ? WHERE id = ?",
            (now_utc(), order_id),
        )


# --- Blank assignment CRUD (DG-294 Phase 1) ----------------------------------


def _ensure_blank_exists(conn, blank_id: int) -> None:
    row = conn.execute("SELECT 1 FROM blanks WHERE id = ?", (blank_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy phôi")


def _ensure_work_item(conn, order_id: int, item_id: int):
    row = conn.execute(
        "SELECT * FROM order_items WHERE id = ? AND order_id = ?",
        (item_id, order_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy công việc")
    return row


def _ensure_blank_assignment(conn, item_id: int, blank_item_id: int):
    row = conn.execute(
        "SELECT * FROM order_item_blanks WHERE id = ? AND order_item_id = ?",
        (blank_item_id, item_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy phôi được gán")
    return row


@router.post("/{ref}/items/{item_id}/blanks", status_code=201)
def add_blank_assignment(ref: str, item_id: int, body: BlankAssignmentCreate):
    """Gán phôi bánh cho công việc (FR8)."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _ensure_work_item(conn, order_id, item_id)
        _ensure_blank_exists(conn, body.blankId)
        if body.quantity < 0:
            raise HTTPException(status_code=400, detail="Số lượng không được âm")
        # Upsert on (order_item_id, blank_id) — update quantity/notes on duplicate
        # to avoid silently returning 201 with stale data (DG-294 CQ-1).
        conn.execute(
            """INSERT INTO order_item_blanks
               (order_item_id, blank_id, quantity, notes, created_at)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(order_item_id, blank_id) DO UPDATE SET
                   quantity = excluded.quantity,
                   notes = excluded.notes""",
            (item_id, body.blankId, body.quantity, body.notes, now_utc()),
        )
        row = conn.execute(
            "SELECT * FROM order_item_blanks WHERE order_item_id = ? AND blank_id = ?",
            (item_id, body.blankId),
        ).fetchone()
        _sync_order_items_json(conn, order_id)
        return BlankAssignment.from_row(row).to_api_dict()


@router.patch("/{ref}/items/{item_id}/blanks/{blank_item_id}")
def update_blank_assignment(
    ref: str, item_id: int, blank_item_id: int, body: BlankAssignmentUpdate
):
    """Cập nhật số lượng/ghi chú phôi đã gán (FR9)."""
    data = body.model_dump(exclude_unset=True)
    if not data:
        raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _ensure_work_item(conn, order_id, item_id)
        row = _ensure_blank_assignment(conn, item_id, blank_item_id)

        updates = []
        params: list = []
        if "quantity" in data:
            if data["quantity"] < 0:
                raise HTTPException(status_code=400, detail="Số lượng không được âm")
            updates.append("quantity = ?")
            params.append(float(data["quantity"]))
        if "notes" in data:
            updates.append("notes = ?")
            params.append(data["notes"])

        if not updates:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        params.append(blank_item_id)
        conn.execute(
            f"UPDATE order_item_blanks SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        updated = conn.execute(
            "SELECT * FROM order_item_blanks WHERE id = ?", (blank_item_id,)
        ).fetchone()
        _sync_order_items_json(conn, order_id)
        return BlankAssignment.from_row(updated).to_api_dict()


@router.delete("/{ref}/items/{item_id}/blanks/{blank_item_id}", status_code=204)
def delete_blank_assignment(ref: str, item_id: int, blank_item_id: int):
    """Xóa phôi đã gán khỏi công việc (FR10)."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _ensure_work_item(conn, order_id, item_id)
        _ensure_blank_assignment(conn, item_id, blank_item_id)
        conn.execute("DELETE FROM order_item_blanks WHERE id = ?", (blank_item_id,))
        _sync_order_items_json(conn, order_id)


@router.post("/{ref}/items/{item_id}/status")
def transition_work_item_status(ref: str, item_id: int, body: WorkItemStatusTransition):
    """Chuyển trạng thái công việc. Lý do bắt buộc khi lùi trạng thái."""
    valid_statuses = [s.value for s in WorkItemStatus]
    if body.status not in valid_statuses:
        raise HTTPException(
            status_code=422,
            detail=f"Trạng thái không hợp lệ. Cho phép: {valid_statuses}",
        )

    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM order_items WHERE id = ? AND order_id = ?",
            (item_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy công việc")

        if row["status"] == WorkItemStatus.CANCELLED:
            raise HTTPException(
                status_code=422, detail="Không thể thay đổi trạng thái đã hủy"
            )

        if _is_backward(row["status"], body.status) and not body.reason.strip():
            raise HTTPException(
                status_code=422, detail="Lý do là bắt buộc khi lùi trạng thái"
            )

        conn.execute(
            "UPDATE order_items SET status = ? WHERE id = ?",
            (body.status, item_id),
        )

        # Auto-sync: derive order status from main items and transition if needed (F1, F3)
        derived_order_status = _derive_order_status(conn, order_id)
        if derived_order_status is not None:
            order_row = conn.execute("SELECT id, order_ref, status FROM orders WHERE id = ?", (order_id,)).fetchone()
            if order_row and order_row["status"] != derived_order_status:
                from baker.models.order import Order
                Order.update_status(
                    conn, order_row["order_ref"], derived_order_status, _AUTO_SYNC_REASON
                )

                if derived_order_status in ("delivered", "completed", "confirmed"):
                    from baker.services.order_stock import auto_decrement_stock
                    auto_decrement_stock(conn, order_row["id"], order_row["order_ref"])

                if derived_order_status == "cancelled":
                    from baker.services.order_stock import restore_stock_for_order
                    restore_stock_for_order(conn, order_row["id"], order_row["order_ref"])

                # Log auto-sync in order_history (F6)
                conn.execute(
                    """INSERT INTO order_history (order_id, action_type, field_name, old_value, new_value, changed_by, timestamp)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (order_row["id"], "auto_sync", "status", order_row["status"], derived_order_status, _AUTO_SYNC_REASON, now_utc()),
                )
                # Sync extras/gifts to match the new order status (F4, F5)
                sync_extras_to_order_status(conn, order_id, derived_order_status)

        updated = conn.execute("SELECT * FROM order_items WHERE id = ?", (item_id,)).fetchone()
        wi = WorkItem.from_row(updated)
        wi.blanks = _load_blanks_for_item(conn, wi.id)
        return wi.to_api_dict()


def _sync_extras_to_order_status(conn, order_id: int, order_status: str) -> None:
    """Backward-compatible alias for internal/private callers."""
    sync_extras_to_order_status(conn, order_id, order_status)
