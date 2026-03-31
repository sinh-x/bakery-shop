"""Work item API routes — per-order production tasks."""

import json
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.order import is_backward_transition
from baker.models.work_item import WorkItem, WorkItemStatus

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


class WorkItemStatusTransition(BaseModel):
    status: str
    reason: str


def _sync_order_items_json(conn, order_id: int) -> None:
    """Regenerate orders.items JSON from order_items table and recalculate total_price."""
    rows = conn.execute(
        "SELECT product_name, quantity, unit_price, notes, product_id, is_extra, is_gift FROM order_items WHERE order_id = ?",
        (order_id,),
    ).fetchall()
    items_json = json.dumps([
        {
            "product": r["product_name"],
            "qty": r["quantity"],
            "price": r["unit_price"],
            "notes": r["notes"] or "",
            "product_id": r["product_id"] or "",
            "is_extra": bool(r["is_extra"]),
            "is_gift": bool(r["is_gift"]),
        }
        for r in rows
    ])
    # Exclude gift items from total price calculation; include shipping_fee
    subtotal = sum(r["quantity"] * r["unit_price"] for r in rows if not r["is_gift"])
    shipping_fee = conn.execute(
        "SELECT shipping_fee FROM orders WHERE id = ?", (order_id,),
    ).fetchone()["shipping_fee"] or 0
    conn.execute(
        "UPDATE orders SET items = ?, total_price = ? WHERE id = ?",
        (items_json, subtotal + shipping_fee, order_id),
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


def _sync_extras_to_order_status(conn, order_id: int, order_status: str) -> None:
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
        return [WorkItem.from_row(r).to_api_dict() for r in rows]


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
        )
        item.save(conn)
        row = conn.execute("SELECT * FROM order_items WHERE id = ?", (item.id,)).fetchone()
        _sync_order_items_json(conn, order_id)
        return WorkItem.from_row(row).to_api_dict()


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
        }
        updates = []
        params: list = []
        for camel, snake in field_map.items():
            if camel in data:
                updates.append(f"{snake} = ?")
                params.append(data[camel])

        if not updates:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        params.append(item_id)
        conn.execute(
            f"UPDATE order_items SET {', '.join(updates)} WHERE id = ?",
            params,
        )
        updated = conn.execute("SELECT * FROM order_items WHERE id = ?", (item_id,)).fetchone()
        _sync_order_items_json(conn, order_id)
        return WorkItem.from_row(updated).to_api_dict()


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
            "UPDATE orders SET updated_at = strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime') WHERE id = ?",
            (order_id,),
        )


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
                # Log auto-sync in order_history (F6)
                conn.execute(
                    """INSERT INTO order_history (order_id, action_type, field_name, old_value, new_value, changed_by)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (order_row["id"], "auto_sync", "status", order_row["status"], derived_order_status, ""),
                )
                # Sync extras/gifts to match the new order status (F4, F5)
                _sync_extras_to_order_status(conn, order_id, derived_order_status)

        updated = conn.execute("SELECT * FROM order_items WHERE id = ?", (item_id,)).fetchone()
        return WorkItem.from_row(updated).to_api_dict()
