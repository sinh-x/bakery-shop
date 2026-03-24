"""Work item API routes — per-order production tasks."""

import json
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.work_item import WorkItem, WorkItemStatus

router = APIRouter(prefix="/api/orders", tags=["work-items"])

_WORK_ITEM_RANK = {
    WorkItemStatus.PENDING: 0,
    WorkItemStatus.WORKING: 1,
    WorkItemStatus.READY: 2,
    WorkItemStatus.DELIVERED: 3,
    WorkItemStatus.CANCELLED: 4,
}


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


class WorkItemUpdate(BaseModel):
    productName: Optional[str] = None
    quantity: Optional[int] = None
    unitPrice: Optional[float] = None
    notes: Optional[str] = None
    position: Optional[int] = None
    isBirthday: Optional[bool] = None
    age: Optional[int] = None


class WorkItemStatusTransition(BaseModel):
    status: str
    reason: str


def _sync_order_items_json(conn, order_id: int) -> None:
    """Regenerate orders.items JSON from order_items table and recalculate total_price."""
    rows = conn.execute(
        "SELECT product_name, quantity, unit_price, notes, product_id FROM order_items WHERE order_id = ?",
        (order_id,),
    ).fetchall()
    items_json = json.dumps([
        {
            "product": r["product_name"],
            "qty": r["quantity"],
            "price": r["unit_price"],
            "notes": r["notes"] or "",
            "product_id": r["product_id"] or "",
        }
        for r in rows
    ])
    total_price = sum(r["quantity"] * r["unit_price"] for r in rows)
    conn.execute(
        "UPDATE orders SET items = ?, total_price = ? WHERE id = ?",
        (items_json, total_price, order_id),
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
        )
        item.save(conn)
        row = conn.execute("SELECT * FROM order_items WHERE id = ?", (item.id,)).fetchone()
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
        updated = conn.execute("SELECT * FROM order_items WHERE id = ?", (item_id,)).fetchone()
        return WorkItem.from_row(updated).to_api_dict()
