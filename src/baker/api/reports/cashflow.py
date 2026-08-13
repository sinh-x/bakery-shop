"""Cashflow-summary report router (DG-386 Phase 4 / review Mn1, cycle 5).

Extracted from ``baker.api.reports.__init__`` so the main router module
stays under the oversized-file threshold. The endpoint URL and behavior
are identical — only the module location changed. Registered under the
parent ``/api/reports`` prefix by ``baker.api.reports``.
"""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.models.cashflow_summary import (
    CashflowAccountMovement,
    CashflowSection,
    CashflowSubcategory,
    CashflowSupplierCategory,
    CashflowSummary,
)
from baker.api.reports._shared import (
    _period_bounds,
    _resolve_date_param,
)
from baker.services.cashflow import (
    OPERATING_INFLOW_SOURCE_TYPES,
    OPERATING_OUTFLOW_SOURCE_TYPES,
    query_cash_period_activity,
    query_supplier_category_breakdown,
    sum_section,
)

router = APIRouter(tags=["reports"])


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
    date = _resolve_date_param(date)

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        # --- Operating cash activity grouped by source_type/account ---
        # Reuses query_cash_period_activity from cashflow.py so the totals
        # reconcile with ``baker report cashflow``. The shared helper
        # defaults to an inclusive upper bound (``je.transaction_date <= ?``)
        # for the CLI, but the API passes ``exclusive_until=True`` so the
        # bound becomes ``je.transaction_date < end_next_day_ts`` — matching
        # the period-summary / expense-summary / product-breakdown endpoints
        # and ensuring a journal entry timestamped exactly at the next
        # period's ``T00:00:00`` is not double-counted by both periods
        # (Mn3, DG-386 cycle 5).
        period_activity = query_cash_period_activity(
            conn, start_ts, end_next_day_ts, exclusive_until=True,
        )

        # --- Supplier category/subcategory breakdown ---
        # expense + expense_settlement only (order_shipping_release is
        # excluded from the breakdown by query_supplier_category_breakdown
        # but its outflow is captured in the suppliers section total via
        # sum_section below). ``exclusive_until=True`` mirrors the activity
        # query so the breakdown stays consistent with suppliers.outflow
        # across the period boundary (Mn3).
        supplier_breakdown = query_supplier_category_breakdown(
            conn, start_ts, end_next_day_ts, exclusive_until=True,
        )

    # --- Aggregate customer and supplier sections ---
    cust_in, cust_out, cust_per = sum_section(
        period_activity, OPERATING_INFLOW_SOURCE_TYPES,
    )
    sup_in, sup_out, sup_per = sum_section(
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