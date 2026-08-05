import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/accounting_service.dart';
import '../../data/api/stock_service.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/order.dart';
import '../../shared/utils/date_formatting.dart';
import '../order/order_list_providers.dart';

/// Revenue-account code used to compute today's revenue from the journal
/// (FR4 — "tổng từ journal (account 4100)"). Credits to this account sum to
/// the day's sales revenue.
const String revenueAccountCode = '4100';

/// Low-stock threshold (units). An item is "tồn kho thấp" when its total
/// quantity (sum of per-chip options) is ≤ this value. Open question
/// §14 suggested ≤5; this constant makes the threshold adjustable.
const int lowStockThreshold = 5;

/// Number of active orders whose `dueDate` is today — "số đơn hàng hôm nay"
/// (FR2/NFR1). Uses the `dueDate == today` convention to filter the active
/// order list down to today's orders.
int countOrdersToday(List<Order> orders) {
  final todayStr = formatApiDate(DateTime.now());
  return orders.where((o) => o.dueDate == todayStr).length;
}

/// Number of active orders currently marked `urgency=critical` — drives the
/// `AlertSection` banner count (FR5/AC9). The popup mechanism
/// (`checkAndShowCriticalAlert`) is reused unchanged from
/// `critical_alert_provider.dart`; this helper only supplies the persistent
/// banner count shown on the dashboard.
int countCriticalOrders(List<Order> orders) {
  return orders
      .where((o) => o.urgency == 'critical')
      .length;
}

/// Sum of `totalPrice` for today's active orders — the "orders" half of
/// today's revenue (FR4). Mirrors [countOrdersToday]'s day filter so the two
/// revenue sources share the same definition of "hôm nay".
double sumOrdersRevenueToday(List<Order> orders) {
  final todayStr = formatApiDate(DateTime.now());
  return orders
      .where((o) => o.dueDate == todayStr)
      .fold(0.0, (sum, o) => sum + o.totalPrice);
}

/// Revenue + low-stock result computed in parallel (FR4/NFR2).
///
/// `revenueToday` combines the journal credit total for account 4100 with the
/// sum of `totalPrice` from today's active orders. `lowStockCount` is the
/// number of stock-overview items whose total quantity is ≤
/// [lowStockThreshold]. Both values are fetched concurrently via
/// `Future.wait` so the journal and stock APIs fire in parallel; the orders
/// API runs in parallel too (watched via [orderListProvider] in the screen).
class DashboardRevenueStock {
  const DashboardRevenueStock({
    required this.revenueToday,
    required this.lowStockCount,
  });

  final double revenueToday;
  final int lowStockCount;
}

/// Fetches today's journal entries for the revenue account (4100) and the
/// stock overview in parallel, then folds them into a [DashboardRevenueStock]
/// (FR4/NFR2). Errors from either call are propagated so the UI can show a
/// retry affordance — partial failure is not silently swallowed.
final FutureProvider<DashboardRevenueStock> dashboardRevenueStockProvider =
    FutureProvider<DashboardRevenueStock>((ref) async {
  final accounting = ref.watch(accountingServiceProvider);
  final stock = ref.watch(stockServiceProvider);

  final todayStr = formatApiDate(DateTime.now());

  // Fire both calls simultaneously (FR4/NFR2 — parallel API calls).
  final results = await Future.wait<
      ({
        double journalRevenue,
        int lowStockCount,
      })>([
    // Journal revenue: sum credits to account 4100 for today.
    () async {
      final resp = await accounting.listJournal(
        since: todayStr,
        until: todayStr,
        accountId: int.parse(revenueAccountCode),
        limit: 500,
      );
      final journalRevenue = _sumRevenueCredits(resp.items, revenueAccountCode);
      return (
        journalRevenue: journalRevenue,
        lowStockCount: 0,
      );
    }(),
    // Low-stock count from stock overview.
    () async {
      final items = await stock.getStockOverview();
      final lowStock = items
          .where((i) => i.totalQuantity <= lowStockThreshold)
          .length;
      return (
        journalRevenue: 0.0,
        lowStockCount: lowStock,
      );
    }(),
  ]);

  final journalRevenue = results
      .fold<double>(0.0, (sum, r) => sum + r.journalRevenue);
  final lowStockCount = results.fold<int>(0, (sum, r) => sum + r.lowStockCount);

  // Add the orders revenue half (FR4 — combined journal + orders). The
  // orders list is watched separately via orderListProvider in the screen;
  // here we re-read its current value to fold in the orders' totalPrice sum
  // without making a second orders API call.
  final ordersAsync = ref.read(orderListProvider);
  final orders = ordersAsync.asData?.value ?? const <Order>[];
  final ordersRevenue = sumOrdersRevenueToday(orders);

  return DashboardRevenueStock(
    revenueToday: journalRevenue + ordersRevenue,
    lowStockCount: lowStockCount,
  );
});

/// Sums the credit amounts of journal lines whose account code/id matches
/// [accountCode]. Revenue accounts (4xxx) are credit-normal, so credits to
/// account 4100 represent sales revenue.
double _sumRevenueCredits(List<JournalEntry> entries, String accountCode) {
  double total = 0;
  for (final entry in entries) {
    for (final line in entry.lines) {
      if (line.accountCode == accountCode ||
          line.accountId == accountCode) {
        total += line.credit;
      }
    }
  }
  return total;
}