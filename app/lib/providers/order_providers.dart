import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/order_service.dart';
import '../data/api/payment_transaction_service.dart';
import '../data/api/work_item_service.dart';
import '../data/models/order.dart';
import '../data/models/order_photo.dart';
import '../data/models/payment_transaction.dart';
import '../data/models/work_item.dart';

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

// Family provider for the photo list of a single order, keyed by orderRef.
class OrderPhotosNotifier extends AsyncNotifier<List<OrderPhoto>> {
  final String orderRef;

  OrderPhotosNotifier(this.orderRef);

  @override
  Future<List<OrderPhoto>> build() async {
    final service = ref.read(orderServiceProvider);
    return service.listOrderPhotos(orderRef);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(orderServiceProvider);
      return service.listOrderPhotos(orderRef);
    });
  }

  Future<OrderPhoto> upload(File file, {String tags = ''}) async {
    final service = ref.read(orderServiceProvider);
    final photo = await service.uploadOrderPhoto(orderRef, file, tags: tags);
    // Append to list optimistically.
    final current = state.value ?? [];
    state = AsyncData([...current, photo]);
    return photo;
  }

  Future<OrderPhoto> updateTags(int photoId, String tags) async {
    final service = ref.read(orderServiceProvider);
    final updated = await service.updatePhotoTags(orderRef, photoId, tags);
    final current = state.value ?? [];
    state = AsyncData(
      current.map((p) => p.id == photoId ? updated : p).toList(),
    );
    return updated;
  }

  Future<void> delete(int photoId) async {
    final service = ref.read(orderServiceProvider);
    await service.deleteOrderPhoto(orderRef, photoId);
    final current = state.value ?? [];
    state = AsyncData(current.where((p) => p.id != photoId).toList());
  }
}

final orderPhotosProvider =
    AsyncNotifierProvider.family<OrderPhotosNotifier, List<OrderPhoto>, String>(
  (ref) => OrderPhotosNotifier(ref),
);

// Family provider for the work items of a single order, keyed by orderRef.
class OrderWorkItemsNotifier extends AsyncNotifier<List<WorkItem>> {
  final String orderRef;

  OrderWorkItemsNotifier(this.orderRef);

  @override
  Future<List<WorkItem>> build() async {
    final service = ref.read(workItemServiceProvider);
    return service.listWorkItems(orderRef);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(workItemServiceProvider);
      return service.listWorkItems(orderRef);
    });
  }

  Future<WorkItem> add({
    required String productName,
    String productId = '',
    int quantity = 1,
    double unitPrice = 0.0,
    String notes = '',
    int position = 0,
  }) async {
    final service = ref.read(workItemServiceProvider);
    final item = await service.createWorkItem(
      orderRef,
      productName: productName,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
      position: position,
    );
    final current = state.value ?? [];
    state = AsyncData([...current, item]);
    return item;
  }

  Future<WorkItem> edit(
    String itemId, {
    String? productName,
    int? quantity,
    double? unitPrice,
    String? notes,
    int? position,
  }) async {
    final service = ref.read(workItemServiceProvider);
    final updated = await service.updateWorkItem(
      orderRef,
      itemId,
      productName: productName,
      quantity: quantity,
      unitPrice: unitPrice,
      notes: notes,
      position: position,
    );
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? updated : i).toList(),
    );
    return updated;
  }


  Future<void> remove(String itemId) async {
    final service = ref.read(workItemServiceProvider);
    await service.deleteWorkItem(orderRef, itemId);
    final current = state.value ?? [];
    state = AsyncData(current.where((i) => i.id != itemId).toList());
  }

  Future<WorkItem> transitionStatus(
    String itemId,
    String status, {
    String reason = '',
  }) async {
    final service = ref.read(workItemServiceProvider);
    final updated =
        await service.transitionStatus(orderRef, itemId, status, reason: reason);
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? updated : i).toList(),
    );
    return updated;
  }
}

final orderWorkItemsProvider = AsyncNotifierProvider.family<
    OrderWorkItemsNotifier, List<WorkItem>, String>(
  (ref) => OrderWorkItemsNotifier(ref),
);

// Family provider for the payment transactions of a single order, keyed by orderRef.
class OrderPaymentTransactionsNotifier
    extends AsyncNotifier<List<PaymentTransaction>> {
  final String orderRef;

  OrderPaymentTransactionsNotifier(this.orderRef);

  @override
  Future<List<PaymentTransaction>> build() async {
    final service = ref.read(paymentTransactionServiceProvider);
    return service.listTransactions(orderRef);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(paymentTransactionServiceProvider);
      return service.listTransactions(orderRef);
    });
  }

  Future<PaymentTransaction> record({
    required double amount,
    String type = 'deposit',
    String method = 'cash',
    String notes = '',
  }) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final txn = await service.createTransaction(
      orderRef,
      amount: amount,
      type: type,
      method: method,
      notes: notes,
    );
    final current = state.value ?? [];
    state = AsyncData([...current, txn]);
    // Refresh order detail to update amountPaid.
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return txn;
  }

  Future<void> remove(String txnId) async {
    final service = ref.read(paymentTransactionServiceProvider);
    await service.deleteTransaction(orderRef, txnId);
    final current = state.value ?? [];
    state = AsyncData(current.where((t) => t.id != txnId).toList());
    // Refresh order detail to update amountPaid.
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
  }
}

final orderPaymentTransactionsProvider = AsyncNotifierProvider.family<
    OrderPaymentTransactionsNotifier, List<PaymentTransaction>, String>(
  (ref) => OrderPaymentTransactionsNotifier(ref),
);
