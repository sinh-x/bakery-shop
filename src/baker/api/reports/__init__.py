"""Reporting API routes — day + period summary endpoints for the Today Sales dashboard.

DG-376 Phase 1+2: provides a single backend endpoint that returns revenue,
order count, cash/bank payment totals, and the full order list for a given
day. This eliminates the client-side metric computation that caused the
three confirmed bugs (completed POS orders excluded, revenue double-count,
non-payment journal noise in cash/bank totals).

DG-378 Phase 1: extends the endpoint with ``cashInTotal`` and
``cashOutTotal`` — owner-driven drawer inflows/outflows tracked under
``source_type='cash_drawer_cash_in'`` (1101 debits) and
``source_type='cash_drawer_cash_out'`` (1101 credits). Same
``journal_lines`` + ``journal_entries`` join pattern as the existing
cash/bank totals, with a different ``source_type`` filter (NFR1).

DG-386 Phase 1: adds ``GET /api/reports/period-summary`` — the same
metric shape as the day summary but aggregated over a week (Monday–Sunday)
or month (1st–last day) anchored on a reference date. Reuses the
``journal_lines`` + ``journal_entries`` join pattern with date-range
bounds computed server-side (FR1/FR2).

DG-386 Phase 2: adds ``GET /api/reports/product-breakdown`` — per-product
revenue attribution for a week or month period. Revenue (journal 4100
credit per order) is prorated across each order's line value
(``unit_price * quantity``, gifts excluded) so the breakdown reconciles
with the period-summary revenue total and ``baker report income-statement``
(FR3 / Risk R-2). Returns the top 10 products plus a synthetic ``Khác``
(Others) row aggregating the remainder, sorted by revenue descending.

DG-386 Phase 3: adds ``GET /api/reports/expense-summary`` — total
expenses for a week or month period with a full parent/child category
tree breakdown from ``expense_categories``. Reuses the aggregation
pattern from ``query_supplier_category_breakdown`` and the
``expense-by-category`` CLI: category/subcategory is resolved from the
originating expense event's ``data`` JSON, deleted expense events are
excluded (matching the expense screen filter logic), and legacy rows
whose subcategory is stored in the ``category`` field are normalized
back to the parent (FR4 / AC4).

DG-386 Phase 4: adds ``GET /api/reports/cashflow-summary`` — the
operating-activities cash-flow summary for a week or month period,
computed from journal entries on cash accounts without requiring an
active cash drawer (F2). Reuses the constants
(``CASH_ACCOUNT_CODES``, ``OPERATING_INFLOW_SOURCE_TYPES``,
``OPERATING_OUTFLOW_SOURCE_TYPES``) and query helpers
(``query_cash_period_activity``, ``query_supplier_category_breakdown``,
``sum_section``) from ``src/baker/services/cashflow.py`` so the totals
reconcile with ``baker report cashflow`` (FR5 / AC5).

DG-386 review Mn1 (cycle 5): the four period endpoints were extracted
into per-domain router modules (``period.py``, ``product_breakdown.py``,
``expense.py``, ``cashflow.py``) registered alongside ``today-summary``
under the shared ``/api/reports`` prefix. The five aggregate metric
queries shared by ``today-summary`` and ``period-summary`` were
extracted into ``_metrics.summary_metrics`` (Mn2).

DG-391 Phase 1: adds ``GET /api/reports/order-breakdown`` — a per-cell
breakdown of order count and revenue grouped by ``orders.source`` ×
``orders.delivery_type`` for a week or month period (FR1 / AC5).
Revenue in ``summary_metrics`` is computed from ``journal_lines``
credits to account 4100 (Doanh thu bán hàng), bucketed by due date for
order-sourced entries (``COALESCE(o.due_date, DATE(je.transaction_date))``)
within the period — see ``_revenue_from_journal`` in ``_metrics.py``.
This mirrors ``baker report income-statement --date-basis due-date`` so
the summary reconciles with the income-statement CLI and preserves the
DG-376 partial-payment invariant (FR3 / AC3). ``PeriodSummary`` gains an
``accountsReceivable`` field = revenue − (cashTotal + bankTransferTotal)
(FR4 / AC4).
"""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.api.reports._metrics import summary_metrics
from baker.api.reports._shared import (
    _FALLBACK_SOURCES,
    _day_bounds,
    _resolve_date_param,
)
from baker.api.reports.cashflow import router as cashflow_router
from baker.api.reports.expense import router as expense_router
from baker.api.reports.order_breakdown import router as order_breakdown_router
from baker.api.reports.period import router as period_router
from baker.api.reports.product_breakdown import router as product_breakdown_router

router = APIRouter(prefix="/api/reports", tags=["reports"])

# Register the per-domain period endpoints under the shared prefix.
router.include_router(period_router)
router.include_router(product_breakdown_router)
router.include_router(expense_router)
router.include_router(cashflow_router)
router.include_router(order_breakdown_router)


@router.get("/today-summary")
def get_today_summary(
    date: Optional[str] = Query(
        None,
        description="Ngày báo cáo (YYYY-MM-DD), mặc định hôm nay",
        pattern=r"^\d{4}-\d{2}-\d{2}$",
    ),
):
    """Tóm tắt doanh thu trong ngày — revenue, orderCount, cashTotal,
    bankTransferTotal, cashInTotal, cashOutTotal, statusBreakdown.

    Revenue = tổng ``journal_lines.credit`` tài khoản 4100 cho các bút
    toán được ghi nhận trong ngày (DG-391 Phase 1 — căn chỉnh theo
    due_date để khớp cash-in cùng kỳ, bucket theo
    ``COALESCE(o.due_date, DATE(je.transaction_date))`` cho order-sourced
    entries). POS / reconciliation orders có due_date rỗng fallback theo
    ``DATE(je.transaction_date)``.

    Cash total = tổng debit tài khoản 1101 (Tiền mặt tại quầy) từ journal entries
    có source_type = 'payment_transaction'.

    Bank transfer total = tổng debit tài khoản 1200/1210/1220/1290 từ journal entries
    có source_type = 'payment_transaction'.

    Cash-in total (DG-378) = tổng debit tài khoản 1101 từ journal entries
    có source_type = 'cash_drawer_cash_in' (owner/employee/equity đưa tiền vào quầy).

    Cash-out total (DG-378) = tổng credit tài khoản 1101 từ journal entries
    có source_type = 'cash_drawer_cash_out' (owner rút tiền khỏi quầy).

    Order count = tất cả đơn hàng có dueDate == date (không lọc theo status),
    bao gồm cả đơn POS có due_date rỗng (match theo created_at).

    DG-409 Phase 1 (FR7/AC8): danh sách đơn hàng đầy đủ không còn được nhúng
    trong phản hồi — chỉ trả về các metric tổng hợp (revenue, orderCount,
    statusBreakdown). Flutter dashboard sẽ gọi ``GET /api/orders?due_date=...``
    riêng khi cần hiển thị danh sách đơn.
    """
    date = _resolve_date_param(date)

    day_start, day_end = _day_bounds(date)

    with get_db() as conn:
        metrics = summary_metrics(
            conn,
            day_start,
            day_end,
            period_start_date=date,
            period_end_date=date,
        )

        # --- Order count + status breakdown (FR7/AC8) ---
        # The full order list is no longer embedded in the response — only
        # aggregate metrics are returned (revenue, order count, status
        # breakdown). The Flutter dashboard fetches the order list via the
        # dedicated ``GET /api/orders?due_date=...`` endpoint when the user
        # opens the Today Sales tab. This keeps the summary payload small
        # and decouples the dashboard metrics from the full order fetch
        # (DG-409 Phase 1 / FR7 / AC8).
        source_placeholders = ",".join("?" for _ in _FALLBACK_SOURCES)
        count_row = conn.execute(
            f"""SELECT COUNT(*) AS cnt,
                   COALESCE(status, '') AS status
                FROM orders
                WHERE (
                    orders.due_date = ?
                    OR (
                        (orders.due_date IS NULL OR orders.due_date = '')
                        AND orders.source IN ({source_placeholders})
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )
                GROUP BY status""",
            (date, *_FALLBACK_SOURCES, day_start, day_end),
        ).fetchall()
        order_count = sum(int(r["cnt"]) for r in count_row)
        status_breakdown = {r["status"]: int(r["cnt"]) for r in count_row}

        return {
            "date": date,
            "revenue": metrics["revenue"],
            "orderCount": order_count,
            "cashTotal": metrics["cashTotal"],
            "bankTransferTotal": metrics["bankTransferTotal"],
            "cashInTotal": metrics["cashInTotal"],
            "cashOutTotal": metrics["cashOutTotal"],
            "statusBreakdown": status_breakdown,
        }
