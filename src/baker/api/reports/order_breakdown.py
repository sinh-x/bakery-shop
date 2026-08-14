"""Order-breakdown report router (DG-391 Phase 1).

Provides ``GET /api/reports/order-breakdown`` — a per-cell breakdown of
order count and revenue grouped by ``orders.source`` ×
``orders.delivery_type`` for a week or month period (FR1 / AC5).

Revenue per cell is the sum of ``orders.total_price`` for orders whose
effective date (``due_date``; POS/reconciliation sources fall back to
``created_at`` when ``due_date`` is NULL/empty) falls within the period
— the same revenue basis as ``summary_metrics`` after the DG-391
Phase 1 alignment (FR3), so the breakdown totals reconcile with the
period-summary revenue.

Registered under the parent ``/api/reports`` prefix by
``baker.api.reports``.
"""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.api.reports._shared import (
    _FALLBACK_SOURCES,
    _period_bounds,
    _resolve_date_param,
)

router = APIRouter(tags=["reports"])


@router.get("/order-breakdown")
def get_order_breakdown(
    period: str = Query(
        ...,
        description="Loại kỳ báo cáo: 'day' (ngày), 'week' (thứ 2–chủ nhật) hoặc 'month' (1–cuối tháng)",
        pattern=r"^(day|week|month)$",
    ),
    date: Optional[str] = Query(
        None,
        description="Ngày tham chiếu (YYYY-MM-DD) xác định tuần/tháng cần tổng hợp; mặc định hôm nay",
        pattern=r"^\d{4}-\d{2}-\d{2}$",
    ),
):
    """Phân tích đơn hàng theo nguồn đặt hàng × loại giao hàng theo kỳ
    (DG-391 Phase 1 / FR1 / AC5).

    Trả về JSON array với các cell:

    - ``source`` — nhãn nguồn đặt hàng (``orders.source``).
    - ``deliveryType`` — loại giao hàng (``orders.delivery_type``).
    - ``orderCount`` — số đơn trong cell.
    - ``revenue`` — tổng ``total_price`` của các đơn trong cell.

    Đơn hàng được lọc theo effective date (``due_date``; POS /
    reconciliation fallback theo ``created_at``) nằm trong kỳ — cùng
    pattern với period-summary.
    """
    date = _resolve_date_param(date)

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    source_placeholders = ",".join("?" for _ in _FALLBACK_SOURCES)

    with get_db() as conn:
        rows = conn.execute(
            f"""SELECT orders.source AS source,
                       orders.delivery_type AS delivery_type,
                       COUNT(*) AS order_count,
                       COALESCE(SUM(orders.total_price), 0) AS revenue
                FROM orders
                WHERE (
                    orders.due_date >= ? AND orders.due_date <= ?
                    OR (
                        (orders.due_date IS NULL OR orders.due_date = '')
                        AND orders.source IN ({source_placeholders})
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )
                GROUP BY orders.source, orders.delivery_type""",
            (
                start_date,
                end_date,
                *_FALLBACK_SOURCES,
                start_ts,
                end_next_day_ts,
            ),
        ).fetchall()

        return [
            {
                "source": r["source"] or "",
                "deliveryType": r["delivery_type"] or "",
                "orderCount": int(r["order_count"]),
                "revenue": round(float(r["revenue"] or 0), 2),
            }
            for r in rows
        ]