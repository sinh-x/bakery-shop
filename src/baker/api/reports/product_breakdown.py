"""Product-breakdown report router (DG-386 Phase 2 / review Mn1, cycle 5).

Extracted from ``baker.api.reports.__init__`` so the main router module
stays under the oversized-file threshold. The endpoint URL and behavior
are identical — only the module location changed. Registered under the
parent ``/api/reports`` prefix by ``baker.api.reports``.
"""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.db.schema import _account_id_by_code
from baker.models.product_breakdown import (
    ProductBreakdown,
    ProductBreakdownRow,
)
from baker.api.reports._shared import (
    _period_bounds,
    _resolve_date_param,
)

router = APIRouter(tags=["reports"])

# Number of top products to surface in the product breakdown before the
# ``Khác`` (Others) aggregate row (FR3 / F2).
_PRODUCT_BREAKDOWN_TOP_N = 10

# Gift items (``is_gift = 1``) are excluded from product-breakdown revenue
# attribution because their cost is handled by the ``order_gift_cogs``
# journal entry and they do not contribute to the 4100 revenue credit.
_ORDER_ITEM_GIFT_EXCLUDE = "oi.is_gift = 0"


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
    - ``totalRevenue``: tổng doanh thu tất cả sản phẩm (top 10 + Khác),
      đối soát được với ``revenue`` của ``period-summary`` và
      ``baker report income-statement`` — với giới hạn đã nêu bên dưới.

    Doanh thu được ghi nhận theo bút toán order (credit 4100 =
    deposit_balance tại giao delivered), rồi phân bổ cho từng sản phẩm
    theo tỷ lệ line value (``unit_price * quantity``) trong đơn — loại
    trừ quà tặng (``is_gift = 1``). Cách này đảm bảo tổng doanh thu theo
    sản phẩm khớp với tổng doanh thu trên báo cáo thu nhập (FR3, Risk R-2).

    Giới hạn đối soát (known limitation): các đơn có doanh thu ròng 4100
    credit ≤ 0 (bút toán đảo/reversal hoặc hoàn/trả hàng) bị loại trừ qua
    ``HAVING revenue > 0``; các đơn có tổng line value = 0 (ví dụ mọi dòng
    đều 0 VND) cũng bị bỏ qua vì không thể phân bổ tỷ lệ
    (``if order_rev <= 0: continue`` và ``if line_total <= 0: continue``).
    Do đó ``totalRevenue`` có thể nhỏ hơn ``period-summary.revenue`` khi
    kỳ có đơn đảo/hoàn hoặc đơn line value = 0 — đây là hành vi cố ý để
    giữ bảng phân tích theo sản phẩm khớp internally (sum-of-products),
    không phải lỗi đối soát.
    """
    date = _resolve_date_param(date)

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

        # --- Per-order line items (excluding gifts) ---
        # Line value = unit_price * quantity. Products are joined by
        # ``CAST(oi.product_id AS INTEGER) = p.id``; items whose product_id
        # cannot be resolved (e.g. custom BKS-DG codes) fall back to the
        # order_items.product_name as the bucket name so their revenue is
        # still attributed and reconciles.
        #
        # Chunk the order-id IN (...) list into batches (default 500) so a
        # period with many orders does not exceed SQLite's 32766 host
        # variable limit (Mn5, DG-386 cycle 5). Results are merged in
        # order-id order so the proration loop below is stable.
        item_rows = []
        _PRODUCT_BREAKDOWN_CHUNK = 500
        for i in range(0, len(order_ids), _PRODUCT_BREAKDOWN_CHUNK):
            batch = order_ids[i:i + _PRODUCT_BREAKDOWN_CHUNK]
            batch_placeholders = ",".join("?" for _ in batch)
            batch_rows = conn.execute(
                f"""SELECT oi.order_id AS order_id,
                           oi.product_name AS product_name,
                           COALESCE(p.name, oi.product_name) AS display_name,
                           oi.quantity AS quantity,
                           oi.unit_price AS unit_price
                    FROM order_items oi
                    LEFT JOIN products p ON CAST(oi.product_id AS INTEGER) = p.id
                    WHERE oi.order_id IN ({batch_placeholders})
                      AND {_ORDER_ITEM_GIFT_EXCLUDE}""",
                batch,
            ).fetchall()
            item_rows.extend(batch_rows)

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