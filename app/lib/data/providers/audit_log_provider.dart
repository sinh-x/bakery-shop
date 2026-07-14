import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/audit_log_service.dart';

/// View state for the audit log screen.
///
/// Holds the current [filters], the current [page] (1-based), the accumulated
/// [items] across all loaded pages (for incremental "load more"), the page
/// metadata ([pageSize], [total]) from the most recent fetch, and a flag
/// indicating whether more pages are available.
class AuditLogState {
  const AuditLogState({
    this.filters = const AuditLogFilters(),
    this.items = const [],
    this.page = 1,
    this.pageSize = 50,
    this.total = 0,
    this.hasMore = false,
  });

  final AuditLogFilters filters;
  final List<AuditLogEntry> items;
  final int page;
  final int pageSize;
  final int total;
  final bool hasMore;

  int get totalPages => pageSize <= 0 ? 0 : (total + pageSize - 1) ~/ pageSize;

  AuditLogState copyWith({
    AuditLogFilters? filters,
    List<AuditLogEntry>? items,
    int? page,
    int? pageSize,
    int? total,
    bool? hasMore,
  }) =>
      AuditLogState(
        filters: filters ?? this.filters,
        items: items ?? this.items,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
      );
}

/// AsyncNotifier for the audit log screen (FR24/AC20).
///
/// - `build()`: fetches the first page with the default (empty) filters.
/// - `applyFilters()`: replaces the active filters and reloads from page 1.
/// - `loadMore()`: fetches the next page and appends to the item list.
/// - `refresh()`: re-runs the current query from page 1.
///
/// The notifier stores the latest [AuditLogState] in `state.value` and uses
/// `state = AsyncLoading()` (preserving the previous data via the `previous`
/// slot where helpful) so the screen can show loading spinners without losing
/// the already-loaded list.
class AuditLogNotifier extends AsyncNotifier<AuditLogState> {
  AuditLogService _service() => ref.read(auditLogServiceProvider);

  @override
  Future<AuditLogState> build() async {
    return _fetchPage(page: 1, filters: const AuditLogFilters());
  }

  /// Replaces the active filters and reloads from page 1 (FR24).
  Future<void> applyFilters(AuditLogFilters filters) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 1, filters: filters),
    );
  }

  /// Clears all filters and reloads from page 1.
  Future<void> clearFilters() => applyFilters(const AuditLogFilters());

  /// Re-runs the current query from page 1.
  Future<void> refresh() async {
    final current = state.value ?? const AuditLogState();
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetchPage(page: 1, filters: current.filters),
    );
  }

  /// Loads the next page and appends the entries to the item list (NFR9 —
  /// page rather than fetch-all).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore) return;
    try {
      final next = await _fetchPageRaw(
        page: current.page + 1,
        filters: current.filters,
      );
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.items],
          page: next.page,
          hasMore: next.page < next.totalPages,
        ),
      );
    } catch (error) {
      debugPrint('audit_log_notifier: loadMore failed: $error');
      state = AsyncError(error, StackTrace.current);
    }
  }

  Future<AuditLogState> _fetchPage({
    required int page,
    required AuditLogFilters filters,
  }) async {
    try {
      return await _fetchPageRaw(page: page, filters: filters);
    } catch (error) {
      debugPrint('audit_log_notifier: fetchPage failed: $error');
      rethrow;
    }
  }

  Future<AuditLogState> _fetchPageRaw({
    required int page,
    required AuditLogFilters filters,
  }) async {
    final result = await _service().list(
      filters: filters,
      page: page,
      pageSize: 50,
    );
    return AuditLogState(
      filters: filters,
      items: result.items,
      page: result.page,
      pageSize: result.pageSize,
      total: result.total,
      hasMore: result.page < result.totalPages,
    );
  }
}

final auditLogProvider =
    AsyncNotifierProvider<AuditLogNotifier, AuditLogState>(AuditLogNotifier.new);