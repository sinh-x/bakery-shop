import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../providers/order/critical_alert_provider.dart';
import '../../providers/order/order_list_providers.dart';
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

class _ManagementDashboardBody extends ConsumerWidget {
  const _ManagementDashboardBody();

  void _handleShortcutTap(BuildContext context, String route) =>
      context.push(route);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        ref.invalidate(orderListProvider);
        ref.invalidate(dashboardRevenueStockProvider);
        await Future.wait([
          ref.read(orderListProvider.future).catchError((_) => <Order>[]),
          ref
              .read(dashboardRevenueStockProvider.future)
              .catchError((_) => const DashboardRevenueStock(
                    revenueToday: 0,
                    lowStockCount: 0,
                  )),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle(title: SharedLabels.dashboardSectionMetrics),
          const SizedBox(height: 8),
          _TodaySalesEntryCard(
            revenueToday: revenueToday,
            onTap: () => context.push('/today-sales'),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: SharedLabels.dashboardSectionShortcuts),
          const SizedBox(height: 8),
          ShortcutGrid(
            onNavigate: (route) => _handleShortcutTap(context, route),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: SharedLabels.dashboardSectionAlerts),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}