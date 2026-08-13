"""Cashflow summary model (DG-386 Phase 4).

Operating-activity cash-flow summary for a week or month period,
computed from journal entries on the bakery's cash accounts without
requiring an active cash drawer (F2). Reuses the constants and query
patterns from ``src/baker/commands/report.py``:

- ``CASH_ACCOUNT_CODES`` — the set of cash-equivalent accounts tracked
  by the direct-method cashflow statement.
- ``OPERATING_INFLOW_SOURCE_TYPES`` (``payment_transaction``) — cash
  received from customers (deposits and refunds).
- ``OPERATING_OUTFLOW_SOURCE_TYPES`` (``expense``,
  ``expense_settlement``, ``order_shipping_release``) — cash paid to
  suppliers/employees and released shipping fees.
- ``_query_supplier_category_breakdown`` — the parent/child category
  tree for cash paid to suppliers (expense + expense_settlement only;
  ``order_shipping_release`` carries no category data and is excluded
  from the breakdown but included in the supplier-section total).

The response shape mirrors the CLI ``baker report cashflow`` operating
section: a customer inflow/outflow block, a supplier outflow block with
the category/subcategory breakdown, and the net operating cash flow.
"""

from dataclasses import dataclass, field


@dataclass
class CashflowAccountMovement:
    """Per-cash-account inflow/outflow pair for one sub-section.

    - ``code`` — cash account code (e.g. ``1100``, ``1200``).
    - ``inflow`` — total debits to this cash account within the
      sub-section's source types for the period.
    - ``outflow`` — total credits to this cash account within the
      sub-section's source types for the period.
    """

    code: str
    inflow: float = 0.0
    outflow: float = 0.0

    def to_api_dict(self) -> dict:
        return {
            "code": self.code,
            "inflow": self.inflow,
            "outflow": self.outflow,
            "net": round(self.inflow - self.outflow, 2),
        }


@dataclass
class CashflowSubcategory:
    """One subcategory line within a supplier category's breakdown.

    Mirrors ``ExpenseSubcategory`` from Phase 3.
    """

    name: str
    amount: float = 0.0

    def to_api_dict(self) -> dict:
        return {"name": self.name, "amount": self.amount}


@dataclass
class CashflowSupplierCategory:
    """One parent category in the supplier-outflow breakdown.

    - ``amount`` — total cash paid under this parent (inclusive of all
      subcategory amounts).
    - ``subcategories`` — per-subcategory breakdown for parents that
      have children defined in ``expense_categories`` (plus any legacy
      subcategory values encountered in the data).
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
class CashflowSection:
    """One operating-activity sub-section (customers or suppliers).

    - ``inflow`` / ``outflow`` — totals summed across all cash accounts
      and all source types in the section.
    - ``perAccount`` — per-cash-account inflow/outflow breakdown.
    """

    inflow: float = 0.0
    outflow: float = 0.0
    perAccount: list = field(default_factory=list)

    def to_api_dict(self) -> dict:
        return {
            "inflow": round(self.inflow, 2),
            "outflow": round(self.outflow, 2),
            "perAccount": [a.to_api_dict() for a in self.perAccount],
        }


@dataclass
class CashflowSummary:
    """Server-side aggregated operating cash flow for a week or month.

    Computed solely from journal entries on cash accounts (F2 — no
    active cash drawer required). Mirrors the operating-activities
    section of ``baker report cashflow``:

    - ``operatingInflow`` — total operating cash inflow (customers).
    - ``operatingOutflow`` — total operating cash outflow (suppliers
      and employees, including ``order_shipping_release``).
    - ``netOperatingCashFlow`` — inflow minus outflow.
    - ``customers`` — customer sub-section (payment_transaction).
    - ``suppliers`` — supplier sub-section (expense +
      expense_settlement + order_shipping_release).
    - ``supplierCategories`` — category/subcategory breakdown of cash
      paid to suppliers (expense + expense_settlement only; shipping
      releases carry no category data and are excluded from the
      breakdown but included in ``suppliers.outflow``).
    - ``uncategorizedSupplier`` — supplier outflow whose category could
      not be resolved from the event data.
    - ``childrenOf`` — full parent→children mapping from
      ``expense_categories`` for complete tree rendering.
    """

    period: str
    startDate: str
    endDate: str
    date: str
    operatingInflow: float = 0.0
    operatingOutflow: float = 0.0
    netOperatingCashFlow: float = 0.0
    customers: CashflowSection = field(default_factory=CashflowSection)
    suppliers: CashflowSection = field(default_factory=CashflowSection)
    supplierCategories: list = field(default_factory=list)
    uncategorizedSupplier: float = 0.0
    childrenOf: dict = field(default_factory=dict)

    def to_api_dict(self) -> dict:
        return {
            "period": self.period,
            "startDate": self.startDate,
            "endDate": self.endDate,
            "date": self.date,
            "operatingInflow": round(self.operatingInflow, 2),
            "operatingOutflow": round(self.operatingOutflow, 2),
            "netOperatingCashFlow": round(self.netOperatingCashFlow, 2),
            "customers": self.customers.to_api_dict(),
            "suppliers": self.suppliers.to_api_dict(),
            "supplierCategories": [
                c.to_api_dict() for c in self.supplierCategories
            ],
            "uncategorizedSupplier": round(self.uncategorizedSupplier, 2),
            "childrenOf": self.childrenOf,
        }