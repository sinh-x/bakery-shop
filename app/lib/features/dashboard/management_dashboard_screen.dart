import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import '../../providers/order/critical_alert_provider.dart';
import 'widgets/alert_section.dart';
import 'widgets/metric_card.dart';
import 'widgets/shortcut_grid.dart';

/// Management dashboard screen — the new admin-facing "Quản lý" tab.
///
/// Replaces the legacy `DashboardScreen` (403 lines, 6 inner classes — see
/// docs/flutter-coding-standards.md §2). This file is the Phase 1 UI
/// scaffold: it renders the metric cards, shortcut grid, and alert section
/// with placeholder/loading values. Phase 3 will wire the real API providers
/// (`OrderService.listActiveOrders()`, journal + stock overview) and
/// progressive loading.
///
/// Coding standards compliance (FR6/NFR3/AC12): the screen file is ≤300
/// lines; the three inner widget classes that would have lived here are
/// extracted to `widgets/` (metric_card, shortcut_grid, alert_section).
///
/// Routes: `/dashboard` (wired in Phase 2 via `app_router.dart`).
/// Auto-refresh: reuses `AutoRefreshMixin` (15s timer + lifecycle + route
/// listener) — the same pattern as `DashboardScreen` and `OrderListScreen`.
/// Critical alerts: reuses `critical_alert_provider.checkAndShowCriticalAlert`
/// unchanged (FR5/AC9).
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
    // Phase 3 will invalidate the dashboard metrics providers here.
    // Phase 1 has no providers to invalidate yet.
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
        title: const Text(VN.tabDashboard),
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
  /// Phase 1 placeholder values. `null` => loading skeleton (NFR2).
  /// Phase 3 replaces these with real API-driven state.
  String? _ordersToday;
  String? _revenueToday;
  String? _lowStockCount;

  @override
  void initState() {
    super.initState();
    // Phase 1 scaffolding: render loading skeletons on first frame so the
    // layout is visible while Phase 3 providers are not yet wired.
  }

  void _refresh() {
    setState(() {
      _ordersToday = null;
      _revenueToday = null;
      _lowStockCount = null;
    });
  }

  void _handleShortcutTap(String route) => context.go(route);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle(title: 'Chỉ số hôm nay'),
          const SizedBox(height: 8),
          _MetricRow(
            ordersToday: _ordersToday,
            revenueToday: _revenueToday,
            lowStockCount: _lowStockCount,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Truy cập nhanh'),
          const SizedBox(height: 8),
          ShortcutGrid(onNavigate: _handleShortcutTap),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Cảnh báo'),
          const SizedBox(height: 8),
          AlertSection(
            count: 0,
            onTap: () => checkAndShowCriticalAlert(
              ref: ref,
              context: context,
              mounted: mounted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.ordersToday,
    required this.revenueToday,
    required this.lowStockCount,
  });

  final String? ordersToday;
  final String? revenueToday;
  final String? lowStockCount;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MetricCard(
              icon: Icons.receipt_outlined,
              label: 'Đơn hàng hôm nay',
              value: ordersToday,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MetricCard(
              icon: Icons.payments_outlined,
              label: 'Doanh thu hôm nay',
              value: revenueToday,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MetricCard(
              icon: Icons.inventory_outlined,
              label: 'Tồn kho thấp',
              value: lowStockCount,
              color: Colors.red,
            ),
          ),
        ],
      ),
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