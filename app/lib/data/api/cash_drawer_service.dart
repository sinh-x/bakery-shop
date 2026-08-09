import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cash_drawer.dart';
import '../models/cash_drawer_transaction.dart';
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

/// DG-331: thrown when closing the drawer with a surplus (counted > expected)
/// and `surplusConfirmed` is false. The backend responds with HTTP 409
/// carrying a `surplusProposal` so the owner can choose the nature of the
/// surplus before re-sending the close request.
///
/// DG-360: this class is dual-use. It is also thrown by
/// [CashDrawerService.openDrawer] when the opening balance diverges from the
/// 1101 reference balance (the open flow reuses the close surplus proposal
/// shape). Despite the `Close*` prefix, it covers both the close flow
/// (`expectedBalance`/`countedAmount`) and the open flow
/// (`referenceBalance`/`openingBalance` mapped onto the same fields), so the
/// caller can reuse `showCloseSurplusDialog` for both flows.
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
///
/// DG-360: this class is dual-use. It is also thrown by
/// [CashDrawerService.openDrawer] when the opening balance diverges from the
/// 1101 reference balance (the open flow reuses the close shortage proposal
/// shape). Despite the `Close*` prefix, it covers both the close flow
/// (`expectedBalance`/`countedAmount`) and the open flow
/// (`referenceBalance`/`openingBalance` mapped onto the same fields), so the
/// caller can reuse `showCloseShortageDialog` for both flows.
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
  ///
  /// DG-360 Phase 2 FR7: when `openingBalance` diverges from the 1101
  /// reference balance, the backend responds with HTTP 409 carrying a
  /// `surplusProposal` or `shortageProposal` (same shape as the close
  /// drawer flow, except the inner fields are `referenceBalance`/
  /// `openingBalance` instead of `expectedBalance`/`countedAmount`). This
  /// method decodes that 409 and throws a [CloseSurplusProposalException] or
  /// [CloseShortageProposalException] so the caller can reuse the existing
  /// `showCloseSurplusDialog`/`showCloseShortageDialog` and re-call
  /// `openDrawer` with the matching `surplusConfirmed`/`surplusSource` or
  /// `shortageConfirmed`/`shortageSource` flags.
  Future<CashDrawer> openDrawer({
    required int openingBalance,
    String note = '',
    bool carryOverConfirmed = false,
    bool surplusConfirmed = false,
    String? surplusSource,
    bool shortageConfirmed = false,
    String? shortageSource,
  }) async {
    try {
      final response = await _dio.post(
        '/api/cash-drawer/open',
        data: {
          'openingBalance': openingBalance,
          'note': note,
          'carryOverConfirmed': carryOverConfirmed,
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
      final proposal = _decodeOpenProposal(e);
      if (proposal != null) throw proposal;
      rethrow;
    }
  }

  /// Decodes a 409 `detail` body into a proposal exception (carry-over,
  /// surplus, or shortage), or returns `null` when the error is not a known
  /// proposal type.
  ///
  /// DG-360 Phase 2: `surplusProposal`/`shortageProposal` reuse the close
  /// drawer exception types so the caller can re-use the same confirmation
  /// dialogs. The open proposal's `referenceBalance`/`openingBalance` fields
  /// map onto the close exception's `expectedBalance`/`countedAmount` fields
  /// so the dialog labels stay consistent (the dialog prints "Số dư dự kiến"
  /// and "Số tiền đếm được" — for an open flow these correspond to the 1101
  /// reference and the entered opening amount respectively).
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
    if (detail.containsKey('surplusProposal')) {
      final p = detail['surplusProposal'] as Map<String, dynamic>;
      return CloseSurplusProposalException(
        message: detail['message'] as String? ?? '',
        expectedBalance: (p['referenceBalance'] as num).toInt(),
        countedAmount: (p['openingBalance'] as num).toInt(),
        surplus: (p['surplus'] as num).toInt(),
      );
    }
    if (detail.containsKey('shortageProposal')) {
      final p = detail['shortageProposal'] as Map<String, dynamic>;
      return CloseShortageProposalException(
        message: detail['message'] as String? ?? '',
        expectedBalance: (p['referenceBalance'] as num).toInt(),
        countedAmount: (p['openingBalance'] as num).toInt(),
        shortage: (p['shortage'] as num).toInt(),
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
  /// khi đóng quầy lần trước".
  Future<int?> getPreviousCloseCountedAmount() async {
    final response = await _dio.get('/api/cash-drawer/status');
    final data = response.data;
    if (data is! Map<String, dynamic>) return null;
    // Only present in the no-active-drawer envelope.
    if (!data.containsKey('activeDrawer')) return null;
    final amount = data['previousCloseCountedAmount'];
    return amount is num ? amount.toInt() : null;
  }

  /// Phase 4.1 F1/F3: returns the 1101 (Cash in Drawer) journal account
  /// balance from `GET /api/cash-drawer/status`, regardless of whether a
  /// drawer is currently open. Surfaced in the open dialog (upfront, before
  /// any 409 proposal) and the close dialog for reconciliation. Returns 0
  /// when the backend omits the field or no drawer state exists.
  Future<int> getAccountingBalance1101() async {
    final response = await _dio.get('/api/cash-drawer/status');
    final data = response.data;
    if (data is! Map<String, dynamic>) return 0;
    final amount = data['accountingBalance1101'];
    return amount is num ? amount.toInt() : 0;
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

  /// DG-343 Phase 2 (FR1/FR2): paginated list of cash transactions for a
  /// given drawer, ordered newest-first. Calls
  /// `GET /api/cash-drawer/{drawer_id}/transactions` with `limit`/`offset`
  /// query params. The backend joins journal entries linked to the drawer
  /// via `cash_drawer_journal_entries` and aggregates their 1101 (Cash in
  /// Drawer) lines into one signed row per entry.
  ///
  /// Each item carries `type` (journal `source_type`), `amount` (signed int,
  /// +inflow/-outflow), `timestamp` (transaction_date fallback to
  /// created_at), and `note` (journal description). Non-cash operations
  /// (bank transfers, card payments) are excluded by the backend.
  ///
  /// Use [cashDrawerTransactionsProvider] for Riverpod caching; call this
  /// directly only for one-off fetches or tests.
  Future<CashDrawerTransactionResponse> getDrawerTransactions(
    int drawerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/api/cash-drawer/$drawerId/transactions',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return CashDrawerTransactionResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// DG-379 Phase 4.2/4.3 (FR1-FR3): edit an open/close transaction's amount
  /// and/or notes in-place. Calls
  /// `PATCH /api/cash-drawer/{drawer_id}/transactions/{entry_id}` with a JSON
  /// body containing the optional `amount` (VND, > 0) and `notes`. The backend
  /// updates `journal_entries.description` and `journal_lines.debit`/`credit`
  /// in a single DB transaction, recalculates drawer balances for close
  /// edits, and returns a dict describing the updated entry + drawer.
  ///
  /// Both [amount] and [notes] are optional — pass `null` to leave a field
  /// unchanged. At least one must be non-null (the backend rejects an empty
  /// body with 400). Throws [DioException] on 404 (drawer/entry missing),
  /// 409 (drawer reconciled or close-edit-while-open), 400 (invalid type or
  /// amount).
  Future<CashDrawerEditResult> editTransaction(
    int drawerId,
    int entryId, {
    int? amount,
    String? notes,
  }) async {
    final response = await _dio.patch(
      '/api/cash-drawer/$drawerId/transactions/$entryId',
      data: {
        if (amount != null) 'amount': amount,
        if (notes != null) 'notes': notes,
      },
    );
    return CashDrawerEditResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// DG-379 Phase 4.2/4.3 (FR8, AC6): mark a drawer as reconciled. Calls
  /// `PATCH /api/cash-drawer/{drawer_id}/reconcile` (no body). Sets
  /// `cash_drawer.reconciled = 1` so further transaction edits are rejected
  /// with 409. Idempotent — re-reconciling an already-reconciled drawer
  /// returns 200 with `reconciled: true`. Throws [DioException] on 404
  /// (drawer missing).
  Future<bool> reconcileDrawer(int drawerId) async {
    final response = await _dio.patch('/api/cash-drawer/$drawerId/reconcile');
    final data = response.data;
    if (data is! Map<String, dynamic>) return false;
    return (data['reconciled'] as bool?) ?? false;
  }
}

/// DG-379 Phase 4.3: result of [CashDrawerService.editTransaction]. Mirrors
/// the backend `CashDrawer.edit_transaction` response dict:
///
///   {
///     "drawerId": "1",
///     "entryId": "12",
///     "sourceType": "cash_drawer_open",
///     "amount": 1500000,          // null when amount was not edited
///     "notes": "Mở quầy sáng",      // the updated (or unchanged) description
///     "drawer": { ...CashDrawer... } // full recalculated drawer
///   }
///
/// The [drawer] field carries the recalculated expected/closing balance and
/// the up-to-date `reconciled` flag so the caller can refresh the status
/// card and transaction list without a second round-trip.
class CashDrawerEditResult {
  const CashDrawerEditResult({
    required this.drawerId,
    required this.entryId,
    required this.sourceType,
    required this.amount,
    required this.notes,
    required this.drawer,
  });

  final String drawerId;
  final String entryId;
  final String sourceType;
  final int? amount;
  final String notes;
  final CashDrawer drawer;

  factory CashDrawerEditResult.fromJson(Map<String, dynamic> json) {
    return CashDrawerEditResult(
      drawerId: (json['drawerId'] as String?) ?? '',
      entryId: (json['entryId'] as String?) ?? '',
      sourceType: (json['sourceType'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toInt(),
      notes: (json['notes'] as String?) ?? '',
      drawer: CashDrawer.fromJson((json['drawer'] as Map<String, dynamic>?) ?? const {}),
    );
  }
}

final cashDrawerServiceProvider = Provider<CashDrawerService>((ref) {
  final dio = ref.watch(dioProvider);
  return CashDrawerService(dio);
});