"""Order-breakdown report router (DG-391 Phase 1).

Provides ``GET /api/reports/order-breakdown`` — a per-cell breakdown of
order count and revenue grouped by ``orders.source`` ×
``orders.delivery_type`` for a week or month period (FR1 / AC5).

Revenue per cell is the sum of ``journal_lines.credit`` for account 4100
(Doanh thu bán hàng), bucketed by due date for order-sourced entries
(``COALESCE(o.due_date, DATE(je.transaction_date))``) — the same
journal-based revenue basis as ``summary_metrics`` after the DG-391
cycle-1 fix (FR3), so the breakdown totals reconcile with the
period-summary revenue and the income-statement CLI in ``--date-basis
due-date`` mode. ``orderCount`` counts distinct orders that have a 4100
credit entry recognized in the period.

Registered under the parent ``/api/reports`` prefix by
``baker.api.reports``.
"""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.db.schema import _account_id_by_code
from baker.api.reports._shared import (
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
    - ``orderCount`` — số đơn trong cell (đếm distinct order có 4100
      credit được ghi nhận trong kỳ).
    - ``revenue`` — tổng ``journal_lines.credit`` tài khoản 4100 của các
      đơn trong cell, bucketed theo due_date.

    Revenue dùng cùng cơ sở journal 4100 credit với period-summary (sau
    đợt fix DG-391 cycle 1) để tổng breakdown khớp tổng period-summary
    (FR3 / AC3).
    """
    date = _resolve_date_param(date)

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        revenue_acc = _account_id_by_code(conn, "4100")
        rows = conn.execute(
            """SELECT o.source AS source,
                      o.delivery_type AS delivery_type,
                      COUNT(DISTINCT o.id) AS order_count,
                      COALESCE(SUM(jl.credit), 0) AS revenue
                 FROM journal_lines jl
                 JOIN journal_entries je ON je.id = jl.journal_entry_id
                 LEFT JOIN orders o
                   ON je.source_type IN ('order', 'order_cogs')
                  AND je.source_id = o.id
                WHERE jl.account_id = ?
                  AND je.source_type IN ('order', 'order_cogs')
                  AND COALESCE(o.due_date, DATE(je.transaction_date)) >= ?
                  AND COALESCE(o.due_date, DATE(je.transaction_date)) <= ?
                GROUP BY o.source, o.delivery_type""",
            (revenue_acc, start_date, end_date),
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