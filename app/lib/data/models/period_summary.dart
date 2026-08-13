import 'order.dart';

/// Period-summary report returned by `GET /api/reports/period-summary`
/// (DG-386 Phase 1).
///
/// Same shape as [TodaySummary] but aggregated over a week (Monday–Sunday)
/// or month (1st–last day) instead of a single day. The Flutter client reuses
/// the same rendering layout across the Ngày/Tuần/Tháng tabs because the
/// metric fields are identical to `today-summary`.
///
/// Fields mirror the API response 1:1:
/// - `period`        — `'week'` or `'month'`.
/// - `startDate`      — first day of the period (`YYYY-MM-DD`).
/// - `endDate`        — last day of the period (`YYYY-MM-DD`).
/// - `date`          — the queried reference day (`YYYY-MM-DD`).
/// - `revenue`       — sum of credits to account 4100 over the period.
/// - `orderCount`    — number of orders due within the period (all statuses).
/// - `cashTotal`     — debits to 1101 from `payment_transaction` entries.
/// - `bankTransferTotal` — debits to bank accounts from `payment_transaction`.
/// - `cashInTotal`   — debits to 1101 from `cash_drawer_cash_in` entries.
/// - `cashOutTotal`  — credits to 1101 from `cash_drawer_cash_out` entries.
/// - `orders`        — orders due within the period (no status filter), each
///                     decoded into an [Order].
class PeriodSummary {
  final String period;
  final String startDate;
  final String endDate;
  final String date;
  final double revenue;
  final int orderCount;
  final double cashTotal;
  final double bankTransferTotal;
  final double cashInTotal;
  final double cashOutTotal;
  final List<Order> orders;

  const PeriodSummary({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.date,
    required this.revenue,
    required this.orderCount,
    required this.cashTotal,
    required this.bankTransferTotal,
    required this.cashInTotal,
    required this.cashOutTotal,
    required this.orders,
  });

  factory PeriodSummary.fromJson(Map<String, dynamic> json) {
    final ordersRaw = json['orders'] as List? ?? const [];
    return PeriodSummary(
      period: json['period'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      date: json['date'] as String? ?? '',
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      cashTotal: (json['cashTotal'] as num?)?.toDouble() ?? 0,
      bankTransferTotal: (json['bankTransferTotal'] as num?)?.toDouble() ?? 0,
      cashInTotal: (json['cashInTotal'] as num?)?.toDouble() ?? 0,
      cashOutTotal: (json['cashOutTotal'] as num?)?.toDouble() ?? 0,
      orders: ordersRaw
          .map((o) => Order.fromJson(o as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}