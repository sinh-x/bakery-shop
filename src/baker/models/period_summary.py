"""Period summary model (DG-386 Phase 1).

Aggregated revenue, payment, and cash-flow metrics over a date range
spanning a full week (Monday–Sunday) or month (1st–last day). Mirrors the
shape of ``GET /api/reports/today-summary`` but extends the bounds to the
requested period instead of a single day.

DG-391 Phase 1: adds ``accountsReceivable`` = revenue − (cashTotal +
bankTransferTotal) — the outstanding receivable (or prepayment credit
when negative) for the period (FR4 / AC4).

DG-409 Phase 1 (FR8/AC8): the embedded ``orders`` list is replaced by a
``statusBreakdown`` dict (status → count) so the response carries only
aggregate metrics. The Flutter dashboard fetches the full order list via
``GET /api/orders`` when the user opens the period tab.
"""

from dataclasses import dataclass, field


@dataclass
class PeriodSummary:
    """Server-side aggregated metrics for a week or month period.

    Fields mirror ``get_today_summary`` so the Flutter client can reuse the
    same rendering layout across the Ngày/Tuần/Tháng tabs:

    - ``revenue`` — sum of ``journal_lines.credit`` for account 4100
      over the period (journal-based, bucketed by due date for
      order-sourced entries; DG-391)
    - ``orderCount`` — number of orders due within the period (all statuses)
    - ``cashTotal`` — debits to 1101 from ``payment_transaction`` entries
    - ``bankTransferTotal`` — debits to bank accounts from ``payment_transaction``
    - ``cashInTotal`` — debits to 1101 from ``cash_drawer_cash_in`` entries
    - ``cashOutTotal`` — credits to 1101 from ``cash_drawer_cash_out`` entries
    - ``accountsReceivable`` — revenue − (cashTotal + bankTransferTotal);
      positive = outstanding receivable, negative = prepayment/credit
      (DG-391 Phase 1 / FR4)
    - ``statusBreakdown`` — dict mapping order status → count for orders
      due within the period (DG-409 Phase 1 / FR8 / AC8). Replaces the
      embedded ``orders`` list.
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
    accountsReceivable: float = 0.0
    statusBreakdown: dict = field(default_factory=dict)

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
            "accountsReceivable": self.accountsReceivable,
            "statusBreakdown": self.statusBreakdown,
        }
