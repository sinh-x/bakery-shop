import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/order_service.dart';
import '../../data/models/order.dart';

/// Day-scoped order-list provider (DG-409 review-auto CQ-1).
///
/// `today-summary`/`period-summary` removed the embedded `orders` list in
/// Phase 1, so the dashboard and Today Sales day-tab now fetch the order
/// list separately via `GET /api/orders?due_date=...`. The summary
/// endpoints remain the source of truth for revenue, order count, and
/// status breakdown; only the order rows come from this provider.
///
/// The provider requests all orders due on the scope regardless of status
/// (matching the previous `summary.orders` semantics, including completed
/// and cancelled) by passing `activeOnly: false`.
///
/// CQ-13 (review-auto re-review): the previous `dueDateOrdersLimit = 200`
/// cap silently truncated busy days. It has been removed — the single-day
/// view is bounded (a day's order volume is finite), so `limit: -1` is
/// passed, which SQLite interprets as "no limit" (`LIMIT -1`), fetching
/// every order due on the day without silent truncation. Active orders
/// remain unpaginated per FR9.

/// Fetches all orders due on [date] (`YYYY-MM-DD`) via
/// `GET /api/orders?due_date=<date>`. Used by the dashboard and Today Sales
/// day-tab to render the `TodayOrderList` section from a separate fetch
/// (CQ-1 — `summary.orders` is no longer returned by the backend).
final dueDateOrdersProvider = FutureProvider.family<List<Order>, String>((
  ref,
  date,
) async {
  final service = ref.watch(orderServiceProvider);
  return service.listOrders(dueDate: date, activeOnly: false, limit: -1);
});
