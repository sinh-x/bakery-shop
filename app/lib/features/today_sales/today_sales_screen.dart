import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../data/models/today_summary.dart';
import '../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../providers/order/order_list_providers.dart';
import '../../providers/today_journal_provider.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/section_title.dart';
import '../dashboard/widgets/today_order_list.dart';
import 'widgets/revenue_summary_section.dart';

/// Today Sales screen (DG-374 Phase 2 / FR3, FR4 / AC5, AC6).
///
/// Shows today's revenue summary (total revenue, order count, cash total,
/// bank transfer total) and an order list grouped by status with due-date/
/// time ordering. A date picker in the app bar switches the order-list view
/// to historical days. Revenue/cashflow sections always reflect today's live
/// data regardless of the selected date.
class TodaySalesScreen extends ConsumerStatefulWidget {
  const TodaySalesScreen({super.key});

  @override
  ConsumerState<TodaySalesScreen> createState() => _TodaySalesScreenState();
}

class _TodaySalesScreenState extends ConsumerState<TodaySalesScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  String _selectedDate = formatApiDate(DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = formatApiDate(picked));
    }
  }

  @override
  String screenRoutePath() => '/today-sales';

  @override
  void invalidateProviders() {
    ref.invalidate(orderListProvider);
    ref.invalidate(todayJournalProvider);
    ref.invalidate(dashboardRevenueStockProvider);
    ref.invalidate(todaySummaryProvider);
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
    final isToday = _selectedDate == formatApiDate(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
        title: Text(isToday
            ? SharedLabels.todaySalesTitle
            : formatDisplayDate(parseApiDate(_selectedDate))),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: VN.chonNgay,
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: onAutoRefreshTriggered,
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: SafeArea(
        child: _TodaySalesBody(selectedDate: _selectedDate, isToday: isToday),
      ),
    );
  }
}

class _TodaySalesBody extends ConsumerStatefulWidget {
  const _TodaySalesBody({
    required this.selectedDate,
    required this.isToday,
  });

  final String selectedDate;
  final bool isToday;

  @override
  ConsumerState<_TodaySalesBody> createState() => _TodaySalesBodyState();
}

class _TodaySalesBodyState extends ConsumerState<_TodaySalesBody> {
  bool _refreshError = false;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);
    final revenueStockAsync = ref.watch(dashboardRevenueStockProvider);
    final summaryAsync = widget.isToday
        ? ref.watch(todaySummaryProvider)
        : ref.watch(dateSummaryProvider(widget.selectedDate));

    final orders = ordersAsync.asData?.value ?? const <Order>[];
    final todayOrders =
        orders.where((o) => o.dueDate == widget.selectedDate).toList();

    final revenueStock = revenueStockAsync.asData?.value;
    final summary = summaryAsync.asData?.value;

    // Today: revenue from dashboardRevenueStockProvider (shares the same
    // today-summary API call) and cash/bank from the summary API. Historical:
    // everything from the summary API (revenue, cash, bank, cash-in,
    // cash-out, order count for the queried date).
    final totalRevenue = widget.isToday
        ? revenueStock?.revenueToday
        : summary?.revenue;
    final orderCount = widget.isToday
        ? (ordersAsync.asData != null ? todayOrders.length : null)
        : summary?.orderCount;
    final cashTotal = summary?.cashTotal;
    final bankTransferTotal = summary?.bankTransferTotal;

    return RefreshIndicator(
      onRefresh: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        ref.invalidate(orderListProvider);
        ref.invalidate(todayJournalProvider);
        ref.invalidate(dashboardRevenueStockProvider);
        ref.invalidate(todaySummaryProvider);
        ref.invalidate(dateSummaryProvider(widget.selectedDate));
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
          ref.read(
                  (widget.isToday
                          ? todaySummaryProvider
                          : dateSummaryProvider(widget.selectedDate))
                      .future)
              .catchError((_) {
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
          _OrderListSection(summaryAsync: summaryAsync),
        ],
      ),
    );
  }
}

/// Order-list section using the today-summary API. Orders are grouped by
/// status with due-date/time ordering within each group (DG-376 FR6/AC6).
class _OrderListSection extends StatelessWidget {
  const _OrderListSection({required this.summaryAsync});

  final AsyncValue<TodaySummary> summaryAsync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderListSection),
        const SizedBox(height: 8),
        summaryAsync.when(
          data: (summary) => TodayOrderList(orders: summary.orders),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text(
              SharedLabels.errorLoading,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
