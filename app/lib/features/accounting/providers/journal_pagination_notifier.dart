import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/accounting_service.dart';
import '../../../data/models/journal_entry.dart';
import '../../../providers/accounting_provider.dart';

/// Pagination-accumulation state for a journal filter view (DG-189 Phase 5.6-c1, CQ-1).
///
/// Owns the accumulated list of loaded journal entries, the running total reported
/// by the API, the current offset, and a per-filter loading flag. Accumulation is
/// performed inside the Notifier's state so the widget's `build` method is free of
/// side effects — re-emissions from the underlying `journalEntriesProvider` replace
/// the page slice in state instead of appending duplicates.
class JournalPaginationState {
  const JournalPaginationState({
    required this.loaded,
    required this.total,
    required this.offset,
    required this.isLoadingMore,
  });

  /// Entries accumulated across all loaded pages for the current filter.
  final List<JournalEntry> loaded;

  /// Total entries reported by the API for the filter (server-side count).
  final int total;

  /// Offset of the currently fetched page slice (0 for the first page).
  final int offset;

  /// Whether a "load more" request is in flight for the next page.
  final bool isLoadingMore;

  bool get hasMore => loaded.length < total;

  JournalPaginationState copyWith({
    List<JournalEntry>? loaded,
    int? total,
    int? offset,
    bool? isLoadingMore,
  }) {
    return JournalPaginationState(
      loaded: loaded ?? this.loaded,
      total: total ?? this.total,
      offset: offset ?? this.offset,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Riverpod async notifier that owns journal pagination accumulation.
///
/// The widget reads [journalPaginationProvider] keyed by the active filter.
/// When the user requests the next page, the widget calls [loadMore]; the
/// notifier fetches the next slice from the API and merges it into `loaded`
/// exactly once. Because accumulation lives in the notifier state, the
/// widget's `build` method is pure — no `setState`-driven side effects and
/// no risk of duplicate appends from provider re-emissions.
class JournalPaginationNotifier
    extends AsyncNotifier<JournalPaginationState> {
  final JournalFilter filter;

  JournalPaginationNotifier(this.filter);

  @override
  Future<JournalPaginationState> build() async {
    final service = ref.read(accountingServiceProvider);
    final response = await service.listJournal(
      since: filter.since,
      until: filter.until,
      accountId: filter.accountId,
      sourceType: filter.sourceType,
      sourceId: filter.sourceId,
      limit: filter.limit,
      offset: filter.offset,
    );
    return JournalPaginationState(
      loaded: response.items,
      total: response.total,
      offset: filter.offset,
      isLoadingMore: false,
    );
  }

  /// Fetch the next page and append it to `loaded`. No-op if already loading
  /// or no more pages remain.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final service = ref.read(accountingServiceProvider);
      final nextOffset = current.loaded.length;
      final response = await service.listJournal(
        since: filter.since,
        until: filter.until,
        accountId: filter.accountId,
        sourceType: filter.sourceType,
        sourceId: filter.sourceId,
        limit: filter.limit,
        offset: nextOffset,
      );
      final merged = List<JournalEntry>.from(current.loaded)
        ..addAll(response.items);
      state = AsyncData(
        JournalPaginationState(
          loaded: merged,
          total: response.total,
          offset: nextOffset,
          isLoadingMore: false,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError<JournalPaginationState>(error, stackTrace);
    }
  }
}

/// Family provider for journal pagination state keyed by the active filter.
final journalPaginationProvider =
    AsyncNotifierProvider.family<JournalPaginationNotifier,
        JournalPaginationState, JournalFilter>(
  JournalPaginationNotifier.new,
);