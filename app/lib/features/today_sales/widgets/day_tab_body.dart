import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/dashboard_metrics_provider.dart';
import '../../../data/providers/period_summary_providers.dart';
import 'day_cashflow_section.dart';
import 'day_expense_section.dart';
import 'day_order_list_section.dart';
import 'day_product_breakdown_section.dart';
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
///
/// Coding standards (NFR2): the tab body delegates section rendering to
/// extracted widgets under `widgets/` (see [DayProductBreakdownSection],
/// [DayExpenseSection], [DayCashflowSection], [DayOrderListSection]).
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RevenueSummarySection(
          totalRevenue: totalRevenue,
          orderCount: orderCount,
          cashTotal: cashTotal,
          bankTransferTotal: bankTransferTotal,
          cashInTotal: cashInTotal,
          cashOutTotal: cashOutTotal,
        ),
        const SizedBox(height: 20),
        DayProductBreakdownSection(asyncValue: productBreakdownAsync),
        const SizedBox(height: 20),
        DayExpenseSection(asyncValue: expenseSummaryAsync),
        const SizedBox(height: 20),
        DayCashflowSection(asyncValue: cashflowSummaryAsync),
        const SizedBox(height: 20),
        DayOrderListSection(selectedDate: widget.selectedDate),
      ],
    );
  }
}