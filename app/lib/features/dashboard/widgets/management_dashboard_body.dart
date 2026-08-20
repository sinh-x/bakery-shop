import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../data/models/today_summary.dart';
import '../../../data/providers/dashboard_metrics_provider.dart';
import '../../../data/providers/order/order_list_providers.dart';
import '../../../data/providers/today_journal_provider.dart';
import '../../../providers/order/critical_alert_provider.dart';
import '../../../providers/order/due_date_order_list_providers.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils.dart' show formatVND;
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/section_title.dart';
import '../providers/management_dashboard_body_notifier.dart';
import 'alert_section.dart';
import 'shortcut_grid.dart';
import 'today_orders_section.dart';
import 'today_sales_entry_card.dart';

/// Body of the management dashboard screen. Hosts the refresh indicator,
/// the today-sales entry card, today's orders section, shortcut grid, and
/// the critical-order alert banner.
class ManagementDashboardBody extends ConsumerStatefulWidget {
  const ManagementDashboardBody({super.key});

  @override
  ConsumerState<ManagementDashboardBody> createState() =>
      ManagementDashboardBodyState();
}

class ManagementDashboardBodyState
    extends ConsumerState<ManagementDashboardBody> {
  void _handleShortcutTap(BuildContext context, String route) =>
      context.push(route);

  @override
  Widget build(BuildContext context) {
    // The refresh-error flag lives in [managementDashboardBodyProvider]
    // (DG-404 Phase 4.7); set/cleared from the pull-to-refresh callback
    // below.
    final refreshError =
        ref.watch(managementDashboardBodyProvider).refreshError;
    // NFR1: orders fetch fires first. NFR2: revenue + order count + low-stock
    // run in parallel via dashboardRevenueStockProvider (today-summary API +
    // stock overview). The TodayOrderList section now fetches its own rows
    // via dueDateOrdersProvider (CQ-1 — summary.orders was removed).
    final ordersAsync = ref.watch(orderListProvider);
    final revenueStockAsync = ref.watch(dashboardRevenueStockProvider);

    final orders = ordersAsync.asData?.value ?? const <Order>[];
    final criticalCount =
        ordersAsync.asData != null ? countCriticalOrders(orders) : 0;

    final revenueStock = revenueStockAsync.asData?.value;
    final revenueToday =
        revenueStock == null ? null : formatVND(revenueStock.revenueToday);

    return RefreshIndicator(
      onRefresh: () async {
        // Capture the messenger before the async gap so the SnackBar can be
        // shown after the refresh completes without tripping the
        // use_build_context_synchronously lint (C3-3).
        final messenger = ScaffoldMessenger.maybeOf(context);
        ref.invalidate(orderListProvider);
        ref.invalidate(todayJournalProvider);
        ref.invalidate(dashboardRevenueStockProvider);
        ref.invalidate(todaySummaryProvider);
        // CQ-1: invalidate the separate today-orders fetch so pull-to-refresh
        // re-fetches the order rows as well as the summary metrics.
        final todayStr = formatApiDate(DateTime.now());
        ref.invalidate(dueDateOrdersProvider(todayStr));
        var failed = false;
        await Future.wait<void>([
          ref.read(orderListProvider.future).catchError((_) {
            failed = true;
            return <Order>[];
          }),
          ref.read(dashboardRevenueStockProvider.future).catchError((_) {
            failed = true;
            return const DashboardRevenueStock(
              revenueToday: 0,
              orderCount: 0,
              lowStockCount: 0,
            );
          }),
          ref.read(todaySummaryProvider.future).catchError((_) {
            failed = true;
            return const TodaySummary(
              date: '',
              revenue: 0,
              orderCount: 0,
              cashTotal: 0,
              bankTransferTotal: 0,
              cashInTotal: 0,
              cashOutTotal: 0,
              orders: [],
            );
          }),
          ref.read(dueDateOrdersProvider(todayStr).future).catchError((_) {
            failed = true;
            return <Order>[];
          }),
        ]);
        if (!mounted) return;
        final notifier = ref.read(managementDashboardBodyProvider.notifier);
        if (failed) {
          notifier.setRefreshError(true);
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(SharedLabels.refreshFailed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (refreshError) {
          notifier.setRefreshError(false);
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: SharedLabels.dashboardSectionMetrics),
          const SizedBox(height: 8),
          if (refreshError)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                SharedLabels.refreshFailed,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
          TodaySalesEntryCard(
            revenueToday: revenueToday,
            onTap: () => context.push('/today-sales'),
          ),
          const SizedBox(height: 20),
          const TodayOrdersSection(),
          const SizedBox(height: 20),
          const SectionTitle(title: SharedLabels.dashboardSectionShortcuts),
          const SizedBox(height: 8),
          ShortcutGrid(
            onNavigate: (route) => _handleShortcutTap(context, route),
          ),
          const SizedBox(height: 20),
          const SectionTitle(title: SharedLabels.dashboardSectionAlerts),
          const SizedBox(height: 8),
          AlertSection(
            count: criticalCount,
            onTap: () => checkAndShowCriticalAlert(
              ref: ref,
              context: context,
              mounted: context.mounted,
            ),
          ),
        ],
      ),
    );
  }
}