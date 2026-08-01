import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cash_drawer.dart';
import 'api_client.dart';

/// Client for the cash-drawer backend API (DG-324 Phase 4).
///
/// Wraps the six endpoints exposed by `src/baker/api/cash_drawer.py`:
///
///   POST /api/cash-drawer/open     → open a daily drawer (FR1)
///   POST /api/cash-drawer/close    → close with counted amount (FR7)
///   POST /api/cash-drawer/cash-in  → owner puts cash in (FR2)
///   POST /api/cash-drawer/cash-out → owner takes cash out (FR3)
///   GET  /api/cash-drawer/status   → active drawer or null (FR4)
///   GET  /api/cash-drawer/history  → paginated past drawers (FR10)
///
/// Balance-affecting mutations return the updated drawer with an optional
/// nested `journalEntry`. The status endpoint returns the active drawer or
/// `null` (200 with a null body) when no drawer is open.
class CashDrawerService {
  final Dio _dio;

  CashDrawerService(this._dio);

  /// FR1: open a daily cash drawer with a starting balance.
  Future<CashDrawer> openDrawer({
    required int openingBalance,
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/cash-drawer/open',
      data: {
        'openingBalance': openingBalance,
        'note': note,
      },
    );
    return CashDrawer.fromJson(response.data as Map<String, dynamic>);
  }

  /// FR2: owner puts cash into the active drawer.
  Future<CashDrawer> cashIn({
    required int amount,
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/cash-drawer/cash-in',
      data: {'amount': amount, 'note': note},
    );
    return CashDrawer.fromJson(response.data as Map<String, dynamic>);
  }

  /// FR3: owner takes cash out of the active drawer.
  Future<CashDrawer> cashOut({
    required int amount,
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/cash-drawer/cash-out',
      data: {'amount': amount, 'note': note},
    );
    return CashDrawer.fromJson(response.data as Map<String, dynamic>);
  }

  /// FR7: close the active drawer with a physical cash count.
  Future<CashDrawer> closeDrawer({
    required int countedAmount,
    String note = '',
  }) async {
    final response = await _dio.post(
      '/api/cash-drawer/close',
      data: {'countedAmount': countedAmount, 'note': note},
    );
    return CashDrawer.fromJson(response.data as Map<String, dynamic>);
  }

  /// FR4: return the active (open) drawer with its expected balance, or
  /// `null` when no drawer is currently open.
  Future<CashDrawer?> getDrawerStatus() async {
    final response = await _dio.get('/api/cash-drawer/status');
    final data = response.data;
    if (data == null) return null;
    if (data is Map<String, dynamic>) return CashDrawer.fromJson(data);
    return null;
  }

  /// FR10: paginated list of past drawers, optionally filtered by date range.
  Future<CashDrawerHistoryResponse> getDrawerHistory({
    String? since,
    String? until,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'offset': offset};
    if (since != null && since.isNotEmpty) query['since'] = since;
    if (until != null && until.isNotEmpty) query['until'] = until;
    final response = await _dio.get(
      '/api/cash-drawer/history',
      queryParameters: query,
    );
    return CashDrawerHistoryResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}

final cashDrawerServiceProvider = Provider<CashDrawerService>((ref) {
  final dio = ref.watch(dioProvider);
  return CashDrawerService(dio);
});