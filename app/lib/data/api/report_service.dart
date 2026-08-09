import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final reportServiceProvider = Provider<ReportService>((ref) {
  final dio = ref.watch(dioProvider);
  return ReportService(dio);
});