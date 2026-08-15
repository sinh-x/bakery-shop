import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/order_service.dart';
import '../../data/models/order.dart';
import '../../data/models/paginated_response.dart';
import '../../shared/labels/shared.dart';
import '../../shared/services/session_cache.dart';
import '../../shared/utils/date_formatting.dart';

class OrderListNotifier extends AsyncNotifier<List<Order>> {
  String? _statusFilter;

  @override
  Future<List<Order>> build() async {
    return _fetch();
  }

  Future<List<Order>> _fetch() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrders(status: _statusFilter, activeOnly: true);
  }

  Future<void> filterByStatus(String? status) async {
    _statusFilter = status;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

final orderListProvider = AsyncNotifierProvider<OrderListNotifier, List<Order>>(
  OrderListNotifier.new,
);

class OrderHistoryNotifier extends AsyncNotifier<List<Order>> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  @override
  Future<List<Order>> build() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _toDate = today;
    _fromDate = today.subtract(const Duration(days: 1));
    return _fetch();
  }

  DateTime get fromDate => _fromDate;
  DateTime get toDate => _toDate;

  String? validateRange(DateTime fromDate, DateTime toDate) {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(toDate.year, toDate.month, toDate.day);
    final dayCount = end.difference(start).inDays + 1;
    if (dayCount < 1) return VN.lichSuDonHangKhoangNgayKhongHopLe;
    if (dayCount > 7) return VN.lichSuDonHangToiDa7Ngay;
    return null;
  }

  Future<void> setDateRange(DateTime fromDate, DateTime toDate) async {
    final error = validateRange(fromDate, toDate);
    if (error != null) {
      throw ArgumentError(error);
    }
    _fromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    _toDate = DateTime(toDate.year, toDate.month, toDate.day);
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSingleDate(DateTime date) {
    return setDateRange(date, date);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<List<Order>> _fetch() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrders(
      dueDateFrom: _formatDate(_fromDate),
      dueDateTo: _formatDate(_toDate),
      activeOnly: false,
      limit: 200,
    );
  }

  String _formatDate(DateTime date) => formatApiDate(date);
}

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<Order>>(
      OrderHistoryNotifier.new,
    );

final dashboardOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final service = ref.watch(orderServiceProvider);
  return service.listActiveOrders();
});

// ---------------------------------------------------------------------------
// Paginated order history (DG-409 Phase 4 / FR12)
// ---------------------------------------------------------------------------

/// Page size for the paginated order history screen.
const int orderHistoryPageSize = 50;

/// Pagination-accumulation state for the order history list (FR12). Active
/// orders stay unpaginated (FR9); this notifier is for the history view only.
class OrderHistoryPaginationState {
  const OrderHistoryPaginationState({
    required this.loaded,
    required this.total,
    required this.offset,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  final List<Order> loaded;
  final int total;
  final int offset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => loaded.length < total;

  OrderHistoryPaginationState copyWith({
    List<Order>? loaded,
    int? total,
    int? offset,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return OrderHistoryPaginationState(
      loaded: loaded ?? this.loaded,
      total: total ?? this.total,
      offset: offset ?? this.offset,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Paginated order history notifier (FR12). Fetches the first page on build
/// using the active date range, then accumulates pages via [loadMore]. Active
/// orders are NOT paginated (FR9) — this notifier always uses
/// ``active_only=false``.
///
/// DG-409 Phase 5 (FR13, AC5): `build()` consults the session cache first,
/// keyed by the active date range. On a hit the cached
/// [OrderHistoryPaginationState] is returned without a network request.
/// Pull-to-refresh and order mutations invalidate the cache so the next
/// build re-fetches.
class OrderHistoryPaginationNotifier
    extends AsyncNotifier<OrderHistoryPaginationState> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  SessionCacheKey _cacheKeyFor(DateTime from, DateTime to) =>
      SessionCacheKey(
        SessionCacheEntity.orderHistory,
        parameter: '${formatApiDate(from)}..${formatApiDate(to)}',
      );

  @override
  Future<OrderHistoryPaginationState> build() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _toDate = today;
    _fromDate = today.subtract(const Duration(days: 1));
    final cache = ref.read(sessionCacheProvider);
    return cache.readOrFetch(_cacheKeyFor(_fromDate, _toDate), () => _fetchPage(0));
  }

  DateTime get fromDate => _fromDate;
  DateTime get toDate => _toDate;

  String? validateRange(DateTime fromDate, DateTime toDate) {
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(toDate.year, toDate.month, toDate.day);
    final dayCount = end.difference(start).inDays + 1;
    if (dayCount < 1) return VN.lichSuDonHangKhoangNgayKhongHopLe;
    if (dayCount > 7) return VN.lichSuDonHangToiDa7Ngay;
    return null;
  }

  Future<void> setDateRange(DateTime fromDate, DateTime toDate) async {
    final error = validateRange(fromDate, toDate);
    if (error != null) {
      throw ArgumentError(error);
    }
    _fromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    _toDate = DateTime(toDate.year, toDate.month, toDate.day);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final page = await _fetchPage(0);
      // Populate the cache for the new range so a later tab-away/back
      // reuses this first page (AC5).
      ref.read(sessionCacheProvider).put(_cacheKeyFor(_fromDate, _toDate), page);
      return page;
    });
  }

  Future<void> setSingleDate(DateTime date) {
    return setDateRange(date, date);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      final nextOffset = current.loaded.length;
      final page = await _fetchPageRaw(nextOffset);
      final merged = List<Order>.from(current.loaded)..addAll(page.items);
      final next = OrderHistoryPaginationState(
        loaded: merged,
        total: page.total,
        offset: nextOffset,
        isLoadingMore: false,
      );
      // Keep the cache in sync with the accumulated state so a later
      // cache hit returns the full loaded set, not just page 1 (AC5).
      ref
          .read(sessionCacheProvider)
          .put(_cacheKeyFor(_fromDate, _toDate), next);
      state = AsyncData(next);
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }

  /// Re-fetch from the first page, bypassing the cache (pull-to-refresh or
  /// mutation invalidation). The cache is invalidated first so the fetch
  /// always hits the network, then re-populated with the fresh result.
  Future<void> refresh() async {
    ref.read(sessionCacheProvider).invalidateEntityType(
      SessionCacheEntity.orderHistory,
    );
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      ref.invalidateSelf();
      return future;
    });
  }

  Future<OrderHistoryPaginationState> _fetchPage(int offset) async {
    final page = await _fetchPageRaw(offset);
    return OrderHistoryPaginationState(
      loaded: page.items,
      total: page.total,
      offset: offset,
      isLoadingMore: false,
    );
  }

  Future<PaginatedResponse<Order>> _fetchPageRaw(int offset) async {
    final service = ref.read(orderServiceProvider);
    return service.listOrdersPaginated(
      dueDateFrom: formatApiDate(_fromDate),
      dueDateTo: formatApiDate(_toDate),
      limit: orderHistoryPageSize,
      offset: offset,
    );
  }
}

final orderHistoryPaginationProvider = AsyncNotifierProvider<
    OrderHistoryPaginationNotifier, OrderHistoryPaginationState>(
  OrderHistoryPaginationNotifier.new,
);