import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/order_service.dart';
import '../../models/order_inventory_audit.dart';

const int orderInventoryAuditPageSize = 100;

class OrderInventoryAuditState {
  const OrderInventoryAuditState({
    this.initialized = false,
    this.items = const [],
    this.total = 0,
    this.hasMore = false,
    this.offset = 0,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.laterRequestFailed = false,
    this.loadMoreFailed = false,
  });

  final bool initialized;
  final List<OrderInventoryAuditEntry> items;
  final int total;
  final bool hasMore;
  final int offset;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool laterRequestFailed;
  final bool loadMoreFailed;

  OrderInventoryAuditState copyWith({
    bool? initialized,
    List<OrderInventoryAuditEntry>? items,
    int? total,
    bool? hasMore,
    int? offset,
    bool? isRefreshing,
    bool? isLoadingMore,
    bool? laterRequestFailed,
    bool? loadMoreFailed,
  }) {
    return OrderInventoryAuditState(
      initialized: initialized ?? this.initialized,
      items: items ?? this.items,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      laterRequestFailed: laterRequestFailed ?? this.laterRequestFailed,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }
}

class OrderInventoryAuditNotifier
    extends AsyncNotifier<OrderInventoryAuditState> {
  OrderInventoryAuditNotifier(this.orderRef);

  final String orderRef;
  bool _requestInFlight = false;

  @override
  Future<OrderInventoryAuditState> build() async {
    return const OrderInventoryAuditState();
  }

  Future<void> loadFirstPage() async {
    if (_requestInFlight || (state.value?.initialized ?? false)) return;
    await _replaceFirstPage(retainCurrent: false);
  }

  Future<void> retry() async {
    if (state.value?.initialized ?? false) {
      await refresh();
    } else {
      await _replaceFirstPage(retainCurrent: false);
    }
  }

  Future<void> refresh() async {
    if (_requestInFlight) return;
    await _replaceFirstPage(retainCurrent: true);
  }

  Future<void> retryRetainedFailure() async {
    if (state.value?.loadMoreFailed ?? false) {
      await loadMore();
    } else {
      await refresh();
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (_requestInFlight ||
        current == null ||
        !current.initialized ||
        !current.hasMore) {
      return;
    }
    _requestInFlight = true;
    state = AsyncData(
      current.copyWith(
        isLoadingMore: true,
        laterRequestFailed: false,
        loadMoreFailed: false,
      ),
    );
    try {
      final page = await _service().getInventoryAudit(
        orderRef,
        limit: orderInventoryAuditPageSize,
        offset: current.items.length,
      );
      state = AsyncData(
        OrderInventoryAuditState(
          initialized: true,
          items: [...current.items, ...page.items],
          total: page.total,
          hasMore: page.hasMore,
          offset: page.offset,
        ),
      );
    } catch (_) {
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          laterRequestFailed: true,
          loadMoreFailed: true,
        ),
      );
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _replaceFirstPage({required bool retainCurrent}) async {
    final current = state.value;
    _requestInFlight = true;
    if (retainCurrent && current != null && current.initialized) {
      state = AsyncData(
        current.copyWith(
          isRefreshing: true,
          laterRequestFailed: false,
          loadMoreFailed: false,
        ),
      );
    } else {
      state = const AsyncLoading();
    }
    try {
      final page = await _service().getInventoryAudit(
        orderRef,
        limit: orderInventoryAuditPageSize,
      );
      state = AsyncData(
        OrderInventoryAuditState(
          initialized: true,
          items: page.items,
          total: page.total,
          hasMore: page.hasMore,
          offset: page.offset,
        ),
      );
    } catch (error, stackTrace) {
      if (retainCurrent && current != null && current.initialized) {
        state = AsyncData(
          current.copyWith(
            isRefreshing: false,
            laterRequestFailed: true,
            loadMoreFailed: false,
          ),
        );
      } else {
        state = AsyncError(error, stackTrace);
      }
    } finally {
      _requestInFlight = false;
    }
  }

  OrderService _service() => ref.read(orderServiceProvider);
}

final orderInventoryAuditProvider =
    AsyncNotifierProvider.family<
      OrderInventoryAuditNotifier,
      OrderInventoryAuditState,
      String
    >(OrderInventoryAuditNotifier.new);
