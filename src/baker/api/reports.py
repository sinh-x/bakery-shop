"""Reporting API routes — day summary endpoint for the Today Sales dashboard.

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
"""

from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from baker.config import get_delivery_critical_threshold
from baker.db.connection import get_db
from baker.db.schema import _account_id_by_code
from baker.models.order import Order
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