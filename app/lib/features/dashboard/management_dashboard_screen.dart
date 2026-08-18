import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../data/models/today_summary.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/section_title.dart';
import '../../data/providers/dashboard_metrics_provider.dart';
import '../../providers/order/critical_alert_provider.dart';
import '../../providers/order/due_date_order_list_providers.dart';
import '../../data/providers/order/order_list_providers.dart';
import '../../data/providers/today_journal_provider.dart';
import '../../shared/utils/date_formatting.dart';
import 'widgets/alert_section.dart';
import 'widgets/metric_card.dart';
import 'widgets/shortcut_grid.dart';
import 'widgets/today_order_list.dart';
import 'package:bakery_app/shared/labels/accounting.dart';
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
/// alert_section, today_order_list).
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
      body: const SafeArea(child: _ManagementDashboardBody()),
    );
  }
}

class _ManagementDashboardBody extends ConsumerStatefulWidget {
  const _ManagementDashboardBody();

  @override
  ConsumerState<_ManagementDashboardBody> createState() =>
      _ManagementDashboardBodyState();
}

class _ManagementDashboardBodyState
    extends ConsumerState<_ManagementDashboardBody> {
  /// Set when the most recent pull-to-refresh failed; cleared on the next
  /// successful refresh. Surfaced via a [SnackBar] so the user knows the
  /// displayed values may be stale (DG-374 cycle-3 C3-3 — the previous
  /// `catchError` fallbacks silently swallowed API errors).
  bool _refreshError = false;

  void _handleShortcutTap(BuildContext context, String route) =>
      context.push(route);

  @override
  Widget build(BuildContext context) {
    // NFR1: orders fetch fires first. NFR2: revenue + order count + low-stock
    // run in parallel via dashboardRevenueStockProvider (today-summary API +
    // stock overview). The TodayOrderList section now fetches its own rows
    // via dueDateOrdersProvider (CQ-1 — summary.orders was removed).
    final ordersAsync = ref.watch(orderListProvider);
    final revenueStockAsync = ref.watch(dashboardRevenueStockProvider);

    final orders = ordersAsync.asData?.value ?? const <Order>[];
    final criticalCount = ordersAsync.asData != null
        ? countCriticalOrders(orders)
        : 0;

    final revenueStock = revenueStockAsync.asData?.value;
    final revenueToday = revenueStock == null
        ? null
        : formatVND(revenueStock.revenueToday);

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
        if (failed) {
          setState(() => _refreshError = true);
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(SharedLabels.refreshFailed),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (_refreshError) {
          setState(() => _refreshError = false);
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: SharedLabels.dashboardSectionMetrics),
          const SizedBox(height: 8),
          if (_refreshError)
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
          _TodaySalesEntryCard(
            revenueToday: revenueToday,
            onTap: () => context.push('/today-sales'),
          ),
          const SizedBox(height: 20),
          const _TodayOrdersSection(),
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

/// Single entry-point card replacing the former three "Chỉ số hôm nay"
/// MetricCards (DG-374 Phase 1 / FR2). Tapping navigates to `/today-sales`.
/// Shows today's revenue as a live preview value when available.
class _TodaySalesEntryCard extends StatelessWidget {
  const _TodaySalesEntryCard({required this.revenueToday, required this.onTap});

  final String? revenueToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      icon: Icons.attach_money_outlined,
      label: SharedLabels.dashboardMetricViewTodaySales,
      value: revenueToday,
      onTap: onTap,
    );
  }
}

/// Today's orders section (FR6/AC6): today's orders grouped by status.
/// Extracted to keep the body widget under the 300-line screen threshold
/// (flutter-coding-standards §1).
///
/// CQ-1: the order rows now come from a dedicated [dueDateOrdersProvider]
/// fetch (`GET /api/orders?due_date=<today>`) instead of the removed
/// `summary.orders` list. The summary endpoint remains the source of truth
/// for revenue and order count; only the order rows are fetched separately.
class _TodayOrdersSection extends ConsumerWidget {
  const _TodayOrdersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayStr = formatApiDate(DateTime.now());
    final ordersAsync = ref.watch(dueDateOrdersProvider(todayStr));
    final todayOrders = ordersAsync.asData?.value ?? const <Order>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: SharedLabels.todayOrders),
        const SizedBox(height: 8),
        if (ordersAsync.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          TodayOrderList(orders: todayOrders),
      ],
    );
  }
}
