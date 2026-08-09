import 'order.dart';

/// Day-summary report returned by `GET /api/reports/today-summary` (DG-376).
///
/// Provides a single backend source of truth for the Today Sales metrics so
/// the Flutter client no longer computes revenue, order count, or cash/bank
/// totals from filtered order/journal lists (the cause of the three confirmed
/// bugs: completed POS orders excluded, revenue double-count, non-payment
/// journal noise).
///
/// Fields mirror the API response 1:1:
/// - `date`            — the queried day (`YYYY-MM-DD`).
/// - `revenue`         — sum of credits to account 4100 for the day
///                       (single source of truth; no `totalPrice` added).
/// - `orderCount`      — count of all orders with `dueDate == date`,
///                       regardless of status (includes completed/cancelled
///                       and same-day POS orders with empty `due_date`).
/// - `cashTotal`       — sum of debits to account 1101 from journal entries
///                       with `source_type = 'payment_transaction'`.
/// - `bankTransferTotal` — sum of debits to accounts 1200/1210/1220/1290
///                       from journal entries with
///                       `source_type = 'payment_transaction'`.
/// - `cashInTotal`     — sum of debits to account 1101 from journal entries
///                       with `source_type = 'cash_drawer_cash_in'`
///                       (owner/employee/equity capital injections into the
///                       drawer; DG-378).
/// - `cashOutTotal`    — sum of credits to account 1101 from journal entries
///                       with `source_type = 'cash_drawer_cash_out'`
///                       (owner draws from the drawer; DG-378).
/// - `orders`          — all orders due on `date` (no status filter), each
///                       decoded into an [Order].
class TodaySummary {
  final String date;
  final double revenue;
  final int orderCount;
  final double cashTotal;
  final double bankTransferTotal;
  final double cashInTotal;
  final double cashOutTotal;
  final List<Order> orders;

  const TodaySummary({
    required this.date,
    required this.revenue,
    required this.orderCount,
    required this.cashTotal,
    required this.bankTransferTotal,
    required this.cashInTotal,
    required this.cashOutTotal,
    required this.orders,
  });

  factory TodaySummary.fromJson(Map<String, dynamic> json) {
    final ordersRaw = json['orders'] as List? ?? const [];
    return TodaySummary(
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