import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../providers/order/order_list_providers.dart';
import '../../providers/today_sales_provider.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/cashflow_breakdown_section.dart';
import 'widgets/revenue_summary_section.dart';
import 'widgets/today_order_list.dart';

/// Today Sales screen (DG-374 Phase 2 / FR3, FR4 / AC5, AC6).
///
/// Shows today's revenue summary (total revenue, order count, cash total,
/// bank transfer total) and today's order list (order ref, customer, status,
/// total price, payment status). Reuses the existing [orderListProvider],
/// [dashboardRevenueStockProvider], and the new [todayPaymentSplitProvider]
/// so all three API calls fire in parallel via Riverpod's watch (NFR1).
///
/// Coding standards (NFR2): the screen file is ≤300 lines; inner widget
/// classes ([_AppBarRefresh], etc.) are kept small and the heavy rendering
/// is delegated to [RevenueSummarySection] and [TodayOrderList] under
/// `widgets/`.
class TodaySalesScreen extends ConsumerStatefulWidget {
  const TodaySalesScreen({super.key});

  @override
  ConsumerState<TodaySalesScreen> createState() => _TodaySalesScreenState();
}

class _TodaySalesScreenState extends ConsumerState<TodaySalesScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  @override
  String screenRoutePath() => '/today-sales';

  @override
  void invalidateProviders() {
    ref.invalidate(orderListProvider);
    ref.invalidate(dashboardRevenueStockProvider);
    ref.invalidate(todayPaymentSplitProvider);
    ref.invalidate(cashDrawerStatusProvider);
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
        title: const Text(SharedLabels.todaySalesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: onAutoRefreshTriggered,
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: const SafeArea(
        child: _TodaySalesBody(),
      ),
    );
  }
}

class _TodaySalesBody extends ConsumerWidget {
  const _TodaySalesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(orderListProvider);
    final revenueStockAsync = ref.watch(dashboardRevenueStockProvider);
    final paymentSplitAsync = ref.watch(todayPaymentSplitProvider);

    final todayStr = formatApiDate(DateTime.now());
    final orders = ordersAsync.asData?.value ?? const <Order>[];
    final todayOrders =
        orders.where((o) => o.dueDate == todayStr).toList();

    final revenueStock = revenueStockAsync.asData?.value;
    final totalRevenue = revenueStock?.revenueToday;
    final orderCount = ordersAsync.asData != null
        ? todayOrders.length
        : null;

    final paymentSplit = paymentSplitAsync.asData?.value;
    final cashTotal = paymentSplit?.cashTotal;
    final bankTransferTotal = paymentSplit?.bankTransferTotal;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(orderListProvider);
        ref.invalidate(dashboardRevenueStockProvider);
        ref.invalidate(todayPaymentSplitProvider);
        ref.invalidate(cashDrawerStatusProvider);
        // Invalidate the active drawer's first transaction page so the
        // cashflow breakdown refreshes alongside the other sections.
        final activeDrawerId =
            int.tryParse(ref.read(cashDrawerStatusProvider).asData?.value?.id ?? '');
        if (activeDrawerId != null) {
          ref.invalidate(cashDrawerTransactionsProvider(
            CashDrawerTransactionsFilter(drawerId: activeDrawerId),
          ));
        }
        await Future.wait([
          ref.read(orderListProvider.future).catchError((_) => <Order>[]),
          ref
              .read(dashboardRevenueStockProvider.future)
              .catchError((_) => const DashboardRevenueStock(
                    revenueToday: 0,
                    lowStockCount: 0,
                  )),
          ref
              .read(todayPaymentSplitProvider.future)
              .catchError((_) => const TodayPaymentSplit(
                    cashTotal: 0,
                    bankTransferTotal: 0,
                  )),
          ref
              .read(cashDrawerStatusProvider.future)
              .catchError((_) => null),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RevenueSummarySection(
            totalRevenue: totalRevenue,
            orderCount: orderCount,
            cashTotal: cashTotal,
            bankTransferTotal: bankTransferTotal,
          ),
          const SizedBox(height: 20),
          TodayOrderList(
            orders: todayOrders,
            isLoading: ordersAsync.isLoading,
            error: ordersAsync.hasError ? ordersAsync.error : null,
            onRetry: () => ref.invalidate(orderListProvider),
          ),
          const SizedBox(height: 20),
          const CashflowBreakdownSection(),
        ],
      ),
    );
  }
}