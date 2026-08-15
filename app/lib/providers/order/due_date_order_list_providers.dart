import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/order_service.dart';
import '../../data/models/order.dart';

/// Day-scoped order-list providers (DG-409 review-auto CQ-1).
///
/// `today-summary`/`period-summary` removed the embedded `orders` list in
/// Phase 1, so the dashboard and Today Sales day-tab now fetch the order
/// list separately via `GET /api/orders?due_date=...` (single day) or
/// `GET /api/orders?due_date_from=...&due_date_to=...` (period range). The
/// summary endpoints remain the source of truth for revenue, order count,
/// and status breakdown; only the order rows come from these providers.
///
/// Both providers request all orders due on the scope regardless of status
/// (matching the previous `summary.orders` semantics, including completed
/// and cancelled) by passing `activeOnly: false`. The default `limit` (50)
/// is raised to `200` to cover busy days without paginating.

/// Maximum number of orders to fetch per day/period scope. Matches the
/// history-provider cap so a busy day still renders the full list.
const int dueDateOrdersLimit = 200;

/// Fetches all orders due on [date] (`YYYY-MM-DD`) via
/// `GET /api/orders?due_date=<date>`. Used by the dashboard and Today Sales
/// day-tab to render the `TodayOrderList` section from a separate fetch
/// (CQ-1 — `summary.orders` is no longer returned by the backend).
final dueDateOrdersProvider = FutureProvider.family<List<Order>, String>((
  ref,
  date,
) async {
  final service = ref.watch(orderServiceProvider);
  return service.listOrders(
    dueDate: date,
    activeOnly: false,
    limit: dueDateOrdersLimit,
  );
});

/// Date range used by [periodRangeOrdersProvider] (CQ-1 — period view). A
/// week or month window is expanded into its start/end days so the order
/// list can be fetched via `due_date_from`/`due_date_to`.
class PeriodOrderRange {
  const PeriodOrderRange({required this.fromDate, required this.toDate});

  final String fromDate;
  final String toDate;

  @override
  bool operator ==(Object other) =>
      other is PeriodOrderRange &&
      other.fromDate == fromDate &&
      other.toDate == toDate;

  @override
  int get hashCode => Object.hash(fromDate, toDate);

  @override
  String toString() => 'PeriodOrderRange($fromDate..$toDate)';
}

/// Fetches all orders due within [range] (`fromDate..toDate`, inclusive) via
/// `GET /api/orders?due_date_from=<from>&due_date_to=<to>`. Used by the
/// Today Sales period tabs when a period order list is needed (mirrors the
/// single-day [dueDateOrdersProvider]).
final periodRangeOrdersProvider =
    FutureProvider.family<List<Order>, PeriodOrderRange>((ref, range) async {
      final service = ref.watch(orderServiceProvider);
      return service.listOrders(
        dueDateFrom: range.fromDate,
        dueDateTo: range.toDate,
        activeOnly: false,
        limit: dueDateOrdersLimit,
      );
    });
