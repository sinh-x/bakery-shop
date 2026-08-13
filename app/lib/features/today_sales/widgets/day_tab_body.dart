import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cashflow_summary.dart';
import '../../../data/models/expense_summary.dart';
import '../../../data/models/product_breakdown.dart';
import '../../../data/models/today_summary.dart';
import '../../../providers/dashboard/dashboard_metrics_provider.dart';
import '../../../providers/dashboard/period_summary_providers.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/today_order_list.dart';
import 'cashflow_summary_section.dart';
import 'expense_summary_section.dart';
import 'product_breakdown_section.dart';
import 'revenue_summary_section.dart';

/// Day-tab body for the Today Sales screen (DG-386 Phase 6 / FR1).
///
/// Preserves the pre-Phase-6 behavior of the old `_TodaySalesBody`:
/// - `todaySummaryProvider` for today, `dateSummaryProvider(<date>)` for
///   historical days.
/// - Revenue + payment + cash-source breakdown via [RevenueSummarySection].
/// - Order list grouped by status with due-date/time ordering.
///
/// Phase 11 (FR1 / AC3-AC5) adds the product breakdown, expense summary, and
/// cashflow summary sections to the Ngày tab. These are fetched via the
/// period endpoints with `period=day` for the selected date, running in
/// parallel with the today-summary fetch (NFR3). The today-summary endpoint
/// remains the source of truth for revenue and orders so existing behavior
/// (date picker, refresh, today-vs-historical branch) is unchanged.
///
/// The date picker lives on the parent [TodaySalesScreen] AppBar and is only
/// shown when the Ngày tab is active; the selected date is passed in via
/// [selectedDate] and [isToday].
class DayTabBody extends ConsumerStatefulWidget {
  const DayTabBody({
    super.key,
    required this.selectedDate,
    required this.isToday,
  });

  final String selectedDate;
  final bool isToday;

  @override
  ConsumerState<DayTabBody> createState() => _DayTabBodyState();
}

class _DayTabBodyState extends ConsumerState<DayTabBody> {
  bool _refreshError = false;

  @override
  Widget build(BuildContext context) {
    final summaryProvider = widget.isToday
        ? todaySummaryProvider
        : dateSummaryProvider(widget.selectedDate);
    final summaryAsync = ref.watch(summaryProvider);
    final summary = summaryAsync.asData?.value;

    final totalRevenue = summary?.revenue;
    final orderCount = summary?.orderCount;
    final cashTotal = summary?.cashTotal;
    final bankTransferTotal = summary?.bankTransferTotal;
    final cashInTotal = summary?.cashInTotal;
    final cashOutTotal = summary?.cashOutTotal;

    // Phase 11 — period=day report data for the breakdown sections (NFR3:
    // the period providers fire in parallel with the today-summary fetch).
    final dayQuery = PeriodQuery(period: 'day', date: widget.selectedDate);
    final productBreakdownAsync = ref.watch(productBreakdownProvider(dayQuery));
    final expenseSummaryAsync = ref.watch(expenseSummaryProvider(dayQuery));
    final cashflowSummaryAsync = ref.watch(cashflowSummaryProvider(dayQuery));

    return RefreshIndicator(
      onRefresh: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        ref.invalidate(summaryProvider);
        ref.invalidate(productBreakdownProvider(dayQuery));
        ref.invalidate(expenseSummaryProvider(dayQuery));
        ref.invalidate(cashflowSummaryProvider(dayQuery));
        var failed = false;
        await ref.read(summaryProvider.future).catchError((_) {
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
        });
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
            cashInTotal: cashInTotal,
            cashOutTotal: cashOutTotal,
          ),
          const SizedBox(height: 20),
          _DayProductBreakdownSection(asyncValue: productBreakdownAsync),
          const SizedBox(height: 20),
          _DayExpenseSection(asyncValue: expenseSummaryAsync),
          const SizedBox(height: 20),
          _DayCashflowSection(asyncValue: cashflowSummaryAsync),
          const SizedBox(height: 20),
          _DayOrderListSection(summaryAsync: summaryAsync),
        ],
      ),
    );
  }
}

/// Product-breakdown section for the day tab. While the period=day fetch is
/// loading the section widget receives `null` and renders its built-in
/// loading/empty state; on error a compact error line is shown.
class _DayProductBreakdownSection extends StatelessWidget {
  const _DayProductBreakdownSection({required this.asyncValue});

  final AsyncValue<ProductBreakdown> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (breakdown) => ProductBreakdownSection(breakdown: breakdown),
      loading: () => const ProductBreakdownSection(breakdown: null),
      error: (_, _) => Center(
        child: Text(
          SharedLabels.errorLoading,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

/// Expense-summary section for the day tab.
class _DayExpenseSection extends StatelessWidget {
  const _DayExpenseSection({required this.asyncValue});

  final AsyncValue<ExpenseSummary> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (summary) => ExpenseSummarySection(summary: summary),
      loading: () => const ExpenseSummarySection(summary: null),
      error: (_, _) => Center(
        child: Text(
          SharedLabels.errorLoading,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

/// Cashflow-summary section for the day tab.
class _DayCashflowSection extends StatelessWidget {
  const _DayCashflowSection({required this.asyncValue});

  final AsyncValue<CashflowSummary> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (summary) => CashflowSummarySection(summary: summary),
      loading: () => const CashflowSummarySection(summary: null),
      error: (_, _) => Center(
        child: Text(
          SharedLabels.errorLoading,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

/// Order-list section for the day tab using the today-summary API. Orders
/// are grouped by status with due-date/time ordering within each group
/// (DG-376 FR6/AC6).
class _DayOrderListSection extends StatelessWidget {
  const _DayOrderListSection({required this.summaryAsync});

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