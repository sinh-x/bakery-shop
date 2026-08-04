/// Cash drawer model (DG-324 Phase 2/6; updated by DG-347 Phase 5).
///
/// Mirrors the JSON returned by the cash-drawer backend API
/// (see `src/baker/api/cash_drawer.py` and `CashDrawer.to_api_dict`):
///
///   {
///     "id": "1",
///     "openedAt": "2026-08-01T00:00:00Z",
///     "closedAt": null,
///     "status": "open",
///     "openingBalance": 1000000,
///     "countedOpeningBalance": 950000,  // DG-354 Phase 4: physical count
///     "countedAmount": null,
///     "discrepancy": null,
///     "expectedBalance": 1000000,
///     "closingBalance": null,           // DG-347: null for open, int when closed
///     "accountingBalance1101": 1000000, // optional, status only
///     "journalEntry": { ... }            // optional, only on mutation responses
///   }
///
/// DG-347 Phase 5: the per-accumulator fields (`cashSales`, `ownerIn`,
/// `ownerOut`, `cashExpenses`, `tienRutIn`, `tienRutOut`) are no longer
/// returned by the backend. The expected balance is now derived on the
/// server from journal entries and is the single source of truth.
///
/// Balance fields are INTEGER (VND) per NFR1. The expected balance is parsed
/// directly from the API `expectedBalance` field (the backend computes it;
/// we do not recompute on the client to avoid drift).
///
/// Plain Dart class (no freezed codegen) — matches the `CakeQueueItem` and
/// `ExpenseCategory` pattern for read-oriented models. `toJson` is provided
/// for symmetry, request-echo tests, and round-trip verification, even though
/// the only client→server payloads are the request bodies in
/// `CashDrawerService` (open/close/cash-in/cash-out).
library;

import '../../shared/utils/date_formatting.dart';
import 'journal_entry.dart';

class CashDrawer {
  /// Backend renders `id` as a string via `str(self.id)`.
  final String id;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String status;
  final int openingBalance;

  /// DG-354 Phase 4 FR7: the user's physical cash count at open time.
  /// The backend returns this separately from `openingBalance` (which
  /// stores the 1101 accounting balance). The Flutter UI displays this
  /// field as the opening balance. Nullable for backward compatibility
  /// with older backends/rows; falls back to [openingBalance] when null
  /// via [displayedOpeningBalance].
  final int? countedOpeningBalance;

  /// DG-354 Phase 4 FR7: the opening balance to display in the UI — the
  /// physical count when available, otherwise the accounting opening
  /// balance. Avoids null-check churn at call sites.
  int get displayedOpeningBalance => countedOpeningBalance ?? openingBalance;

  final int? countedAmount;
  final int? discrepancy;

  /// FR4: expected balance computed by the backend from journal entries
  /// (opening + cashSales + ownerIn - ownerOut - cashExpenses, plus
  /// tien-rut adjustments). Parsed directly from the API `expectedBalance`
  /// field; the client does not recompute it to avoid drift.
  final int expectedBalance;

  /// DG-347 Phase 5 F2: the counted balance recorded when the drawer was
  /// closed. Null for open drawers (not yet counted). Populated by the
  /// backend `to_api_dict` once a close-with-count has been performed.
  final int? closingBalance;

  /// Phase 4.1 F2: the 1101 (Cash in Drawer) journal account balance from
  /// `GET /api/cash-drawer/status`. Surfaced for reconciliation alongside
  /// the computed [expectedBalance]; the two should match while the drawer
  /// is open. Defaults to 0 when the backend omits the field (older
  /// responses, history rows).
  final int accountingBalance1101;

  /// Optional journal entry returned by mutation endpoints (open, cash-in,
  /// cash-out, close-with-discrepancy). Null for the status/history GETs.
  final JournalEntry? journalEntry;

  const CashDrawer({
    required this.id,
    this.openedAt,
    this.closedAt,
    required this.status,
    required this.openingBalance,
    this.countedOpeningBalance,
    this.countedAmount,
    this.discrepancy,
    required this.expectedBalance,
    this.closingBalance,
    this.accountingBalance1101 = 0,
    this.journalEntry,
  });

  /// Whether this drawer is currently open (status == 'open').
  bool get isOpen => status == 'open';

  /// Whether this drawer has been closed (status == 'closed').
  bool get isClosed => status == 'closed';

  /// FR7: shortage/surplus label helper. Positive = surplus, negative =
  /// shortage, zero = exact match.
  int get discrepancyValue => discrepancy ?? 0;

  factory CashDrawer.fromJson(Map<String, dynamic> json) {
    final journalJson = json['journalEntry'];
    return CashDrawer(
      id: json['id'] as String,
      openedAt: parseApiDateTime(json['openedAt'] as String?),
      closedAt: parseApiDateTime(json['closedAt'] as String?),
      status: (json['status'] as String?) ?? 'open',
      openingBalance: (json['openingBalance'] as num?)?.toInt() ?? 0,
      countedOpeningBalance: (json['countedOpeningBalance'] as num?)?.toInt(),
      countedAmount: (json['countedAmount'] as num?)?.toInt(),
      discrepancy: (json['discrepancy'] as num?)?.toInt(),
      expectedBalance: (json['expectedBalance'] as num?)?.toInt() ?? 0,
      closingBalance: (json['closingBalance'] as num?)?.toInt(),
      accountingBalance1101:
          (json['accountingBalance1101'] as num?)?.toInt() ?? 0,
      journalEntry: journalJson is Map<String, dynamic>
          ? JournalEntry.fromJson(journalJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'openedAt': timestampToJson(openedAt),
        'closedAt': timestampToJson(closedAt),
        'status': status,
        'openingBalance': openingBalance,
        'countedOpeningBalance': countedOpeningBalance,
        'countedAmount': countedAmount,
        'discrepancy': discrepancy,
        'expectedBalance': expectedBalance,
        'closingBalance': closingBalance,
        'accountingBalance1101': accountingBalance1101,
        if (journalEntry != null) 'journalEntry': journalEntry!.toJson(),
      };

  @override
  String toString() =>
      'CashDrawer(id: $id, status: $status, expectedBalance: $expectedBalance)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashDrawer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Paginated history envelope returned by `GET /api/cash-drawer/history`.
///
///   { "total": 12, "limit": 50, "offset": 0, "items": [ ...CashDrawer... ] }
class CashDrawerHistoryResponse {
  final int total;
  final int limit;
  final int offset;
  final List<CashDrawer> items;

  const CashDrawerHistoryResponse({
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  factory CashDrawerHistoryResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return CashDrawerHistoryResponse(
      total: (json['total'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
              .map((e) => CashDrawer.fromJson(e as Map<String, dynamic>))
              .toList()
          : const <CashDrawer>[],
    );
  }
}