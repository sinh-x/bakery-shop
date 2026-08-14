import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/report_service.dart';
import '../../data/models/cashflow_summary.dart';
import '../../data/models/expense_summary.dart';
import '../../data/models/period_summary.dart';
import '../../data/models/product_breakdown.dart';
import '../../shared/utils/date_formatting.dart';

/// Identifies a week-or-month period query for the summary screen family
/// providers (DG-386 Phase 5).
///
/// - [period] is `'week'` (Monday–Sunday) or `'month'` (1st–last day).
/// - [date] is the `YYYY-MM-DD` reference day anchoring the period. When
///   empty the backend defaults to the current day.
class PeriodQuery {
  const PeriodQuery({required this.period, this.date = ''});

  final String period;
  final String date;

  @override
  bool operator ==(Object other) =>
      other is PeriodQuery && other.period == period && other.date == date;

  @override
  int get hashCode => Object.hash(period, date);

  @override
  String toString() => 'PeriodQuery($period, $date)';
}

/// Convenience constructor for the "current period" query used by the Tuần/
/// Tháng tabs on first load.
PeriodQuery currentPeriodQuery(String period) =>
    PeriodQuery(period: period, date: formatApiDate(DateTime.now()));

/// Period-summary report family (DG-386 Phase 1 / FR2 / AC1, AC2, AC7).
///
/// Same family pattern as [dateSummaryProvider] but keyed by a [PeriodQuery]
/// so the Tuần/Tháng tabs can fetch the backend-aggregated week or month
/// summary. Switching the tab or navigating to a different week/month
/// produces a new [PeriodQuery] and triggers a fresh fetch (AC7).
final periodSummaryProvider =
    FutureProvider.family<PeriodSummary, PeriodQuery>((ref, query) async {
  final reports = ref.watch(reportServiceProvider);
  return reports.getPeriodSummary(period: query.period, date: query.date);
});

/// Product-breakdown report family (DG-386 Phase 2 / FR3 / AC3).
final productBreakdownProvider =
    FutureProvider.family<ProductBreakdown, PeriodQuery>((ref, query) async {
  final reports = ref.watch(reportServiceProvider);
  return reports.getProductBreakdown(period: query.period, date: query.date);
});

/// Expense-summary report family (DG-386 Phase 3 / FR4 / AC4).
final expenseSummaryProvider =
    FutureProvider.family<ExpenseSummary, PeriodQuery>((ref, query) async {
  final reports = ref.watch(reportServiceProvider);
  return reports.getExpenseSummary(period: query.period, date: query.date);
});

/// Cashflow-summary report family (DG-386 Phase 4 / FR5 / AC5).
final cashflowSummaryProvider =
    FutureProvider.family<CashflowSummary, PeriodQuery>((ref, query) async {
  final reports = ref.watch(reportServiceProvider);
  return reports.getCashflowSummary(period: query.period, date: query.date);
});

/// Combined period data fetched in parallel for one [PeriodQuery]
/// (NFR3 — parallel fetch via `Future.wait`, mirroring
/// [dashboardRevenueStockProvider]).
class PeriodReportData {
  const PeriodReportData({
    required this.summary,
    required this.productBreakdown,
    required this.expenseSummary,
    required this.cashflowSummary,
  });

  final PeriodSummary summary;
  final ProductBreakdown productBreakdown;
  final ExpenseSummary expenseSummary;
  final CashflowSummary cashflowSummary;
}

/// Fires all four period endpoints in parallel for one [PeriodQuery]
/// (NFR3 / AC7). Errors from any call propagate so the UI can show a retry
/// affordance — partial failure is not silently swallowed.
final periodReportDataProvider =
    FutureProvider.family<PeriodReportData, PeriodQuery>((ref, query) async {
  // Watch each family member so the combined provider is invalidated when
  // any source is invalidated, then resolve them concurrently.
  final summaryFuture = ref.watch(periodSummaryProvider(query).future);
  final productFuture = ref.watch(productBreakdownProvider(query).future);
  final expenseFuture = ref.watch(expenseSummaryProvider(query).future);
  final cashflowFuture = ref.watch(cashflowSummaryProvider(query).future);

  final results = await Future.wait<dynamic>([
    summaryFuture,
    productFuture,
    expenseFuture,
    cashflowFuture,
  ]);

  return PeriodReportData(
    summary: results[0] as PeriodSummary,
    productBreakdown: results[1] as ProductBreakdown,
    expenseSummary: results[2] as ExpenseSummary,
    cashflowSummary: results[3] as CashflowSummary,
  );
});