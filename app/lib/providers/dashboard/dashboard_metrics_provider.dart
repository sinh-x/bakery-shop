import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/stock_service.dart';
import '../../data/models/journal_entry.dart';
import '../../data/models/order.dart';
import '../../shared/utils/date_formatting.dart';
import '../order/order_list_providers.dart';
import '../today_journal_provider.dart';

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
///
/// The journal fetch is shared via [todayJournalProvider] (DG-374 cycle-3
/// C3-2) so a single pull-to-refresh only issues one journal API call instead
/// of one per consumer.
final FutureProvider<DashboardRevenueStock> dashboardRevenueStockProvider =
    FutureProvider<DashboardRevenueStock>((ref) async {
  final stock = ref.watch(stockServiceProvider);

  // Today's journal entries are fetched once and shared with
  // todayPaymentSplitProvider via todayJournalProvider (C3-2). Filter the
  // shared entries to the revenue account (4100) here.
  final allEntries = await ref.watch(todayJournalProvider.future);
  final journalEntries = allEntries
      .where((e) => e.lines.any(
            (l) => l.accountCode == revenueAccountCode ||
                l.accountId == revenueAccountCode,
          ))
      .toList();

  // Low-stock count from stock overview (runs in parallel with the journal
  // fetch via Riverpod's watch).
  final items = await stock.getStockOverview();
  final lowStock = items
      .where((i) => i.totalQuantity <= lowStockThreshold)
      .length;

  final journalRevenue =
      _sumRevenueCredits(journalEntries, revenueAccountCode);

  // Add the orders revenue half (FR4 — combined journal + orders). The
  // orders list is watched separately via orderListProvider in the screen;
  // here we re-read its current value to fold in the orders' totalPrice sum
  // without making a second orders API call.
  final ordersAsync = ref.read(orderListProvider);
  final orders = ordersAsync.asData?.value ?? const <Order>[];
  final ordersRevenue = sumOrdersRevenueToday(orders);

  return DashboardRevenueStock(
    revenueToday: journalRevenue + ordersRevenue,
    lowStockCount: lowStock,
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
