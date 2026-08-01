import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/cash_drawer_service.dart';
import '../data/models/cash_drawer.dart';

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
/// open. Displayed in the open dialog as "Số dư sau khi đóng quỹ lần trước".
/// `null` when an active drawer is open or no drawer history exists.
final cashDrawerPreviousCloseProvider = FutureProvider<int?>((ref) async {
  final service = ref.watch(cashDrawerServiceProvider);
  return service.getPreviousCloseCountedAmount();
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