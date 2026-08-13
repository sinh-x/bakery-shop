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
"""

import calendar
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from baker.config import get_delivery_critical_threshold
from baker.db.connection import get_db
from baker.db.schema import _account_id_by_code
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

    - ``week``: Monday–Sunday of the week containing ``date_str``
      (Monday-anchored, per FR1).
    - ``month``: 1st day through last day of the month containing
      ``date_str``.

    The ``start_ts`` / ``next_day_ts`` pair mirrors ``_day_bounds`` so the
    same ``>= start_ts AND < next_day_ts`` journal-entry filter works for
    multi-day ranges.
    """
    ref = datetime.strptime(date_str, "%Y-%m-%d")
    if period == "week":
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
            detail="period phải là 'week' hoặc 'month'",
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
        description="Loại kỳ báo cáo: 'week' (thứ 2–chủ nhật) hoặc 'month' (1–cuối tháng)",
        pattern=r"^(week|month)$",
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
        description="Loại kỳ báo cáo: 'week' (thứ 2–chủ nhật) hoặc 'month' (1–cuối tháng)",
        pattern=r"^(week|month)$",
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