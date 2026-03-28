"""Cake queue API — cross-order work item list for the cake team."""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db

router = APIRouter(prefix="/api/work-items", tags=["cake-queue"])


@router.get("")
def list_work_items_queue(
    status: Optional[str] = Query(
        None,
        description="Lọc theo trạng thái (mặc định: pending,working). Dùng 'all' để lấy mọi trạng thái trừ delivered.",
    ),
    include_ready: bool = Query(False, description="Thêm trạng thái ready vào kết quả"),
    limit: int = Query(100, description="Số lượng tối đa"),
    offset: int = Query(0, description="Bỏ qua N bản ghi đầu"),
):
    """Hàng đợi làm bánh — danh sách công việc qua tất cả đơn hàng (trừ delivered).

    Mặc định: pending + working, sắp xếp theo ngày giao tăng dần (urgent first).
    """
    with get_db() as conn:
        # Build status filter
        if status == "all":
            status_clause = "oi.status != 'delivered'"
            params: list = []
        else:
            allowed = ["pending", "working"]
            if include_ready:
                allowed.append("ready")
            placeholders = ",".join("?" * len(allowed))
            status_clause = f"oi.status IN ({placeholders})"
            params = allowed

        rows = conn.execute(
            f"""
            SELECT
                oi.id,
                oi.order_id,
                oi.product_id,
                oi.product_name,
                oi.quantity,
                oi.unit_price,
                oi.notes,
                oi.position,
                oi.status,
                oi.is_birthday,
                oi.age,
                oi.created_at,
                o.order_ref,
                o.customer_name,
                o.due_date,
                o.due_time
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE {status_clause}
              AND COALESCE(oi.is_extra, 0) = 0
            ORDER BY o.due_date ASC NULLS LAST, o.due_time ASC NULLS LAST, oi.id ASC
            LIMIT ? OFFSET ?
            """,
            params + [limit, offset],
        ).fetchall()

        return [
            {
                "id": str(row["id"]),
                "orderId": str(row["order_id"]),
                "orderRef": row["order_ref"],
                "customerName": row["customer_name"],
                "productId": row["product_id"] or "",
                "productName": row["product_name"],
                "quantity": row["quantity"],
                "unitPrice": row["unit_price"],
                "notes": row["notes"] or "",
                "position": row["position"],
                "status": row["status"],
                "isBirthday": bool(row["is_birthday"]),
                "age": row["age"],
                "dueDate": row["due_date"],
                "dueTime": row["due_time"],
                "createdAt": row["created_at"],
            }
            for row in rows
        ]
