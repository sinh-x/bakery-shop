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

/// DG-330: thrown when opening balance < 1101 reference balance and the
/// owner must confirm transferring the difference to 1102 (Owner's Cash).
class TransferProposalException implements Exception {
  TransferProposalException({
    required this.message,
    required this.referenceBalance,
    required this.openingBalance,
    required this.excess,
  });

  final String message;
  final int referenceBalance;
  final int openingBalance;
  final int excess;
}

/// DG-330: thrown when opening balance > 1101 reference balance and the
/// owner must confirm stock reconciliation before proceeding.
class ExcessProposalException implements Exception {
  ExcessProposalException({
    required this.message,
    required this.referenceBalance,
    required this.openingBalance,
    required this.excess,
  });

  final String message;
  final int referenceBalance;
  final int openingBalance;
  final int excess;
}

/// DG-330: thrown after stock reconciliation confirmed, asking whether the
/// excess should be recorded as an unidentified sale (50% COGS markup).
class UnidentifiedSaleProposalException implements Exception {
  UnidentifiedSaleProposalException({
    required this.message,
    required this.referenceBalance,
    required this.openingBalance,
    required this.excess,
  });

  final String message;
  final int referenceBalance;
  final int openingBalance;
  final int excess;
}

/// DG-331: thrown when closing the drawer with a surplus (counted > expected)
/// and `surplusConfirmed` is false. The backend responds with HTTP 409
/// carrying a `surplusProposal` so the owner can choose the nature of the
/// surplus before re-sending the close request.
class CloseSurplusProposalException implements Exception {
  CloseSurplusProposalException({
    required this.message,
    required this.expectedBalance,
    required this.countedAmount,
    required this.surplus,
  });

  final String message;
  final int expectedBalance;
  final int countedAmount;
  final int surplus;

  @override
  String toString() =>
      'CloseSurplusProposalException(expectedBalance: $expectedBalance, '
      'countedAmount: $countedAmount, surplus: $surplus)';
}

/// DG-331: thrown when closing the drawer with a shortage (counted <
/// expected) and `shortageConfirmed` is false. The backend responds with
/// HTTP 409 carrying a `shortageProposal` so the owner can choose the nature
/// of the shortage before re-sending the close request.
class CloseShortageProposalException implements Exception {
  CloseShortageProposalException({
    required this.message,
    required this.expectedBalance,
    required this.countedAmount,
    required this.shortage,
  });

  final String message;
  final int expectedBalance;
  final int countedAmount;
  final int shortage;

  @override
  String toString() =>
      'CloseShortageProposalException(expectedBalance: $expectedBalance, '
      'countedAmount: $countedAmount, shortage: $shortage)';
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
    bool transferConfirmed = false,
    bool stockReconciliationConfirmed = false,
    bool unidentifiedSaleConfirmed = false,
    bool ownerCapitalConfirmed = false,
  }) async {
    try {
      final response = await _dio.post(
        '/api/cash-drawer/open',
        data: {
          'openingBalance': openingBalance,
          'note': note,
          'carryOverConfirmed': carryOverConfirmed,
          'transferConfirmed': transferConfirmed,
          'stockReconciliationConfirmed': stockReconciliationConfirmed,
          'unidentifiedSaleConfirmed': unidentifiedSaleConfirmed,
          'ownerCapitalConfirmed': ownerCapitalConfirmed,
        },
      );
      return CashDrawer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final proposal = _decodeOpenProposal(e);
      if (proposal != null) throw proposal;
      rethrow;
    }
  }

  /// Decodes a 409 `detail` body into a proposal exception (carry-over,
  /// transfer, excess, or unidentified-sale), or returns `null` when the
  /// error is not a known proposal type.
  Object? _decodeOpenProposal(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final body = e.response?.data;
    // FastAPI wraps HTTPException detail in {"detail": {...}}
    final detail = body is Map ? body['detail'] : null;
    if (detail is! Map<String, dynamic>) return null;

    if (detail.containsKey('carryOverProposal')) {
      final p = detail['carryOverProposal'] as Map<String, dynamic>;
      return CarryOverProposalException(
        message: detail['message'] as String? ?? '',
        amount: (p['amount'] as num).toInt(),
        fromDrawerId: p['fromDrawerId'] as String? ?? '',
        fromOpenedAt: p['fromOpenedAt'] as String? ?? '',
        fromExpectedBalance: (p['fromExpectedBalance'] as num).toInt(),
      );
    }
    if (detail.containsKey('transferProposal')) {
      final p = detail['transferProposal'] as Map<String, dynamic>;
      return TransferProposalException(
        message: detail['message'] as String? ?? '',
        referenceBalance: (p['referenceBalance'] as num).toInt(),
        openingBalance: (p['openingBalance'] as num).toInt(),
        excess: (p['excess'] as num).toInt(),
      );
    }
    if (detail.containsKey('excessProposal')) {
      final p = detail['excessProposal'] as Map<String, dynamic>;
      return ExcessProposalException(
        message: detail['message'] as String? ?? '',
        referenceBalance: (p['referenceBalance'] as num).toInt(),
        openingBalance: (p['openingBalance'] as num).toInt(),
        excess: (p['excess'] as num).toInt(),
      );
    }
    if (detail.containsKey('unidentifiedSaleProposal')) {
      final p = detail['unidentifiedSaleProposal'] as Map<String, dynamic>;
      return UnidentifiedSaleProposalException(
        message: detail['message'] as String? ?? '',
        referenceBalance: (p['referenceBalance'] as num).toInt(),
        openingBalance: (p['openingBalance'] as num).toInt(),
        excess: (p['excess'] as num).toInt(),
      );
    }
    return null;
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
  ///
  /// DG-331: when the counted amount diverges from the expected balance
  /// (surplus or shortage) and the matching confirmation flag is false, the
  /// backend responds with HTTP 409 carrying a `surplusProposal` or
  /// `shortageProposal`. This method decodes that 409 and throws a
  /// [CloseSurplusProposalException] or [CloseShortageProposalException]
  /// instead of a generic [DioException], so the caller can surface the
  /// proposal to the owner and re-call `closeDrawer` with the appropriate
  /// confirmation flag + source. Backward compatible: omitting the new
  /// params reproduces the legacy behavior (no flags → backend may still
  /// raise 409 for discrepancy when source is None).
  Future<CashDrawer> closeDrawer({
    required int countedAmount,
    String note = '',
    bool surplusConfirmed = false,
    String? surplusSource,
    bool shortageConfirmed = false,
    String? shortageSource,
  }) async {
    try {
      final response = await _dio.post(
        '/api/cash-drawer/close',
        data: {
          'countedAmount': countedAmount,
          'note': note,
          if (surplusConfirmed) 'surplusConfirmed': true,
          if (surplusSource != null && surplusSource.isNotEmpty)
            'surplusSource': surplusSource,
          if (shortageConfirmed) 'shortageConfirmed': true,
          if (shortageSource != null && shortageSource.isNotEmpty)
            'shortageSource': shortageSource,
        },
      );
      return CashDrawer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final proposal = _decodeCloseProposal(e);
      if (proposal != null) throw proposal;
      rethrow;
    }
  }

  /// Decodes a 409 `detail` body into a close proposal exception (surplus or
  /// shortage), or returns `null` when the error is not a known close
  /// proposal type (so the caller can `rethrow` the original [DioException]).
  Object? _decodeCloseProposal(DioException e) {
    if (e.response?.statusCode != 409) return null;
    final body = e.response?.data;
    final detail = body is Map ? body['detail'] : null;
    if (detail is! Map<String, dynamic>) return null;

    if (detail.containsKey('surplusProposal')) {
      final p = detail['surplusProposal'] as Map<String, dynamic>;
      return CloseSurplusProposalException(
        message: detail['message'] as String? ?? '',
        expectedBalance: (p['expectedBalance'] as num).toInt(),
        countedAmount: (p['countedAmount'] as num).toInt(),
        surplus: (p['surplus'] as num).toInt(),
      );
    }
    if (detail.containsKey('shortageProposal')) {
      final p = detail['shortageProposal'] as Map<String, dynamic>;
      return CloseShortageProposalException(
        message: detail['message'] as String? ?? '',
        expectedBalance: (p['expectedBalance'] as num).toInt(),
        countedAmount: (p['countedAmount'] as num).toInt(),
        shortage: (p['shortage'] as num).toInt(),
      );
    }
    return null;
  }

  /// FR4: return the active (open) drawer with its expected balance, or
  /// `null` when no drawer is currently open.
  Future<CashDrawer?> getDrawerStatus() async {
    final response = await _dio.get('/api/cash-drawer/status');
    final data = response.data;
    if (data == null) return null;
    if (data is! Map<String, dynamic>) return null;
    // DG-331 FR9: when no active drawer exists but a previously closed
    // drawer is present, the backend returns an envelope shaped as
    // `{activeDrawer: null, previousCloseCountedAmount: <int>}`. There is
    // no active drawer to surface here; the reference amount is exposed
    // via [getPreviousCloseCountedAmount] for the open dialog.
    if (data.containsKey('activeDrawer')) return null;
    return CashDrawer.fromJson(data);
  }

  /// DG-331 FR9: returns the `previousCloseCountedAmount` (counted_amount of
  /// the most recent closed drawer) when no active drawer exists but a
  /// previously closed drawer is present. Returns `null` when an active
  /// drawer is open (the reference is only for the open dialog) or when no
  /// drawer history exists. Used by the open dialog to display "Số dư sau
  /// khi đóng quỹ lần trước".
  Future<int?> getPreviousCloseCountedAmount() async {
    final response = await _dio.get('/api/cash-drawer/status');
    final data = response.data;
    if (data is! Map<String, dynamic>) return null;
    // Only present in the no-active-drawer envelope.
    if (!data.containsKey('activeDrawer')) return null;
    final amount = data['previousCloseCountedAmount'];
    return amount is num ? amount.toInt() : null;
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