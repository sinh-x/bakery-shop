"""Expense-summary report router (DG-386 Phase 3 / review Mn1, cycle 5).

Extracted from ``baker.api.reports.__init__`` so the main router module
stays under the oversized-file threshold. The endpoint URL and behavior
are identical — only the module location changed. Registered under the
parent ``/api/reports`` prefix by ``baker.api.reports``.
"""

import json
from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.models.expense_summary import (
    ExpenseCategory,
    ExpenseSubcategory,
    ExpenseSummary,
)
from baker.api.reports._shared import (
    _period_bounds,
    _resolve_date_param,
)
from baker.services.expense_categories import aggregate_categories

router = APIRouter(tags=["reports"])


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
    date = _resolve_date_param(date)

    start_date, end_date, start_ts, end_next_day_ts = _period_bounds(period, date)

    with get_db() as conn:
        # --- Expense journal debits within the period (source_type='expense') ---
        # Mirrors the expense-by-category CLI query (report.py:736-750) but
        # filters by the period bounds and joins events to exclude deleted
        # expenses (matching the expense screen filter logic, F2). Only the
        # debit side is summed — credits would be reversal entries which are
        # excluded by the deleted-event filter and the natural net-out of
        # the expense journal sync.
        #
        # The events join (with deleted_at filter) is applied at the SQL
        # level rather than only in Python category resolution so that a
        # soft-deleted expense whose journal entry could not be
        # cascade-deleted (locked entry → reversed instead) does not leak
        # its original debit (and the reversal's swapped debit) into the
        # period total. Both the original and reversal entries share the
        # same source_id (the event id), so filtering on the joined
        # event's deleted_at excludes both (M1, DG-386 cycle 5).
        rows = conn.execute(
            """SELECT je.source_id AS event_id,
                      jl.debit      AS debit
               FROM journal_entries je
               JOIN journal_lines jl ON jl.journal_entry_id = je.id
               JOIN events e ON e.id = je.source_id
               WHERE je.source_type = 'expense'
                 AND jl.debit > 0
                 AND je.transaction_date >= ?
                 AND je.transaction_date < ?
                 AND (e.deleted_at IS NULL OR e.deleted_at = '')""",
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
        # Resolve (category, subcategory, amount) per row, then delegate
        # the legacy normalization + totals/sub_totals/uncategorized
        # accumulation to the shared aggregate_categories helper
        # (DG-386 review Mn3).
        triples: list[tuple[str | None, str | None, float]] = []
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

            triples.append((category, subcategory, amount))

        totals, sub_totals, uncategorized = aggregate_categories(
            triples, parent_of
        )

        # --- Build the category tree response ---
        # Each parent category lists its known children (from
        # ``expense_categories``) followed by any legacy/other subcategory
        # values encountered in the data, matching the CLI render order.
        categories: list[ExpenseCategory] = []
        for parent_name in sorted(totals):
            subs: list[ExpenseSubcategory] = []
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