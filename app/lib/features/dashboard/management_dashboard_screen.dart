import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/labels/shared.dart';
import '../../shared/labels/accounting.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../data/providers/dashboard_metrics_provider.dart';
import '../../providers/order/critical_alert_provider.dart';
import '../../providers/order/due_date_order_list_providers.dart';
import '../../data/providers/order/order_list_providers.dart';
import '../../data/providers/today_journal_provider.dart';
import '../../shared/utils/date_formatting.dart';
import 'widgets/management_dashboard_body.dart';

/// Management dashboard screen — admin-facing "Quản lý" tab.
///
/// Phase 3 wires the real API providers and progressive loading:
/// - `orderListProvider` (active orders + critical count) — fires first so
///   the critical-order alert banner renders within NFR1's ≤2s budget.
/// - `dashboardRevenueStockProvider` (today-summary API + stock overview) —
///   runs in parallel; revenue, today's order count, and low-stock metrics
///   fill in as soon as both API calls resolve (NFR2 — no UI blocking). The
///   today-summary API is the single source of truth for revenue (journal
///   4100 credits only) and order count (all orders due today, including
///   completed POS orders) — DG-376 Bug 1 + Bug 3 fixes.
/// - `todaySummaryProvider` feeds the [TodayOrderList] section (FR6/AC6):
///   today's orders grouped by status with a count per group.
/// - `critical_alert_provider.checkAndShowCriticalAlert` — reused unchanged
///   for the popup mechanism (FR5/AC9). The persistent [AlertSection] banner
///   is fed by [countCriticalOrders] from the live active order list.
///
/// Coding standards (FR6/NFR3/AC12): the screen file is ≤300 lines; inner
/// widget classes are extracted to `widgets/` (metric_card, shortcut_grid,
/// alert_section, today_order_list, management_dashboard_body,
/// today_sales_entry_card, today_orders_section).
class ManagementDashboardScreen extends ConsumerStatefulWidget {
  const ManagementDashboardScreen({super.key});

  @override
  ConsumerState<ManagementDashboardScreen> createState() =>
      _ManagementDashboardScreenState();
}

class _ManagementDashboardScreenState
    extends ConsumerState<ManagementDashboardScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  @override
  String screenRoutePath() => '/dashboard';

  @override
  void invalidateProviders() {
    // Phase 3 — invalidate the dashboard metric providers so auto-refresh
    // (15s timer / route re-entry / app resume) re-fetches fresh data.
    // todaySummaryProvider is also invalidated (DG-376 Phase 5 — FR6/AC6).
    ref.invalidate(orderListProvider);
    ref.invalidate(todayJournalProvider);
    ref.invalidate(dashboardRevenueStockProvider);
    ref.invalidate(todaySummaryProvider);
    // CQ-1: today's order rows now come from a separate fetch — invalidate
    // it alongside the summary so auto-refresh re-fetches the list too.
    ref.invalidate(dueDateOrdersProvider(formatApiDate(DateTime.now())));
  }

  @override
  void onAutoRefreshTriggered() {
    super.onAutoRefreshTriggered();
    checkAndShowCriticalAlert(ref: ref, context: context, mounted: mounted);
  }

  @override
  void initState() {
    super.initState();
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text(SharedLabels.tabManagement),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: SharedLabels.lamMoi,
            onPressed: onAutoRefreshTriggered,
          ),
          AppBarOverflowMenu(
            onSelected: (value) {
              if (value == 'accounting') {
                context.push('/accounting');
              }
            },
            items: const [
              PopupMenuItem<String>(
                value: 'accounting',
                child: Text(AccountingLabels.accountingTitle),
              ),
            ],
          ),
        ],
      ),
      body: const SafeArea(child: ManagementDashboardBody()),
    );
  }
}