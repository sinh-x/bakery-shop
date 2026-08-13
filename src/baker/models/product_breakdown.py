"""Product breakdown model (DG-386 Phase 2).

Per-product revenue attribution for a week or month period. Each row
represents one product (or the synthetic ``Others`` bucket) with the
quantity sold, revenue share, and percentage of total period revenue.

Revenue is attributed proportionally to each order item's line value
(``unit_price * quantity``) so the sum of all product revenues
reconciles with the journal 4100 credit total reported by
``GET /api/reports/period-summary`` and ``baker report income-statement``
(see FR3 / Risk R-2 cross-validation).
"""

from dataclasses import dataclass, field


@dataclass
class ProductBreakdownRow:
    """One row in the product breakdown — a single product or the
    ``Others`` aggregate bucket.

    - ``name`` — product name (or ``"Khác"`` for the Others row).
    - ``quantity`` — total units sold across all orders in the period.
    - ``revenue`` — attributed revenue (sum of order-level 4100 revenue
      prorated by this product's share of each order's line value).
    - ``percentage`` — share of total period revenue, 0–100.
    """

    name: str
    quantity: int = 0
    revenue: float = 0.0
    percentage: float = 0.0

    def to_api_dict(self) -> dict:
        return {
            "name": self.name,
            "quantity": self.quantity,
            "revenue": self.revenue,
            "percentage": self.percentage,
        }


@dataclass
class ProductBreakdown:
    """Server-side aggregated per-product revenue for a week or month.

    - ``products`` — top N products by revenue (default top 10), each
      with name, quantity, revenue, percentage.
    - ``others`` — single row aggregating all products beyond the top N
      (``"Khác"``). When there are no products beyond the top N, the
      row is still present with zero quantity/revenue/percentage so the
      client can render a stable layout.
    - ``totalRevenue`` — sum of all product revenues (top N + Others),
      which reconciles with the journal 4100 credit total for the
      period.
    """

    period: str
    startDate: str
    endDate: str
    date: str
    totalRevenue: float = 0.0
    products: list = field(default_factory=list)
    others: ProductBreakdownRow = field(
        default_factory=lambda: ProductBreakdownRow(name="Khác")
    )

    def to_api_dict(self) -> dict:
        return {
            "period": self.period,
            "startDate": self.startDate,
            "endDate": self.endDate,
            "date": self.date,
            "totalRevenue": self.totalRevenue,
            "products": [p.to_api_dict() for p in self.products],
            "others": self.others.to_api_dict(),
        }