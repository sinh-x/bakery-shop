import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/customer_service.dart';
import '../data/models/customer.dart';
import '../shared/services/session_cache.dart';

/// Current search query for the customer list. Empty string = no filter.
/// Setting this re-triggers [CustomerListNotifier] via `ref.watch`.
class CustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

final customerSearchProvider = NotifierProvider<CustomerSearchNotifier, String>(
  CustomerSearchNotifier.new,
);

/// Live-searched customer list. Re-fetches whenever the search query changes
/// (FR1). Empty query returns the unfiltered list.
class CustomerListNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    final search = ref.watch(customerSearchProvider);
    final service = ref.read(customerServiceProvider);
    return service.listCustomers(search: search);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final search = ref.read(customerSearchProvider);
      final service = ref.read(customerServiceProvider);
      return service.listCustomers(search: search);
    });
  }
}

final customerListProvider =
    AsyncNotifierProvider<CustomerListNotifier, List<Customer>>(
      CustomerListNotifier.new,
    );

/// Current search query for the admin duplicate-finder screen
/// (DG-372 Phase 4.2 — FR1/FR5). Empty string = no filter; the screen
/// filters the already-fetched `List<DuplicateGroup>` client-side, so
/// changing this does NOT re-fetch from the backend.
class DuplicateFinderSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;

  void clear() => state = '';
}

final duplicateFinderSearchProvider =
    NotifierProvider<DuplicateFinderSearchNotifier, String>(
      DuplicateFinderSearchNotifier.new,
    );

/// Fetches a single customer by id (FR3).
final customerProvider = FutureProvider.family<Customer, int>((ref, id) async {
  final service = ref.read(customerServiceProvider);
  return service.getCustomer(id);
});

/// Fetches a customer's order history as raw JSON maps (FR6). Screens decode
/// these via `Order.fromJson` so the Order model stays the single source of
/// truth for order shape.
final customerOrdersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, id) async {
      final service = ref.read(customerServiceProvider);
      return service.getCustomerOrders(id);
    });

/// Admin duplicate-finder group list (DG-252 Phase 7 — FR7/AC4).
///
/// AsyncNotifier wrapping `GET /api/customers/duplicates`. Screens call
/// `refresh()` after a successful merge so the merged group disappears and
/// any newly-revealed duplicates reload.
class DuplicateGroupsNotifier extends AsyncNotifier<List<DuplicateGroup>> {
  @override
  Future<List<DuplicateGroup>> build() async {
    final service = ref.read(customerServiceProvider);
    final result = await service.listDuplicates();
    return result.groups;
  }

  /// Re-fetches the duplicate groups from the backend (after a merge, manual
  /// refresh, etc.).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(customerServiceProvider);
      final result = await service.listDuplicates();
      return result.groups;
    });
  }
}

final duplicateGroupsProvider =
    AsyncNotifierProvider<DuplicateGroupsNotifier, List<DuplicateGroup>>(
      DuplicateGroupsNotifier.new,
    );

// ---------------------------------------------------------------------------
// Paginated customer list (DG-409 Phase 4 / FR11, AC4)
// ---------------------------------------------------------------------------

/// Page size for the paginated customer list screen.
const int customerPageSize = 50;

/// Pagination-accumulation state for the customer list (FR11, AC4). Server-
/// side search runs across ALL customers; only the result page is sliced, so
/// `total` reflects the full search-result count (not just the loaded page).
class CustomerPaginationState {
  const CustomerPaginationState({
    required this.loaded,
    required this.total,
    required this.offset,
    required this.isLoadingMore,
    this.loadMoreError,
  });

  final List<Customer> loaded;
  final int total;
  final int offset;
  final bool isLoadingMore;
  final Object? loadMoreError;

  bool get hasMore => loaded.length < total;

  CustomerPaginationState copyWith({
    List<Customer>? loaded,
    int? total,
    int? offset,
    bool? isLoadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return CustomerPaginationState(
      loaded: loaded ?? this.loaded,
      total: total ?? this.total,
      offset: offset ?? this.offset,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Paginated customer list notifier (FR11, AC4). Watches
/// [customerSearchProvider] so a new server-side search resets to the first
/// page of the new result set. Modeled on [JournalPaginationNotifier].
///
/// DG-409 Phase 5 (FR13, AC5): `build()` consults the session cache first,
/// keyed by the current search query. On a hit the cached
/// [CustomerPaginationState] is returned without a network request. Pull-to-
/// refresh and customer mutations invalidate the cache so the next build
/// re-fetches.
class CustomerPaginationNotifier
    extends AsyncNotifier<CustomerPaginationState> {
  SessionCacheKey _cacheKeyFor(String search) =>
      SessionCacheKey(SessionCacheEntity.customers, parameter: search);

  @override
  Future<CustomerPaginationState> build() async {
    final search = ref.watch(customerSearchProvider);
    final cache = ref.read(sessionCacheProvider);
    return cache.readOrFetch(
      _cacheKeyFor(search),
      () => _fetchFirstPage(search),
    );
  }

  Future<CustomerPaginationState> _fetchFirstPage(String search) async {
    final service = ref.read(customerServiceProvider);
    final response = await service.listCustomersPaginated(
      search: search,
      limit: customerPageSize,
      offset: 0,
    );
    return CustomerPaginationState(
      loaded: response.items,
      total: response.total,
      offset: response.offset,
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
      final search = ref.read(customerSearchProvider);
      final service = ref.read(customerServiceProvider);
      final nextOffset = current.loaded.length;
      final response = await service.listCustomersPaginated(
        search: search,
        limit: customerPageSize,
        offset: nextOffset,
      );
      final merged = List<Customer>.from(current.loaded)
        ..addAll(response.items);
      final next = CustomerPaginationState(
        loaded: merged,
        total: response.total,
        offset: nextOffset,
        isLoadingMore: false,
      );
      // Keep the cache in sync with the accumulated state so a later
      // cache hit returns the full loaded set, not just page 1 (AC5).
      ref.read(sessionCacheProvider).put(_cacheKeyFor(search), next);
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
    ref
        .read(sessionCacheProvider)
        .invalidateEntityType(SessionCacheEntity.customers);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      ref.invalidateSelf();
      return future;
    });
  }
}

final customerPaginationProvider =
    AsyncNotifierProvider<CustomerPaginationNotifier, CustomerPaginationState>(
      CustomerPaginationNotifier.new,
    );
