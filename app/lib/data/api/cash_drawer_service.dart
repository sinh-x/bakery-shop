import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cash_drawer.dart';
import 'api_client.dart';

/// FR9 carry-over proposal returned by the backend when opening today's
/// drawer while the previous day's drawer is still open. The backend raises
/// HTTP 409 with a `detail` body of:
///
///   {
///     "message": "Quỹ hôm trước chưa đóng ...",
///     "carryOverProposal": {
///       "amount": 1550000,
///       "fromDrawerId": "7",
///       "fromOpenedAt": "2026-07-28T08:00:00Z",
///       "fromExpectedBalance": 1550000
///     }
///   }
///
/// Thrown as [CarryOverProposalException] by [CashDrawerService.openDrawer]
/// so the caller can intercept it, prompt the owner, and re-call `openDrawer`
/// with `carryOverConfirmed: true` (accept) or `false` (decline).
class CarryOverProposalException implements Exception {
  CarryOverProposalException({
    required this.message,
    required this.amount,
    required this.fromDrawerId,
    required this.fromOpenedAt,
    required this.fromExpectedBalance,
  });

  final String message;
  final int amount;
  final String fromDrawerId;
  final String fromOpenedAt;
  final int fromExpectedBalance;

  @override
  String toString() =>
      'CarryOverProposalException(amount: $amount, fromDrawerId: $fromDrawerId)';
}

/// Client for the cash-drawer backend API (DG-324 Phase 2/6).
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
  ///
  /// FR9: when a previous-day drawer is still open and `carryOverConfirmed`
  /// is `false` (the default), the backend responds with HTTP 409 carrying a
  /// carry-over proposal. This method decodes that 409 and throws a
  /// [CarryOverProposalException] instead of a generic [DioException], so the
  /// caller can surface the proposal to the owner and re-call `openDrawer`
  /// with `carryOverConfirmed: true` (accept) or `false` (decline). On a
  /// successful open the returned [CashDrawer] is unchanged; the optional
  /// `carryOver` block on the success body is not surfaced as a separate
  /// field (the proposal was already confirmed by the caller).
  Future<CashDrawer> openDrawer({
    required int openingBalance,
    String note = '',
    bool carryOverConfirmed = false,
  }) async {
    try {
      final response = await _dio.post(
        '/api/cash-drawer/open',
        data: {
          'openingBalance': openingBalance,
          'note': note,
          'carryOverConfirmed': carryOverConfirmed,
        },
      );
      return CashDrawer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final proposal = _decodeCarryOverProposal(e);
      if (proposal != null) throw proposal;
      rethrow;
    }
  }

  /// Decodes a 409 `detail` body into a [CarryOverProposalException], or
  /// returns `null` when the error is not a carry-over proposal (so the
  /// caller can `rethrow` the original [DioException]).
  CarryOverProposalException? _decodeCarryOverProposal(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final dynamic detail = e.response?.data?['detail'];
    if (detail is! Map<String, dynamic>) return null;
    final proposalJson = detail['carryOverProposal'];
    if (proposalJson is! Map<String, dynamic>) return null;
    final amount = (proposalJson['amount'] as num?)?.toInt();
    final fromDrawerId = proposalJson['fromDrawerId']?.toString();
    final fromOpenedAt = proposalJson['fromOpenedAt']?.toString();
    final fromExpectedBalance =
        (proposalJson['fromExpectedBalance'] as num?)?.toInt();
    if (amount == null || fromDrawerId == null) return null;
    return CarryOverProposalException(
      message: (detail['message'] as String?) ?? '',
      amount: amount,
      fromDrawerId: fromDrawerId,
      fromOpenedAt: fromOpenedAt ?? '',
      fromExpectedBalance: fromExpectedBalance ?? amount,
    );
  }

  /// FR2/FR3a: owner puts cash into the active drawer.
  ///
  /// `source` selects the credit side (DG-330 Phase 3):
  ///   - `owner`   → CR 1102 (Owner's Cash)
  ///   - `employee`→ CR 23XX (staff advance; `staffName` required)
  ///   - `equity`  → CR 3100 (owner capital injection) — default, backward compat
  Future<CashDrawer> cashIn({
    required int amount,
    String note = '',
    String source = 'equity',
    String? staffName,
  }) async {
    final response = await _dio.post(
      '/api/cash-drawer/cash-in',
      data: {
        'amount': amount,
        'note': note,
        'source': source,
        if (staffName != null && staffName.isNotEmpty) 'staffName': staffName,
      },
    );
    return CashDrawer.fromJson(response.data as Map<String, dynamic>);
  }

  /// FR3/FR4: owner takes cash out of the active drawer.
  ///
  /// `destination` selects the debit side (DG-330 Phase 3):
  ///   - `owner`   → DR 1102 (Owner's Cash) — default, backward compat
  ///   - `employee`→ DR 23XX (employee advance; `staffName` required)
  Future<CashDrawer> cashOut({
    required int amount,
    String note = '',
    String destination = 'owner',
    String? staffName,
  }) async {
    final response = await _dio.post(
      '/api/cash-drawer/cash-out',
      data: {
        'amount': amount,
        'note': note,
        'destination': destination,
        if (staffName != null && staffName.isNotEmpty) 'staffName': staffName,
      },
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