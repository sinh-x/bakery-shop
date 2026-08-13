import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cashflow_summary.dart';
import '../models/expense_summary.dart';
import '../models/period_summary.dart';
import '../models/product_breakdown.dart';
import '../models/today_summary.dart';
import 'api_client.dart';

/// Reporting API client (DG-376). Wraps the backend reporting endpoints that
/// provide a single source of truth for the Today Sales dashboard metrics.
class ReportService {
  final Dio _dio;

  ReportService(this._dio);

  /// Fetches the day-summary report for [date] (`YYYY-MM-DD`).
  ///
  /// Calls `GET /api/reports/today-summary?date=YYYY-MM-DD`. When [date] is
  /// omitted the backend defaults to the current UTC day. The response is
  /// decoded into a [TodaySummary] carrying revenue, order count, cash/bank
  /// totals, and the full order list for the day.
  Future<TodaySummary> getTodaySummary({String? date}) async {
    final params = <String, dynamic>{};
    if (date != null && date.isNotEmpty) params['date'] = date;
    final response = await _dio.get(
      '/api/reports/today-summary',
      queryParameters: params,
    );
    return TodaySummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the period-summary report for [period] (`week` or `month`)
  /// anchored at [date] (`YYYY-MM-DD`) (DG-386 Phase 1).
  ///
  /// Mirrors [getTodaySummary] but aggregates over the full week
  /// (Monday–Sunday) or month (1st–last day) containing [date]. When [date]
  /// is omitted the backend defaults to the current day.
  Future<PeriodSummary> getPeriodSummary({
    required String period,
    String? date,
  }) async {
    final params = <String, dynamic>{'period': period};
    if (date != null && date.isNotEmpty) params['date'] = date;
    final response = await _dio.get(
      '/api/reports/period-summary',
      queryParameters: params,
    );
    return PeriodSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the per-product revenue breakdown for [period] anchored at
  /// [date] (DG-386 Phase 2).
  ///
  /// Returns top 10 products + an `others` row sorted by revenue descending.
  Future<ProductBreakdown> getProductBreakdown({
    required String period,
    String? date,
  }) async {
    final params = <String, dynamic>{'period': period};
    if (date != null && date.isNotEmpty) params['date'] = date;
    final response = await _dio.get(
      '/api/reports/product-breakdown',
      queryParameters: params,
    );
    return ProductBreakdown.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the expense summary for [period] anchored at [date]
  /// (DG-386 Phase 3).
  ///
  /// Returns total expenses with the full parent/child category tree.
  Future<ExpenseSummary> getExpenseSummary({
    required String period,
    String? date,
  }) async {
    final params = <String, dynamic>{'period': period};
    if (date != null && date.isNotEmpty) params['date'] = date;
    final response = await _dio.get(
      '/api/reports/expense-summary',
      queryParameters: params,
    );
    return ExpenseSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the operating cashflow summary for [period] anchored at [date]
  /// (DG-386 Phase 4).
  ///
  /// Returns operating inflow/outflow with supplier category breakdown,
  /// computed from journal entries (no active cash drawer required).
  Future<CashflowSummary> getCashflowSummary({
    required String period,
    String? date,
  }) async {
    final params = <String, dynamic>{'period': period};
    if (date != null && date.isNotEmpty) params['date'] = date;
    final response = await _dio.get(
      '/api/reports/cashflow-summary',
      queryParameters: params,
    );
    return CashflowSummary.fromJson(response.data as Map<String, dynamic>);
  }
}

final reportServiceProvider = Provider<ReportService>((ref) {
  final dio = ref.watch(dioProvider);
  return ReportService(dio);
});