"""Expense summary model (DG-386 Phase 3).

Total expenses for a week or month period, broken down by the full
parent/child category tree from ``expense_categories``. Each parent
category reports its subtotal (inclusive of all subcategories) and a
list of subcategory amounts; the grand total reconciles with the sum
of expense journal debits (account 5xxx) recognized in the period.

The breakdown reuses the aggregation pattern from
``_query_supplier_category_breakdown`` (``src/baker/commands/report.py``)
and ``expense-by-category`` CLI: category/subcategory is resolved from
the originating expense event's ``data`` JSON, legacy rows whose
subcategory is stored in the ``category`` field are normalized back to
the parent, and deleted expense events are excluded (matching the
expense screen filter logic).
"""

from dataclasses import dataclass, field


@dataclass
class ExpenseSubcategory:
    """One subcategory line within a parent category's breakdown.

    - ``name`` — subcategory name (matches a child row in
      ``expense_categories`` or a legacy/other value present in the data).
    - ``amount`` — total expense amount attributed to this subcategory.
    """

    name: str
    amount: float = 0.0

    def to_api_dict(self) -> dict:
        return {"name": self.name, "amount": self.amount}


@dataclass
class ExpenseCategory:
    """One parent category in the expense breakdown.

    - ``name`` — parent category name (matches a parent row in
      ``expense_categories``).
    - ``amount`` — total for this parent, inclusive of all subcategory
      amounts and any directly-attributed (no-subcategory) expenses.
    - ``subcategories`` — per-subcategory breakdown for parents that
      have children defined in ``expense_categories`` (plus any legacy
      subcategory values encountered). Empty for parents without
      children.
    """

    name: str
    amount: float = 0.0
    subcategories: list = field(default_factory=list)

    def to_api_dict(self) -> dict:
        return {
            "name": self.name,
            "amount": self.amount,
            "subcategories": [s.to_api_dict() for s in self.subcategories],
        }


@dataclass
class ExpenseSummary:
    """Server-side aggregated expenses for a week or month period.

    - ``totalExpenses`` — grand total of all expense amounts in the
      period (sum of parent category amounts + uncategorized).
    - ``categories`` — per-parent-category breakdown, sorted by name.
      Each entry includes its subcategory children (FR4 / AC4).
    - ``uncategorized`` — total of expense amounts whose category could
      not be resolved from the event data (kept separate so the client
      can render a distinct row).
    - ``childrenOf`` — the full parent→children mapping from
      ``expense_categories`` (so the client can render the complete tree
      even when a subcategory had zero expenses in the period).
    """

    period: str
    startDate: str
    endDate: str
    date: str
    totalExpenses: float = 0.0
    categories: list = field(default_factory=list)
    uncategorized: float = 0.0
    childrenOf: dict = field(default_factory=dict)

    def to_api_dict(self) -> dict:
        return {
            "period": self.period,
            "startDate": self.startDate,
            "endDate": self.endDate,
            "date": self.date,
            "totalExpenses": self.totalExpenses,
            "categories": [c.to_api_dict() for c in self.categories],
            "uncategorized": self.uncategorized,
            "childrenOf": self.childrenOf,
        }