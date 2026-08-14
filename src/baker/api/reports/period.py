"""Period-summary report router (DG-386 Phase 1 / review Mn1, cycle 5).

Extracted from ``baker.api.reports.__init__`` so the main router module
stays under the oversized-file threshold. The endpoint URL and behavior
are identical — only the module location changed. Registered under the
parent ``/api/reports`` prefix by ``baker.api.reports``.
"""

from typing import Optional

from fastapi import APIRouter, Query

from baker.config import get_delivery_critical_threshold
from baker.db.connection import get_db
from baker.models.order import Order
from baker.models.period_summary import PeriodSummary
from baker.api.orders import _parse_payment_methods
from baker.api.reports._metrics import summary_metrics
from baker.api.reports._shared import (
    _FALLBACK_SOURCES,
    _period_bounds,
    _resolve_date_param,
)

router = APIRouter(tags=["reports"])


@router.get("/period-summary")
def get_period_summary(
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
    """Tóm tắt doanh thu theo kỳ — tổng hợp tuần hoặc tháng (DG-386 Phase 1).

    Trả về cùng hình dạng với ``GET /api/reports/today-summary`` (revenue,
    orderCount, cashTotal, bankTransferTotal, cashInTotal, cashOutTotal,
    orders) nhưng tổng hợp trên toàn bộ khoảng thời gian của kỳ:

    - ``week``: thứ 2 đến chủ nhật của tuần chứa ``date`` (FR1).
    - ``month``: từ ngày 1 đến cuối tháng chứa ``date`` (FR1).

    Các metric được tính theo cùng pattern với today-summary nhưng thay
    single-day bounds bằng period bounds:

    - revenue = tổng ``journal_lines.credit`` tài khoản 4100 cho các bút
      toán được ghi nhận trong kỳ (bucket theo due_date cho order-sourced
      entries — ``COALESCE(o.due_date, DATE(je.transaction_date))``) —
      DG-391 Phase 1 / cycle-1 fix
    - cashTotal = tổng debit 1101 từ ``payment_transaction``
    - bankTransferTotal = tổng debit 1200/1210/1220/1290 từ ``payment_transaction``
    - cashInTotal = tổng debit 1101 từ ``cash_drawer_cash_in``
    - cashOutTotal = tổng credit 1101 từ ``cash_drawer_cash_out``
    - orderCount = số đơn có dueDate nằm trong kỳ (mọi status), bao gồm
      đơn POS/reconciliation có due_date rỗng (match theo created_at)
    """
    date = _resolve_date_param(date)

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        metrics = summary_metrics(
            conn,
            start_ts,
            end_next_day_ts,
            period_start_date=start_date,
            period_end_date=end_date,
        )

        # --- Orders: all orders due within [start_date, end_date] (no status filter) ---
        # POS/reconciliation orders with empty due_date fall back to created_at
        # within the period bounds (same pattern as today-summary).
        threshold_minutes = get_delivery_critical_threshold(conn)
        source_placeholders = ",".join("?" for _ in _FALLBACK_SOURCES)
        rows = conn.execute(
            f"""SELECT orders.*, s.name AS assigned_staff_name,
                (SELECT GROUP_CONCAT(DISTINCT method) FROM payment_transactions
                 WHERE order_id = orders.id AND invalidated_at IS NULL) AS payment_methods_concat
                FROM orders LEFT JOIN staff AS s ON s.id = orders.assigned_staff_id
                WHERE (
                    orders.due_date >= ? AND orders.due_date <= ?
                    OR (
                        (orders.due_date IS NULL OR orders.due_date = '')
                        AND orders.source IN ({source_placeholders})
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )
                ORDER BY orders.id DESC""",
            (start_date, end_date, *_FALLBACK_SOURCES, start_ts, end_next_day_ts),
        ).fetchall()

        orders = []
        for r in rows:
            staff_name = (
                r["assigned_staff_name"]
                if r["assigned_staff_name"] is not None
                else ""
            )
            order = Order.from_row(
                r, conn, assigned_staff_name=staff_name
            )
            payment_methods = _parse_payment_methods(r["payment_methods_concat"])
            orders.append(order.to_api_dict(threshold_minutes=threshold_minutes, payment_methods=payment_methods))

        summary = PeriodSummary(
            period=period,
            startDate=start_date,
            endDate=end_date,
            date=date,
            revenue=metrics["revenue"],
            orderCount=len(orders),
            cashTotal=metrics["cashTotal"],
            bankTransferTotal=metrics["bankTransferTotal"],
            cashInTotal=metrics["cashInTotal"],
            cashOutTotal=metrics["cashOutTotal"],
            accountsReceivable=round(
                metrics["revenue"]
                - (metrics["cashTotal"] + metrics["bankTransferTotal"]),
                2,
            ),
            orders=orders,
        )
        return summary.to_api_dict()