"""Reporting API routes — day summary endpoint for the Today Sales dashboard.

DG-376 Phase 1+2: provides a single backend endpoint that returns revenue,
order count, cash/bank payment totals, and the full order list for a given
day. This eliminates the client-side metric computation that caused the
three confirmed bugs (completed POS orders excluded, revenue double-count,
non-payment journal noise in cash/bank totals).
"""

from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Query

from baker.config import get_delivery_critical_threshold
from baker.db.connection import get_db
from baker.db.schema import _account_id_by_code
from baker.models.order import Order

router = APIRouter(prefix="/api/reports", tags=["reports"])


# Bank account codes used by payment_transaction journal routing.
_BANK_ACCOUNT_CODES = ("1200", "1210", "1220", "1290")

# POS source label — orders with empty due_date are matched by created_at.
_POS_SOURCE = "Tại tiệm - POS"


def _day_bounds(date_str: str) -> tuple[str, str]:
    """Return (start, next_day_start) timestamps for string-range filtering."""
    day = datetime.strptime(date_str, "%Y-%m-%d")
    next_day = day + timedelta(days=1)
    return (
        f"{date_str}T00:00:00",
        next_day.strftime("%Y-%m-%dT00:00:00"),
    )


@router.get("/today-summary")
def get_today_summary(
    date: Optional[str] = Query(None, description="Ngày báo cáo (YYYY-MM-DD), mặc định hôm nay"),
):
    """Tóm tắt doanh thu trong ngày — revenue, orderCount, cashTotal, bankTransferTotal, orders.

    Revenue = tổng credit tài khoản 4100 (Doanh thu bán hàng) trong ngày
    (single source of truth, không cộng thêm order totalPrice).

    Cash total = tổng debit tài khoản 1101 (Tiền mặt tại quầy) từ journal entries
    có source_type = 'payment_transaction'.

    Bank transfer total = tổng debit tài khoản 1200/1210/1220/1290 từ journal entries
    có source_type = 'payment_transaction'.

    Order count = tất cả đơn hàng có dueDate == date (không lọc theo status),
    bao gồm cả đơn POS có due_date rỗng (match theo created_at).
    """
    from baker.utils.time import now_utc

    if date is None:
        date = now_utc()[:10]

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

        # --- Orders: all orders due on `date` (no status filter) ---
        # POS orders with empty due_date are matched by created_at within
        # the day bounds (same pattern as GET /api/orders?due_date=...).
        threshold_minutes = get_delivery_critical_threshold(conn)
        rows = conn.execute(
            f"""SELECT orders.*, s.name AS assigned_staff_name
                FROM orders LEFT JOIN staff AS s ON s.id = orders.assigned_staff_id
                WHERE (
                    orders.due_date = ?
                    OR (
                        (orders.due_date IS NULL OR orders.due_date = '')
                        AND orders.source = ?
                        AND orders.created_at >= ?
                        AND orders.created_at < ?
                    )
                )
                ORDER BY orders.id DESC""",
            (date, _POS_SOURCE, day_start, day_end),
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
            orders.append(order.to_api_dict(threshold_minutes=threshold_minutes))

        return {
            "date": date,
            "revenue": revenue,
            "orderCount": len(orders),
            "cashTotal": cash_total,
            "bankTransferTotal": bank_total,
            "orders": orders,
        }