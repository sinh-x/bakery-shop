import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/cash_drawer_service.dart';
import '../models/cash_drawer.dart';
import '../models/cash_drawer_transaction.dart';

/// Filter parameters for the cash-drawer history query (FR10).
class CashDrawerHistoryFilter {
  const CashDrawerHistoryFilter({
    this.since,
    this.until,
    this.limit = 50,
    this.offset = 0,
  });

  final String? since;
  final String? until;
  final int limit;
  final int offset;

  CashDrawerHistoryFilter copyWith({
    String? since,
    String? until,
    int? limit,
    int? offset,
  }) {
    return CashDrawerHistoryFilter(
      since: since ?? this.since,
      until: until ?? this.until,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashDrawerHistoryFilter &&
          runtimeType == other.runtimeType &&
          since == other.since &&
          until == other.until &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(since, until, limit, offset);
}

/// FR4: the active (open) cash drawer with its real-time expected balance,
/// or `null` when no drawer is currently open. Refreshes on every consumer
/// watch — the underlying [CashDrawerService.getDrawerStatus] call hits
/// `GET /api/cash-drawer/status` (NFR2: < 200ms p95).
final cashDrawerStatusProvider = FutureProvider<CashDrawer?>((ref) async {
  final service = ref.watch(cashDrawerServiceProvider);
  return service.getDrawerStatus();
});

/// DG-331 FR9: the `previousCloseCountedAmount` (counted_amount of the most
/// recent closed drawer) returned by `GET /status` when no active drawer is
/// open. Displayed in the open dialog as "Số dư sau khi đóng quầy lần trước".
/// `null` when an active drawer is open or no drawer history exists.
final cashDrawerPreviousCloseProvider = FutureProvider<int?>((ref) async {
  final service = ref.watch(cashDrawerServiceProvider);
  return service.getPreviousCloseCountedAmount();
});

/// Phase 4.1 F3: the 1101 (Cash in Drawer) journal account balance from
/// `GET /api/cash-drawer/status`, returned regardless of whether a drawer is
/// currently open. Displayed in the open dialog upfront (before any 409
/// proposal) as "Số dư kế toán 1101" for reconciliation reference. Falls
/// back to 0 when the backend omits the field.
final cashDrawerAccountingBalance1101Provider = FutureProvider<int>((ref) async {
  final service = ref.watch(cashDrawerServiceProvider);
  return service.getAccountingBalance1101();
});

/// FR10: paginated cash-drawer history, filterable by date range. Uses
/// `FutureProvider.family` so distinct filter arguments cache independently,
/// matching the [journalEntriesProvider] pattern in `accounting_provider.dart`.
final cashDrawerHistoryProvider =
    FutureProvider.family<CashDrawerHistoryResponse, CashDrawerHistoryFilter>((
  ref,
  filter,
) async {
  final service = ref.watch(cashDrawerServiceProvider);
  return service.getDrawerHistory(
    since: filter.since,
    until: filter.until,
    limit: filter.limit,
    offset: filter.offset,
  );
});

/// Filter parameters for the cash-drawer transactions query (DG-343 Phase 2,
/// FR1/FR2). Keyed on `drawerId` so distinct drawers cache independently,
/// mirroring the [cashDrawerHistoryProvider] family pattern.
class CashDrawerTransactionsFilter {
  const CashDrawerTransactionsFilter({
    required this.drawerId,
    this.limit = 50,
    this.offset = 0,
  });

  final int drawerId;
  final int limit;
  final int offset;

  CashDrawerTransactionsFilter copyWith({
    int? drawerId,
    int? limit,
    int? offset,
  }) {
    return CashDrawerTransactionsFilter(
      drawerId: drawerId ?? this.drawerId,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashDrawerTransactionsFilter &&
          runtimeType == other.runtimeType &&
          drawerId == other.drawerId &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode => Object.hash(drawerId, limit, offset);
}

/// DG-343 Phase 2 (FR1/FR2, AC1/AC2/AC4): paginated cash-drawer transaction
/// list, keyed on [CashDrawerTransactionsFilter]. Uses
/// `FutureProvider.family` so distinct (drawerId, limit, offset) pages cache
/// independently, matching the [cashDrawerHistoryProvider] pattern. The UI
/// (Phase 3) polls this provider for the active drawer on a 30s Timer to
/// satisfy AC4, and loads further pages by reading the family with growing
/// `offset` for infinite-scroll (AC2).
final cashDrawerTransactionsProvider = FutureProvider.family<
    CashDrawerTransactionResponse, CashDrawerTransactionsFilter>((ref, filter) async {
  final service = ref.watch(cashDrawerServiceProvider);
  return service.getDrawerTransactions(
    filter.drawerId,
    limit: filter.limit,
    offset: filter.offset,
  );
});