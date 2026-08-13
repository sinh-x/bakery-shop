import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cashflow_summary.dart';
import '../../../data/models/expense_summary.dart';
import '../../../data/models/order.dart';
import '../../../data/models/period_summary.dart';
import '../../../data/models/product_breakdown.dart';
import '../../../providers/dashboard/period_summary_providers.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/today_order_list.dart';
import 'cashflow_summary_section.dart';
import 'expense_summary_section.dart';
import 'product_breakdown_section.dart';
import 'revenue_summary_section.dart';

/// Shifts a [DateTime] anchor by one week (±7 days) or one month (±1 month)
/// so the backend can re-derive the new period window from the new anchor.
///
/// For month shifts the day is clamped to the target month's last day so a
/// 31st-of-month anchor does not skip a month when the target has fewer
/// days (Dart normalizes overflow, e.g. Jan 31 + 1 month → Feb 31 → Mar 3).
DateTime shiftPeriodAnchor(DateTime anchor, {required bool isWeek, required int direction}) {
  if (isWeek) {
    return anchor.add(Duration(days: 7 * direction));
  }
  int targetYear = anchor.year;
  int targetMonth = anchor.month + direction;
  if (targetMonth > 12) {
    targetYear = anchor.year + 1;
    targetMonth = 1;
  } else if (targetMonth < 1) {
    targetYear = anchor.year - 1;
    targetMonth = 12;
  }
  // DateTime(year, month + 1, 0).day is the last day of `month`.
  final lastDayOfMonth = DateTime(targetYear, targetMonth + 1, 0).day;
  final clampedDay = anchor.day < lastDayOfMonth ? anchor.day : lastDayOfMonth;
  return DateTime(targetYear, targetMonth, clampedDay);
}

/// Week/Month tab body for the Today Sales screen (DG-386 Phase 6 / FR1,
/// FR2 / AC1, AC2, AC7).
///
/// Renders the period-aggregated summary for a [PeriodQuery] (week or month).
/// All four period endpoints are fired in parallel via
/// [periodReportDataProvider] (NFR3 — `Future.wait`), so revenue, product
/// breakdown, expense summary, and cashflow summary all resolve together.
/// Switching the tab or navigating to a different week/month produces a new
/// [PeriodQuery] and triggers a fresh fetch (AC7).
///
/// Reuses [RevenueSummarySection] for the revenue/payment/cash-source cards
/// because the [PeriodSummary] metric fields are identical in shape to
/// `TodaySummary`. The product/expense/cashflow sections are implemented and
/// wired here (DG-386 Phases 7–11 / FR1).
class PeriodTabBody extends ConsumerWidget {
  const PeriodTabBody({
    super.key,
    required this.query,
    required this.onNavigate,
  });

  final PeriodQuery query;

  final void Function(DateTime newAnchor) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(periodReportDataProvider(query));

    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            SharedLabels.errorLoading,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (report) => _PeriodTabContent(
        summary: report.summary,
        productBreakdown: report.productBreakdown,
        expenseSummary: report.expenseSummary,
        cashflowSummary: report.cashflowSummary,
        query: query,
        onNavigate: onNavigate,
      ),
    );
  }
}

class _PeriodTabContent extends StatelessWidget {
  const _PeriodTabContent({
    required this.summary,
    required this.productBreakdown,
    required this.expenseSummary,
    required this.cashflowSummary,
    required this.query,
    required this.onNavigate,
  });

  final PeriodSummary summary;
  final ProductBreakdown productBreakdown;
  final ExpenseSummary expenseSummary;
  final CashflowSummary cashflowSummary;
  final PeriodQuery query;
  final void Function(DateTime newAnchor) onNavigate;

  bool get _isWeek => query.period == 'week';

  DateTime get _anchor => parseApiDate(query.date) ?? DateTime.now();

  /// Shifts the anchor by one week (±7 days) or one month (±1 month) so the
  /// backend re-derives the new period window from the new anchor. Delegates
  /// to [shiftPeriodAnchor] for the clamping logic.
  DateTime _shift(int direction) => shiftPeriodAnchor(
        _anchor,
        isWeek: _isWeek,
        direction: direction,
      );

  String get _periodLabel {
    if (_isWeek) {
      final start = parseApiDate(summary.startDate);
      final end = parseApiDate(summary.endDate);
      if (start == null || end == null) return SharedLabels.todaySalesTabWeek;
      return '${formatDisplayDate(start)} - ${formatDisplayDate(end)}';
    }
    final start = parseApiDate(summary.startDate);
    if (start == null) return SharedLabels.todaySalesTabMonth;
    return '${start.month}/${start.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PeriodNavHeader(
          label: _periodLabel,
          onPrev: () => onNavigate(_shift(-1)),
          onNext: () => onNavigate(_shift(1)),
        ),
        const SizedBox(height: 16),
        RevenueSummarySection(
          totalRevenue: summary.revenue,
          orderCount: summary.orderCount,
          cashTotal: summary.cashTotal,
          bankTransferTotal: summary.bankTransferTotal,
          cashInTotal: summary.cashInTotal,
          cashOutTotal: summary.cashOutTotal,
        ),
        const SizedBox(height: 20),
        ProductBreakdownSection(breakdown: productBreakdown),
        const SizedBox(height: 20),
        ExpenseSummarySection(summary: expenseSummary),
        const SizedBox(height: 20),
        CashflowSummarySection(summary: cashflowSummary),
        const SizedBox(height: 20),
        _PeriodOrderListSection(orders: summary.orders),
      ],
    );
  }
}

/// Prev/next navigation header for the week/month tabs (FR1 / AC1, AC2).
class _PeriodNavHeader extends StatelessWidget {
  const _PeriodNavHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: SharedLabels.todaySalesPeriodPrevious,
          onPressed: onPrev,
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: SharedLabels.todaySalesPeriodNext,
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Order-list section for the week/month tabs. Renders the orders aggregated
/// within the period using the same [TodayOrderList] grouping as the day tab.
class _PeriodOrderListSection extends StatelessWidget {
  const _PeriodOrderListSection({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderListSection),
        const SizedBox(height: 8),
        TodayOrderList(orders: orders),
      ],
    );
  }
}