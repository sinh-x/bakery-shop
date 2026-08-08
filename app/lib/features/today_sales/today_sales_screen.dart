import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/cash_drawer_provider.dart';
import '../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../providers/order/order_list_providers.dart';
import '../../providers/today_journal_provider.dart';
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
  /// Today's date (API format), captured once in [initState] so it stays
  /// stable for the screen's lifetime. Recomputing `DateTime.now()` in
  /// `build` would let the date roll past midnight while provider caches
  /// still hold the prior day's data, causing an empty order list (CQ-5).
  late final String todayStr = formatApiDate(DateTime.now());

  @override
  String screenRoutePath() => '/today-sales';

  @override
  void invalidateProviders() {
    ref.invalidate(orderListProvider);
    ref.invalidate(todayJournalProvider);
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
      body: SafeArea(
        child: _TodaySalesBody(todayStr: todayStr),
      ),
    );
  }
}

class _TodaySalesBody extends ConsumerStatefulWidget {
  const _TodaySalesBody({required this.todayStr});

  /// Stable today-date string (API format) captured once by the parent
  /// [TodaySalesScreen] state. Used to filter orders to today's set without
  /// recomputing `DateTime.now()` on every rebuild (CQ-5).
  final String todayStr;

  @override
  ConsumerState<_TodaySalesBody> createState() => _TodaySalesBodyState();
}

class _TodaySalesBodyState extends ConsumerState<_TodaySalesBody> {
  /// Set when the most recent pull-to-refresh failed; cleared on the next
  /// successful refresh. Surfaced via a [SnackBar] so the user knows the
  /// displayed values may be stale (DG-374 cycle-3 C3-3 — the previous
  /// `catchError` fallbacks silently swallowed API errors).
  bool _refreshError = false;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);
    final revenueStockAsync = ref.watch(dashboardRevenueStockProvider);
    final paymentSplitAsync = ref.watch(todayPaymentSplitProvider);

    final orders = ordersAsync.asData?.value ?? const <Order>[];
    final todayOrders =
        orders.where((o) => o.dueDate == widget.todayStr).toList();

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
        // Capture the messenger before the async gap so the SnackBar can be
        // shown after the refresh completes without tripping the
        // use_build_context_synchronously lint (C3-3).
        final messenger = ScaffoldMessenger.maybeOf(context);
        ref.invalidate(orderListProvider);
        ref.invalidate(todayJournalProvider);
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
        // Track per-future errors so we can surface a single SnackBar when
        // any refresh leg failed (C3-3), while keeping graceful fallback
        // values so existing data remains visible.
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
          ref.read(todayPaymentSplitProvider.future).catchError((_) {
            failed = true;
            return const TodayPaymentSplit(
              cashTotal: 0,
              bankTransferTotal: 0,
            );
          }),
          ref.read(cashDrawerStatusProvider.future).catchError((_) {
            failed = true;
            return null;
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
          if (_refreshError)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                SharedLabels.refreshFailed,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ),
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
