"""Period summary model (DG-386 Phase 1).

Aggregated revenue, payment, and cash-flow metrics over a date range
spanning a full week (Monday–Sunday) or month (1st–last day). Mirrors the
shape of ``GET /api/reports/today-summary`` but extends the bounds to the
requested period instead of a single day.
"""

from dataclasses import dataclass, field


@dataclass
class PeriodSummary:
    """Server-side aggregated metrics for a week or month period.

    Fields mirror ``get_today_summary`` so the Flutter client can reuse the
    same rendering layout across the Ngày/Tuần/Tháng tabs:

    - ``revenue`` — sum of credits to account 4100 over the period
    - ``orderCount`` — number of orders due within the period (all statuses)
    - ``cashTotal`` — debits to 1101 from ``payment_transaction`` entries
    - ``bankTransferTotal`` — debits to bank accounts from ``payment_transaction``
    - ``cashInTotal`` — debits to 1101 from ``cash_drawer_cash_in`` entries
    - ``cashOutTotal`` — credits to 1101 from ``cash_drawer_cash_out`` entries
    - ``orders`` — list of order dicts (same shape as today-summary)
    """

    period: str
    startDate: str
    endDate: str
    date: str
    revenue: float = 0.0
    orderCount: int = 0
    cashTotal: float = 0.0
    bankTransferTotal: float = 0.0
    cashInTotal: float = 0.0
    cashOutTotal: float = 0.0
    orders: list = field(default_factory=list)

    def to_api_dict(self) -> dict:
        return {
            "period": self.period,
            "startDate": self.startDate,
            "endDate": self.endDate,
            "date": self.date,
            "revenue": self.revenue,
            "orderCount": self.orderCount,
            "cashTotal": self.cashTotal,
            "bankTransferTotal": self.bankTransferTotal,
            "cashInTotal": self.cashInTotal,
            "cashOutTotal": self.cashOutTotal,
            "orders": self.orders,
        }