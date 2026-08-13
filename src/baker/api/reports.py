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
pattern from ``_query_supplier_category_breakdown`` and the
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
(``_query_cash_period_activity``, ``_query_supplier_category_breakdown``,
``_sum_section``) from ``src/baker/commands/report.py`` so the totals
reconcile with ``baker report cashflow`` (FR5 / AC5).
"""

import calendar
import json
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from baker.commands.report import (
    CASH_ACCOUNT_CODES,
    OPERATING_INFLOW_SOURCE_TYPES,
    OPERATING_OUTFLOW_SOURCE_TYPES,
    _query_cash_period_activity,
    _query_supplier_category_breakdown,
    _sum_section,
)
from baker.config import get_delivery_critical_threshold
from baker.db.connection import get_db
from baker.db.schema import _account_id_by_code
from baker.models.cashflow_summary import (
    CashflowAccountMovement,
    CashflowSection,
    CashflowSubcategory,
    CashflowSupplierCategory,
    CashflowSummary,
)
from baker.models.expense_summary import (
    ExpenseCategory,
    ExpenseSubcategory,
    ExpenseSummary,
)
from baker.models.order import Order
from baker.models.period_summary import PeriodSummary
from baker.models.product_breakdown import (
    ProductBreakdown,
    ProductBreakdownRow,
)
from baker.api.orders import _parse_payment_methods
from baker.utils.time import now_utc

router = APIRouter(prefix="/api/reports", tags=["reports"])


# Bank account codes used by payment_transaction journal routing.
_BANK_ACCOUNT_CODES = ("1200", "1210", "1220", "1290")

# POS source label — orders with empty due_date are matched by created_at.
_POS_SOURCE = "Tại tiệm - POS"

# Reconciliation source label — same fallback scope as POS for NULL due_date
# (DG-384 Phase 2: include reconciliation orders in today-summary date filter).
_RECONCILIATION_SOURCE = "reconciliation"

# Sources that fall back to created_at when due_date is NULL/empty.
_FALLBACK_SOURCES = (_POS_SOURCE, _RECONCILIATION_SOURCE)

# Number of top products to surface in the product breakdown before the
# ``Khác`` (Others) aggregate row (FR3 / F2).
_PRODUCT_BREAKDOWN_TOP_N = 10

# Gift items (``is_gift = 1``) are excluded from product-breakdown revenue
# attribution because their cost is handled by the ``order_gift_cogs``
# journal entry and they do not contribute to the 4100 revenue credit.
_ORDER_ITEM_GIFT_EXCLUDE = "oi.is_gift = 0"


def _day_bounds(date_str: str) -> tuple[str, str]:
    """Return (start, next_day_start) timestamps for string-range filtering."""
    day = datetime.strptime(date_str, "%Y-%m-%d")
    next_day = day + timedelta(days=1)
    return (
        f"{date_str}T00:00:00",
        next_day.strftime("%Y-%m-%dT00:00:00"),
    )


def _period_bounds(period: str, date_str: str) -> tuple[str, str, str, str]:
    """Return (start_date, end_date, start_ts, next_day_ts) for a period.

    - ``day``: the single day containing ``date_str`` (start == end ==
      ``date_str``). Mirrors [_day_bounds] so the day tab can reuse the
      period endpoints without a separate code path.
    - ``week``: Monday–Sunday of the week containing ``date_str``
      (Monday-anchored, per FR1).
    - ``month``: 1st day through last day of the month containing
      ``date_str``.

    The ``start_ts`` / ``next_day_ts`` pair mirrors ``_day_bounds`` so the
    same ``>= start_ts AND < next_day_ts`` journal-entry filter works for
    multi-day ranges.
    """
    ref = datetime.strptime(date_str, "%Y-%m-%d")
    if period == "day":
        start = ref
        end = ref
    elif period == "week":
        # weekday(): Mon=0 .. Sun=6 — subtract to reach this week's Monday.
        start = ref - timedelta(days=ref.weekday())
        end = start + timedelta(days=6)
    elif period == "month":
        start = ref.replace(day=1)
        last_day = calendar.monthrange(ref.year, ref.month)[1]
        end = ref.replace(day=last_day)
    else:
        raise HTTPException(
            status_code=422,
            detail="period phải là 'day', 'week' hoặc 'month'",
        )
    start_str = start.strftime("%Y-%m-%d")
    end_str = end.strftime("%Y-%m-%d")
    next_day = end + timedelta(days=1)
    return (
        start_str,
        end_str,
        f"{start_str}T00:00:00",
        next_day.strftime("%Y-%m-%dT00:00:00"),
    )


def _period_date_range_filter(start_str: str, end_str: str) -> str:
    """Return the SQL ``orders.due_date`` predicate for an inclusive date range."""
    return "orders.due_date >= ? AND orders.due_date <= ?"


@router.get("/today-summary")
def get_today_summary(
    date: Optional[str] = Query(
        None,
        description="Ngày báo cáo (YYYY-MM-DD), mặc định hôm nay",
        pattern=r"^\d{4}-\d{2}-\d{2}$",
    ),
):
    """Tóm tắt doanh thu trong ngày — revenue, orderCount, cashTotal,
    bankTransferTotal, cashInTotal, cashOutTotal, orders.

    Revenue = tổng credit tài khoản 4100 (Doanh thu bán hàng) trong ngày
    (single source of truth, không cộng thêm order totalPrice).

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
    """
    if date is None:
        date = now_utc()[:10]
    else:
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail="date phải có định dạng YYYY-MM-DD",
            )

    day_start, day_end = _day_bounds(date)

    with get_db() as conn:
        # --- Revenue: sum of credits to account 4100 for the day ---
        revenue_acc_id = _account_id_by_code(conn, "4100")
        revenue_row = conn.execute(
            """SELECT COALESCE(SUM(jl.credit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (revenue_acc_id, day_start, day_end),
        ).fetchone()
        revenue = float(revenue_row["total"] or 0)

        # --- Cash total: debits to 1101 where source_type = 'payment_transaction' ---
        cash_acc_id = _account_id_by_code(conn, "1101")
        cash_row = conn.execute(
            """SELECT COALESCE(SUM(jl.debit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'payment_transaction'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (cash_acc_id, day_start, day_end),
        ).fetchone()
        cash_total = float(cash_row["total"] or 0)

        # --- Bank total: debits to 1200/1210/1220/1290 where source_type = 'payment_transaction' ---
        bank_acc_ids = [_account_id_by_code(conn, code) for code in _BANK_ACCOUNT_CODES]
        placeholders = ",".join("?" for _ in bank_acc_ids)
        bank_row = conn.execute(
            f"""SELECT COALESCE(SUM(jl.debit), 0) AS total
                FROM journal_lines jl
                JOIN journal_entries je ON je.id = jl.journal_entry_id
                WHERE jl.account_id IN ({placeholders})
                  AND je.source_type = 'payment_transaction'
                  AND je.transaction_date >= ?
                  AND je.transaction_date < ?""",
            [*bank_acc_ids, day_start, day_end],
        ).fetchone()
        bank_total = float(bank_row["total"] or 0)

        # --- Cash-in total: debits to 1101 where source_type = 'cash_drawer_cash_in' (DG-378) ---
        # Same journal_lines + journal_entries join pattern as cash_total above,
        # filtering by the drawer cash-in source type instead of payment_transaction.
        cash_in_row = conn.execute(
            """SELECT COALESCE(SUM(jl.debit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'cash_drawer_cash_in'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (cash_acc_id, day_start, day_end),
        ).fetchone()
        cash_in_total = float(cash_in_row["total"] or 0)

        # --- Cash-out total: credits to 1101 where source_type = 'cash_drawer_cash_out' (DG-378) ---
        cash_out_row = conn.execute(
            """SELECT COALESCE(SUM(jl.credit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'cash_drawer_cash_out'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (cash_acc_id, day_start, day_end),
        ).fetchone()
        cash_out_total = float(cash_out_row["total"] or 0)

        # --- Orders: all orders due on `date` (no status filter) ---
        # POS orders with empty due_date are matched by created_at within
        # the day bounds (same pattern as GET /api/orders?due_date=...).
        threshold_minutes = get_delivery_critical_threshold(conn)
        source_placeholders = ",".join("?" for _ in _FALLBACK_SOURCES)
        rows = conn.execute(
            f"""SELECT orders.*, s.name AS assigned_staff_name,
                (SELECT GROUP_CONCAT(DISTINCT method) FROM payment_transactions
                 WHERE order_id = orders.id AND invalidated_at IS NULL) AS payment_methods_concat
                FROM orders LEFT JOIN staff AS s ON s.id = orders.assigned_staff_id
                WHERE (
                    orders.due_date = ?
                    OR (
                        (orders.due_date IS NULL OR orders.due_date = '')
                        AND orders.source IN ({source_placeholders})
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )
                ORDER BY orders.id DESC""",
            (date, *_FALLBACK_SOURCES, day_start, day_end),
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

        return {
            "date": date,
            "revenue": revenue,
            "orderCount": len(orders),
            "cashTotal": cash_total,
            "bankTransferTotal": bank_total,
            "cashInTotal": cash_in_total,
            "cashOutTotal": cash_out_total,
            "orders": orders,
        }


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

    - revenue = tổng credit tài khoản 4100 trong kỳ
    - cashTotal = tổng debit 1101 từ ``payment_transaction``
    - bankTransferTotal = tổng debit 1200/1210/1220/1290 từ ``payment_transaction``
    - cashInTotal = tổng debit 1101 từ ``cash_drawer_cash_in``
    - cashOutTotal = tổng credit 1101 từ ``cash_drawer_cash_out``
    - orderCount = số đơn có dueDate nằm trong kỳ (mọi status), bao gồm
      đơn POS/reconciliation có due_date rỗng (match theo created_at)
    """
    if date is None:
        date = now_utc()[:10]
    else:
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail="date phải có định dạng YYYY-MM-DD",
            )

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        # --- Revenue: sum of credits to account 4100 over the period ---
        revenue_acc_id = _account_id_by_code(conn, "4100")
        revenue_row = conn.execute(
            """SELECT COALESCE(SUM(jl.credit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (revenue_acc_id, start_ts, end_next_day_ts),
        ).fetchone()
        revenue = float(revenue_row["total"] or 0)

        # --- Cash total: debits to 1101 from payment_transaction entries ---
        cash_acc_id = _account_id_by_code(conn, "1101")
        cash_row = conn.execute(
            """SELECT COALESCE(SUM(jl.debit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'payment_transaction'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (cash_acc_id, start_ts, end_next_day_ts),
        ).fetchone()
        cash_total = float(cash_row["total"] or 0)

        # --- Bank total: debits to 1200/1210/1220/1290 from payment_transaction ---
        bank_acc_ids = [_account_id_by_code(conn, code) for code in _BANK_ACCOUNT_CODES]
        placeholders = ",".join("?" for _ in bank_acc_ids)
        bank_row = conn.execute(
            f"""SELECT COALESCE(SUM(jl.debit), 0) AS total
                FROM journal_lines jl
                JOIN journal_entries je ON je.id = jl.journal_entry_id
                WHERE jl.account_id IN ({placeholders})
                  AND je.source_type = 'payment_transaction'
                  AND je.transaction_date >= ?
                  AND je.transaction_date < ?""",
            [*bank_acc_ids, start_ts, end_next_day_ts],
        ).fetchone()
        bank_total = float(bank_row["total"] or 0)

        # --- Cash-in total: debits to 1101 from cash_drawer_cash_in ---
        cash_in_row = conn.execute(
            """SELECT COALESCE(SUM(jl.debit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'cash_drawer_cash_in'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (cash_acc_id, start_ts, end_next_day_ts),
        ).fetchone()
        cash_in_total = float(cash_in_row["total"] or 0)

        # --- Cash-out total: credits to 1101 from cash_drawer_cash_out ---
        cash_out_row = conn.execute(
            """SELECT COALESCE(SUM(jl.credit), 0) AS total
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'cash_drawer_cash_out'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (cash_acc_id, start_ts, end_next_day_ts),
        ).fetchone()
        cash_out_total = float(cash_out_row["total"] or 0)

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
                    {_period_date_range_filter(start_date, end_date)}
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
            revenue=revenue,
            orderCount=len(orders),
            cashTotal=cash_total,
            bankTransferTotal=bank_total,
            cashInTotal=cash_in_total,
            cashOutTotal=cash_out_total,
            orders=orders,
        )
        return summary.to_api_dict()


@router.get("/product-breakdown")
def get_product_breakdown(
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
    """Phân tích doanh thu theo sản phẩm theo kỳ — top 10 + dòng ``Khác``
    (DG-386 Phase 2).

    Trả về danh sách sản phẩm kèm số lượng bán ra, doanh thu và tỷ trọng
    % trên tổng doanh thu kỳ, sắp xếp theo doanh thu giảm dần:

    - ``products``: top 10 sản phẩm có doanh thu cao nhất trong kỳ.
    - ``others``: một dòng tổng hợp phần còn lại (``"Khác"``).
    - ``totalRevenue``: tổng doanh thu всех sản phẩm (top 10 + Khác),
      đối soát được với ``revenue`` của ``period-summary`` và
      ``baker report income-statement``.

    Doanh thu được ghi nhận theo bút toán order (credit 4100 =
    deposit_balance tại giao delivered), rồi phân bổ cho từng sản phẩm
    theo tỷ lệ line value (``unit_price * quantity``) trong đơn — loại
    trừ quà tặng (``is_gift = 1``). Cách này đảm bảo tổng doanh thu theo
    sản phẩm khớp với tổng doanh thu trên báo cáo thu nhập (FR3, Risk R-2).
    """
    if date is None:
        date = now_utc()[:10]
    else:
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail="date phải có định dạng YYYY-MM-DD",
            )

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        # --- Order-level revenue (4100 credit) recognized in the period ---
        # Mirrors the period-summary revenue query but grouped per order so
        # revenue can be prorated across that order's line items. Only
        # ``source_type = 'order'`` entries contribute — these are the
        # deposits→revenue / AR entries posted at delivery time. Reversals
        # are handled naturally: a reversed entry is a separate
        # ``source_type = 'order'`` journal entry with swapped debit/credit,
        # so summing credits per order nets out correctly.
        revenue_acc_id = _account_id_by_code(conn, "4100")
        order_revenue_rows = conn.execute(
            """SELECT je.source_id AS order_id,
                      COALESCE(SUM(jl.credit), 0) AS revenue
               FROM journal_lines jl
               JOIN journal_entries je ON je.id = jl.journal_entry_id
               WHERE jl.account_id = ?
                 AND je.source_type = 'order'
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?
               GROUP BY je.source_id
               HAVING revenue > 0""",
            (revenue_acc_id, start_ts, end_next_day_ts),
        ).fetchall()

        if not order_revenue_rows:
            breakdown = ProductBreakdown(
                period=period,
                startDate=start_date,
                endDate=end_date,
                date=date,
                totalRevenue=0.0,
                products=[],
                others=ProductBreakdownRow(name="Khác"),
            )
            return breakdown.to_api_dict()

        order_revenue = {
            int(r["order_id"]): float(r["revenue"] or 0) for r in order_revenue_rows
        }
        order_ids = list(order_revenue.keys())
        order_id_placeholders = ",".join("?" for _ in order_ids)

        # --- Per-order line items (excluding gifts) ---
        # Line value = unit_price * quantity. Products are joined by
        # ``CAST(oi.product_id AS INTEGER) = p.id``; items whose product_id
        # cannot be resolved (e.g. custom BKS-DG codes) fall back to the
        # order_items.product_name as the bucket name so their revenue is
        # still attributed and reconciles.
        item_rows = conn.execute(
            f"""SELECT oi.order_id AS order_id,
                       oi.product_name AS product_name,
                       COALESCE(p.name, oi.product_name) AS display_name,
                       oi.quantity AS quantity,
                       oi.unit_price AS unit_price
                FROM order_items oi
                LEFT JOIN products p ON CAST(oi.product_id AS INTEGER) = p.id
                WHERE oi.order_id IN ({order_id_placeholders})
                  AND {_ORDER_ITEM_GIFT_EXCLUDE}""",
            order_ids,
        ).fetchall()

        # --- Prorate each order's revenue across its line items ---
        # An order with zero line value (e.g. all items 0 VND) skips
        # attribution — its revenue is not allocated to any product and
        # therefore excluded from the breakdown total. This is rare and
        # keeps the breakdown total reconcilable with sum-of-products.
        per_product: dict[str, dict] = {}
        total_revenue = 0.0
        line_values_by_order: dict[int, float] = {}
        for r in item_rows:
            oid = int(r["order_id"])
            qty = int(r["quantity"] or 0)
            unit_price = float(r["unit_price"] or 0)
            line_value = unit_price * qty
            line_values_by_order[oid] = line_values_by_order.get(oid, 0.0) + line_value

        for r in item_rows:
            oid = int(r["order_id"])
            order_rev = order_revenue.get(oid, 0.0)
            if order_rev <= 0:
                continue
            line_total = line_values_by_order.get(oid, 0.0)
            if line_total <= 0:
                continue
            qty = int(r["quantity"] or 0)
            unit_price = float(r["unit_price"] or 0)
            share = (unit_price * qty) / line_total
            attributed = order_rev * share
            name = r["display_name"] or r["product_name"] or "Không tên"
            bucket = per_product.setdefault(
                name, {"name": name, "quantity": 0, "revenue": 0.0}
            )
            bucket["quantity"] += qty
            bucket["revenue"] += attributed
            total_revenue += attributed

        # --- Top N + Others, sorted by revenue descending ---
        sorted_products = sorted(
            per_product.values(), key=lambda p: p["revenue"], reverse=True
        )
        top_rows = sorted_products[:_PRODUCT_BREAKDOWN_TOP_N]
        remainder_rows = sorted_products[_PRODUCT_BREAKDOWN_TOP_N:]

        products = [
            ProductBreakdownRow(
                name=p["name"],
                quantity=p["quantity"],
                revenue=round(p["revenue"], 2),
                percentage=round(
                    (p["revenue"] / total_revenue * 100) if total_revenue > 0 else 0.0,
                    2,
                ),
            )
            for p in top_rows
        ]

        others_qty = sum(p["quantity"] for p in remainder_rows)
        others_rev = sum(p["revenue"] for p in remainder_rows)
        others = ProductBreakdownRow(
            name="Khác",
            quantity=others_qty,
            revenue=round(others_rev, 2),
            percentage=round(
                (others_rev / total_revenue * 100) if total_revenue > 0 else 0.0,
                2,
            ),
        )

        breakdown = ProductBreakdown(
            period=period,
            startDate=start_date,
            endDate=end_date,
            date=date,
            totalRevenue=round(total_revenue, 2),
            products=products,
            others=others,
        )
        return breakdown.to_api_dict()


@router.get("/expense-summary")
def get_expense_summary(
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
    """Tổng chi phí theo danh mục cho kỳ — tuần hoặc tháng (DG-386 Phase 3).

    Trả về tổng chi phí kèm phân loại đầy đủ danh mục cha/con từ bảng
    ``expense_categories`` cho khoảng thời gian được chỉ định (FR4 / AC4):

    - ``totalExpenses`` — tổng tất cả chi phí trong kỳ.
    - ``categories`` — phân loại theo danh mục cha, mỗi danh mục bao gồm
      tổng (gồm tất cả subcategory) và danh sách subcategory. Sắp xếp
      theo tên danh mục.
    - ``uncategorized`` — chi phí không xác định được danh mục từ dữ
      liệu sự kiện.
    - ``childrenOf`` — ánh xạ cha→[con] đầy đủ từ ``expense_categories``
      để client render cây hoàn chỉnh kể cả khi subcategory không có
      chi phí trong kỳ.

    Chi phí được trích từ journal entries ``source_type = 'expense'``
    (debit tài khoản chi phí 5xxx) trong kỳ, đối chiếu với sự kiện
    expense gốc (``events.data``) để lấy ``category`` / ``subcategory``.
    Sự kiện đã xóa (``deleted_at`` không rỗng) bị loại trừ — khớp với
    logic lọc của màn hình chi phí (F2). Dòng legacy có subcategory lưu
    trong trường ``category`` được chuẩn hóa về danh mục cha.
    """
    if date is None:
        date = now_utc()[:10]
    else:
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail="date phải có định dạng YYYY-MM-DD",
            )

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        # --- Expense journal debits within the period (source_type='expense') ---
        # Mirrors the expense-by-category CLI query (report.py:736-750) but
        # filters by the period bounds and joins events to exclude deleted
        # expenses (matching the expense screen filter logic, F2). Only the
        # debit side is summed — credits would be reversal entries which are
        # excluded by the deleted-event filter and the natural net-out of
        # the expense journal sync.
        rows = conn.execute(
            """SELECT je.source_id AS event_id,
                      jl.debit      AS debit
               FROM journal_entries je
               JOIN journal_lines jl ON jl.journal_entry_id = je.id
               WHERE je.source_type = 'expense'
                 AND jl.debit > 0
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?""",
            (start_ts, end_next_day_ts),
        ).fetchall()

        # --- Parent/child category mappings (DG-302 Phase 1) ---
        # children_of (parent -> sorted child names) is returned to the
        # client so the full tree is renderable even when a subcategory had
        # zero expenses this period. parent_of normalizes legacy rows whose
        # subcategory name is stored in the category field back to the parent.
        parent_of: dict[str, str] = {}
        children_of: dict[str, list[str]] = {}
        cat_rows = conn.execute(
            """
            SELECT child.name AS child_name,
                   parent.name AS parent_name
            FROM expense_categories child
            JOIN expense_categories parent ON parent.id = child.parent_id
            """
        ).fetchall()
        for cr in cat_rows:
            parent_of[cr["child_name"]] = cr["parent_name"]
            children_of.setdefault(cr["parent_name"], []).append(
                cr["child_name"]
            )
        for parent in children_of:
            children_of[parent].sort()

        # --- Pre-load non-deleted expense events for category resolution ---
        # Only expense events are needed (source_type='expense' → source_id
        # is an event id). Deleted events are excluded so their journal
        # debits (if any linger) do not contribute to the total (F2).
        events_by_id: dict[int, dict | None] = {}
        event_rows = conn.execute(
            """
            SELECT id, data
            FROM events
            WHERE type = 'expense'
              AND (deleted_at IS NULL OR deleted_at = '')
            """
        ).fetchall()
        for er in event_rows:
            data: dict | None = None
            if er["data"]:
                try:
                    parsed = json.loads(er["data"])
                    if isinstance(parsed, dict):
                        data = parsed
                except (json.JSONDecodeError, TypeError):
                    pass
            events_by_id[int(er["id"])] = data

        # --- Aggregate by category/subcategory ---
        # totals[parent] = total (incl. all subcategories)
        # sub_totals[parent][subcategory] = subtotal
        # Mirrors _query_supplier_category_breakdown / expense_by_category_cmd.
        totals: dict[str, float] = {}
        sub_totals: dict[str, dict[str, float]] = {}
        uncategorized = 0.0

        for r in rows:
            event_id = r["event_id"]
            amount = float(r["debit"])
            category: str | None = None
            subcategory: str | None = None

            if isinstance(event_id, int):
                ev_data = events_by_id.get(event_id)
                if ev_data:
                    cat = ev_data.get("category")
                    if isinstance(cat, str) and cat:
                        category = cat
                    sub = ev_data.get("subcategory")
                    if isinstance(sub, str) and sub:
                        subcategory = sub

            if category:
                # Legacy normalization: when the category field is actually
                # a subcategory name, normalize it back to the parent so it
                # lands in the right bucket (matches report.py:806-813).
                if category in parent_of:
                    parent = parent_of[category]
                    sub_totals.setdefault(parent, {})
                    sub_totals[parent][category] = (
                        sub_totals[parent].get(category, 0.0) + amount
                    )
                    totals[parent] = totals.get(parent, 0.0) + amount
                else:
                    totals[category] = totals.get(category, 0.0) + amount
                    if subcategory:
                        sub_totals.setdefault(category, {})
                        sub_totals[category][subcategory] = (
                            sub_totals[category].get(subcategory, 0.0) + amount
                        )
            else:
                uncategorized += amount

        # --- Build the category tree response ---
        # Each parent category lists its known children (from
        # ``expense_categories``) followed by any legacy/other subcategory
        # values encountered in the data, matching the CLI render order.
        categories: list[ExpenseCategory] = []
        for parent_name in sorted(totals):
            subs: list[ExpenseSubcategory] = []
            known_children = set(children_of.get(parent_name, []))
            # Known children first (in seed order), then legacy/other subs.
            rendered = set()
            for sub_name in children_of.get(parent_name, []):
                sub_amount = sub_totals.get(parent_name, {}).get(sub_name, 0.0)
                subs.append(ExpenseSubcategory(name=sub_name, amount=round(sub_amount, 2)))
                rendered.add(sub_name)
            for sub_name in sorted(sub_totals.get(parent_name, {})):
                if sub_name in rendered:
                    continue
                subs.append(
                    ExpenseSubcategory(
                        name=sub_name,
                        amount=round(sub_totals[parent_name][sub_name], 2),
                    )
                )
            categories.append(
                ExpenseCategory(
                    name=parent_name,
                    amount=round(totals[parent_name], 2),
                    subcategories=subs,
                )
            )

        total_expenses = round(sum(totals.values()) + uncategorized, 2)

        summary = ExpenseSummary(
            period=period,
            startDate=start_date,
            endDate=end_date,
            date=date,
            totalExpenses=total_expenses,
            categories=categories,
            uncategorized=round(uncategorized, 2),
            childrenOf=children_of,
        )
        return summary.to_api_dict()


@router.get("/cashflow-summary")
def get_cashflow_summary(
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
    """Tóm tắt dòng tiền hoạt động kinh doanh theo kỳ (DG-386 Phase 4).

    Trả về dòng tiền thuần từ hoạt động kinh doanh (operating
    activities) cho tuần hoặc tháng, tính từ journal entries trên các
    tài khoản tiền mặt (``CASH_ACCOUNT_CODES``) — không yêu cầu quầy
    tiền mặt đang mở (F2). Khớp với phần "Hoạt động kinh doanh" của
    ``baker report cashflow``:

    - ``operatingInflow`` — dòng vào từ khách hàng
      (``payment_transaction`` debit tài khoản tiền mặt).
    - ``operatingOutflow`` — dòng ra cho nhà cung cấp/nhân viên
      (``expense``, ``expense_settlement``,
      ``order_shipping_release`` credit tài khoản tiền mặt).
    - ``netOperatingCashFlow`` — inflow − outflow.
    - ``customers`` — sub-section ``payment_transaction`` theo tài
      khoản tiền mặt.
    - ``suppliers`` — sub-section ``expense`` +
      ``expense_settlement`` + ``order_shipping_release`` theo tài
      khoản tiền mặt.
    - ``supplierCategories`` — phân loại cha/con của dòng ra cho nhà
      cung cấp (chỉ ``expense`` và ``expense_settlement``;
      ``order_shipping_release`` không có dữ liệu danh mục nên bị loại
      khỏi breakdown nhưng vẫn nằm trong ``suppliers.outflow``).
    - ``uncategorizedSupplier`` — dòng ra không xác định được danh mục.
    - ``childrenOf`` — ánh xạ cha→[con] đầy đủ từ
      ``expense_categories`` để client render cây hoàn chỉnh.

    Bất kỳ journal entry nào chạm tài khoản tài sản cố định 1600 đều
    bị loại trừ (đó là hoạt động đầu tư, báo cáo riêng trong CLI).
    """
    if date is None:
        date = now_utc()[:10]
    else:
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail="date phải có định dạng YYYY-MM-DD",
            )

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        # --- Operating cash activity grouped by source_type/account ---
        # Reuses _query_cash_period_activity from report.py so the totals
        # reconcile with ``baker report cashflow``. The CLI uses inclusive
        # ``<= until_b`` bounds with end-of-day suffix; here we use the
        # same half-open ``>= start_ts AND < end_next_day_ts`` bounds as
        # the other period endpoints (period-summary, product-breakdown,
        # expense-summary) for consistency. Both schemes cover the same
        # day range for journal entries whose transaction_date carries a
        # T00:00:00..T23:59:59 timestamp.
        period_activity = _query_cash_period_activity(
            conn, start_ts, end_next_day_ts,
        )

        # --- Supplier category/subcategory breakdown ---
        # expense + expense_settlement only (order_shipping_release is
        # excluded from the breakdown by _query_supplier_category_breakdown
        # but its outflow is captured in the suppliers section total via
        # _sum_section below).
        supplier_breakdown = _query_supplier_category_breakdown(
            conn, start_ts, end_next_day_ts,
        )

    # --- Aggregate customer and supplier sections ---
    cust_in, cust_out, cust_per = _sum_section(
        period_activity, OPERATING_INFLOW_SOURCE_TYPES,
    )
    sup_in, sup_out, sup_per = _sum_section(
        period_activity, OPERATING_OUTFLOW_SOURCE_TYPES,
    )

    cust_accounts = [
        CashflowAccountMovement(
            code=code,
            inflow=round(mov["inflow"], 2),
            outflow=round(mov["outflow"], 2),
        )
        for code, mov in sorted(cust_per.items())
    ]
    sup_accounts = [
        CashflowAccountMovement(
            code=code,
            inflow=round(mov["inflow"], 2),
            outflow=round(mov["outflow"], 2),
        )
        for code, mov in sorted(sup_per.items())
    ]

    # --- Supplier category tree ---
    # Mirrors the rendering logic in _echo_supplier_category_breakdown /
    # the expense-summary endpoint: known children first (in seed order),
    # then legacy/other subcategory values, sorted by name.
    breakdown_totals: dict[str, float] = supplier_breakdown["totals"]
    breakdown_sub_totals: dict[str, dict[str, float]] = supplier_breakdown[
        "sub_totals"
    ]
    uncategorized_supplier = supplier_breakdown["uncategorized"]
    children_of: dict[str, list[str]] = supplier_breakdown["children_of"]

    supplier_categories: list[CashflowSupplierCategory] = []
    for parent_name in sorted(breakdown_totals):
        subs: list[CashflowSubcategory] = []
        known_children = set(children_of.get(parent_name, []))
        rendered: set[str] = set()
        for sub_name in children_of.get(parent_name, []):
            sub_amount = breakdown_sub_totals.get(parent_name, {}).get(
                sub_name, 0.0
            )
            subs.append(
                CashflowSubcategory(
                    name=sub_name, amount=round(sub_amount, 2)
                )
            )
            rendered.add(sub_name)
        for sub_name in sorted(breakdown_sub_totals.get(parent_name, {})):
            if sub_name in rendered:
                continue
            subs.append(
                CashflowSubcategory(
                    name=sub_name,
                    amount=round(breakdown_sub_totals[parent_name][sub_name], 2),
                )
            )
        supplier_categories.append(
            CashflowSupplierCategory(
                name=parent_name,
                amount=round(breakdown_totals[parent_name], 2),
                subcategories=subs,
            )
        )

    oper_in = cust_in + sup_in
    oper_out = cust_out + sup_out

    summary = CashflowSummary(
        period=period,
        startDate=start_date,
        endDate=end_date,
        date=date,
        operatingInflow=round(oper_in, 2),
        operatingOutflow=round(oper_out, 2),
        netOperatingCashFlow=round(oper_in - oper_out, 2),
        customers=CashflowSection(
            inflow=round(cust_in, 2),
            outflow=round(cust_out, 2),
            perAccount=cust_accounts,
        ),
        suppliers=CashflowSection(
            inflow=round(sup_in, 2),
            outflow=round(sup_out, 2),
            perAccount=sup_accounts,
        ),
        supplierCategories=supplier_categories,
        uncategorizedSupplier=round(uncategorized_supplier, 2),
        childrenOf=children_of,
    )
    return summary.to_api_dict()