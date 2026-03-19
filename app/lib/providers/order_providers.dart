import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/order_service.dart';
import '../data/models/order.dart';

class OrderListNotifier extends AsyncNotifier<List<Order>> {
  String? _statusFilter;

  @override
  Future<List<Order>> build() async {
    return _fetch();
  }

  Future<List<Order>> _fetch() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrders(status: _statusFilter);
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

final orderListProvider =
    AsyncNotifierProvider<OrderListNotifier, List<Order>>(
  OrderListNotifier.new,
);

// Family provider for a single order detail, keyed by orderRef.
class OrderDetailNotifier extends AsyncNotifier<Order> {
  final String orderRef;

  OrderDetailNotifier(this.orderRef);

  @override
  Future<Order> build() async {
    final service = ref.read(orderServiceProvider);
    return service.getOrder(orderRef);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(orderServiceProvider);
      return service.getOrder(orderRef);
    });
  }

  Future<Order> transitionTo(String targetStatus, {String reason = ''}) async {
    final service = ref.read(orderServiceProvider);
    final updated =
        await service.updateStatus(orderRef, targetStatus, reason: reason);
    state = AsyncData(updated);
    // Refresh the list so the status change is reflected there too.
    ref.read(orderListProvider.notifier).refresh();
    return updated;
  }

  Future<Order> save({
    String? notes,
    String? dueDate,
    String? dueTime,
    String? customerPhone,
    String? deliveryAddress,
    String? deliveryType,
  }) async {
    final service = ref.read(orderServiceProvider);
    final updated = await service.editOrder(
      orderRef,
      notes: notes,
      dueDate: dueDate,
      dueTime: dueTime,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
      deliveryType: deliveryType,
    );
    state = AsyncData(updated);
    ref.read(orderListProvider.notifier).refresh();
    return updated;
  }
}

final orderDetailProvider =
    AsyncNotifierProvider.family<OrderDetailNotifier, Order, String>(
  (ref) => OrderDetailNotifier(ref),
);

/// Provides all active (non-terminal) orders for the dashboard view.
final dashboardOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final service = ref.watch(orderServiceProvider);
  return service.listActiveOrders();
});
