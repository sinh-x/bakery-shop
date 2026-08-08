import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/report_service.dart';
import '../../data/api/stock_service.dart';
import '../../data/models/order.dart';
import '../../data/models/today_summary.dart';
import '../../shared/utils/date_formatting.dart';

/// Low-stock threshold (units). An item is "tồn kho thấp" when its total
/// quantity (sum of per-chip options) is ≤ this value. Open question
/// §14 suggested ≤5; this constant makes the threshold adjustable.
const int lowStockThreshold = 5;

/// Number of active orders currently marked `urgency=critical` — drives the
/// `AlertSection` banner count (FR5/AC9). The popup mechanism
/// (`checkAndShowCriticalAlert`) is reused unchanged from
/// `critical_alert_provider.dart`; this helper only supplies the persistent
/// banner count shown on the dashboard. Derived from the live active order
/// list (separate from today's order count, which now comes from the API).
int countCriticalOrders(List<Order> orders) {
  return orders.where((o) => o.urgency == 'critical').length;
}

/// Today's day-summary report from the backend (DG-376 Phase 3).
///
/// Single source of truth for revenue, order count, and cash/bank totals.
/// Replaces the former client-side computation (`sumOrdersRevenueToday`,
/// `countOrdersToday`, journal 4100 summation) that caused the three
/// confirmed bugs: completed POS orders excluded from the count, revenue
/// double-count for partially-paid delivered orders, and non-payment journal
/// noise in cash/bank totals.
final FutureProvider<TodaySummary> todaySummaryProvider =
    FutureProvider<TodaySummary>((ref) async {
  final reports = ref.watch(reportServiceProvider);
  final todayStr = formatApiDate(DateTime.now());
  return reports.getTodaySummary(date: todayStr);
});

/// Revenue + order count + low-stock result computed in parallel
/// (FR4/NFR2/NFR3).
///
/// `revenueToday` and `orderCount` come from [todaySummaryProvider] (the
/// backend `GET /api/reports/today-summary` endpoint — journal 4100 credits
/// only, no `totalPrice` double-count; order count includes all orders due
/// today regardless of status, including completed POS orders).
/// `lowStockCount` is the number of stock-overview items whose total
/// quantity is ≤ [lowStockThreshold]. The summary and stock APIs fire
/// concurrently via `Future.wait` (NFR3 — parallel-fetch pattern preserved).
class DashboardRevenueStock {
  const DashboardRevenueStock({
    required this.revenueToday,
    required this.orderCount,
    required this.lowStockCount,
  });

  final double revenueToday;
  final int orderCount;
  final int lowStockCount;
}

/// Fetches the today-summary report and stock overview in parallel, then
/// folds them into a [DashboardRevenueStock] (FR4/NFR2/NFR3). Errors from
/// either call are propagated so the UI can show a retry affordance —
/// partial failure is not silently swallowed.
final FutureProvider<DashboardRevenueStock> dashboardRevenueStockProvider =
    FutureProvider<DashboardRevenueStock>((ref) async {
  final stock = ref.watch(stockServiceProvider);

  // Fire both calls simultaneously (NFR3 — parallel API calls).
  final summaryFuture = ref.watch(todaySummaryProvider.future);
  final stockFuture = stock.getStockOverview();
  final results = await Future.wait<dynamic>([summaryFuture, stockFuture]);

  final summary = results[0] as TodaySummary;
  final stockItems = results[1] as List<StockOverviewItem>;
  final lowStockCount = stockItems
      .where((i) => i.totalQuantity <= lowStockThreshold)
      .length;

  return DashboardRevenueStock(
    revenueToday: summary.revenue,
    orderCount: summary.orderCount,
    lowStockCount: lowStockCount,
  );
});
