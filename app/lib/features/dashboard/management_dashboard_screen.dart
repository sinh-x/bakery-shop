import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/section_title.dart';
import '../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../providers/order/critical_alert_provider.dart';
import '../../providers/order/order_list_providers.dart';
import '../../providers/today_journal_provider.dart';
import 'widgets/alert_section.dart';
import 'widgets/metric_card.dart';
import 'widgets/shortcut_grid.dart';

/// Management dashboard screen — admin-facing "Quản lý" tab.
///
/// Phase 3 wires the real API providers and progressive loading:
/// - `orderListProvider` (orders today + critical count) — fires first so
///   the "Đơn hàng hôm nay" metric renders within NFR1's ≤2s budget.
/// - `dashboardRevenueStockProvider` (journal 4100 + stock overview) — runs
///   in parallel with the orders fetch; revenue + low-stock metrics fill in
///   as soon as both API calls resolve (NFR2 — no UI blocking).
/// - `critical_alert_provider.checkAndShowCriticalAlert` — reused unchanged
///   for the popup mechanism (FR5/AC9). The persistent [AlertSection] banner
///   is fed by [countCriticalOrders] from the live order list.
///
/// Coding standards (FR6/NFR3/AC12): the screen file is ≤300 lines; inner
/// widget classes are extracted to `widgets/` (metric_card, shortcut_grid,
/// alert_section).
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
    ref.invalidate(orderListProvider);
    ref.invalidate(todayJournalProvider);
    ref.invalidate(dashboardRevenueStockProvider);
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
            tooltip: VN.lamMoi,
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
                child: Text(VN.accountingTitle),
              ),
            ],
          ),
        ],
      ),
      body: const SafeArea(
        child: _ManagementDashboardBody(),
      ),
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
    // Orders fetch fires first (NFR1 — first metric within ≤2s). Revenue +
    // low-stock run in parallel via dashboardRevenueStockProvider (NFR2).
    final ordersAsync = ref.watch(orderListProvider);
    final revenueStockAsync = ref.watch(dashboardRevenueStockProvider);

    final orders = ordersAsync.asData?.value ?? const <Order>[];
    final criticalCount = ordersAsync.asData != null
        ? countCriticalOrders(orders)
        : 0;

    final revenueStock = revenueStockAsync.asData?.value;
    // Progressive loading (NFR2): revenue stays as a skeleton until both
    // journal + stock calls resolve; null while loading/refreshing. Shown as
    // a live preview on the "Xem doanh số hôm nay" entry-point card.
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
              lowStockCount: 0,
            );
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