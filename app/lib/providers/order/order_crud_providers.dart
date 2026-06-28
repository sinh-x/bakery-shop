import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/api/order_service.dart';
import '../../data/api/payment_transaction_service.dart';
import '../../data/api/work_item_service.dart';
import '../../data/models/order.dart';
import '../../data/models/order_photo.dart';
import '../../data/models/payment_transaction.dart';
import '../../data/models/work_item.dart';
import '../../shared/labels/shared.dart';
import '../events_provider.dart';

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

  String _formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
}

final orderHistoryProvider =
    AsyncNotifierProvider<OrderHistoryNotifier, List<Order>>(
      OrderHistoryNotifier.new,
    );

class OrderDetailNotifier extends AsyncNotifier<Order> {
  final String orderRef;

  OrderDetailNotifier(this.orderRef);

  @override
  Future<Order> build() async {
    final service = ref.read(orderServiceProvider);
    return service.getOrder(orderRef);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      final service = ref.read(orderServiceProvider);
      return service.getOrder(orderRef);
    });
  }

  Future<Order> transitionTo(String targetStatus, {String reason = ''}) async {
    final service = ref.read(orderServiceProvider);
    final changedBy = ref.read(loggedByProvider);
    final updated = await service.updateStatus(
      orderRef,
      targetStatus,
      reason: reason,
      changedBy: changedBy,
    );
    state = AsyncData(updated);
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
    String? source,
    String? publicCodeDateChangeDecision,
    String? customerName,
    double? shippingFee,
  }) async {
    final service = ref.read(orderServiceProvider);
    final changedBy = ref.read(loggedByProvider);
    final updated = await service.editOrder(
      orderRef,
      notes: notes,
      dueDate: dueDate,
      dueTime: dueTime,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
      deliveryType: deliveryType,
      source: source,
      publicCodeDateChangeDecision: publicCodeDateChangeDecision,
      customerName: customerName,
      changedBy: changedBy,
      shippingFee: shippingFee,
    );
    state = AsyncData(updated);
    ref.read(orderListProvider.notifier).refresh();
    return updated;
  }
}

final orderDetailProvider =
    AsyncNotifierProvider.family<OrderDetailNotifier, Order, String>(
      OrderDetailNotifier.new,
    );

final dashboardOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final service = ref.watch(orderServiceProvider);
  return service.listActiveOrders();
});

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

  Future<OrderPhoto> upload(
    XFile file, {
    String tags = '',
    int? workItemId,
  }) async {
    final service = ref.read(orderServiceProvider);
    final photo = await service.uploadOrderPhoto(
      orderRef,
      file,
      tags: tags,
      workItemId: workItemId,
    );
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
      OrderPhotosNotifier.new,
    );

class OrderWorkItemsNotifier extends AsyncNotifier<List<WorkItem>> {
  final String orderRef;

  OrderWorkItemsNotifier(this.orderRef);

  @override
  Future<List<WorkItem>> build() async {
    final service = ref.read(workItemServiceProvider);
    return service.listWorkItems(orderRef);
  }

  Future<void> refresh() async {
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
    bool isExtra = false,
    bool isGift = false,
    Map<String, dynamic>? attributes,
    int? priceChipId,
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
      isExtra: isExtra,
      isGift: isGift,
      attributes: attributes,
      priceChipId: priceChipId,
    );
    final current = state.value ?? [];
    state = AsyncData([...current, item]);
    await ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return item;
  }

  Future<WorkItem> edit(
    String itemId, {
    String? productName,
    int? quantity,
    double? unitPrice,
    String? notes,
    int? position,
    bool? isBirthday,
    int? age,
    bool? isExtra,
    bool? isGift,
    Map<String, dynamic>? attributes,
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
      isBirthday: isBirthday,
      age: age,
      isExtra: isExtra,
      isGift: isGift,
      attributes: attributes,
    );
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? updated : i).toList(),
    );
    await ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }

  Future<void> remove(String itemId) async {
    final service = ref.read(workItemServiceProvider);
    await service.deleteWorkItem(orderRef, itemId);
    final current = state.value ?? [];
    state = AsyncData(current.where((i) => i.id != itemId).toList());
    await ref.read(orderDetailProvider(orderRef).notifier).refresh();
  }

  Future<WorkItem> transitionStatus(
    String itemId,
    String status, {
    String reason = '',
  }) async {
    final service = ref.read(workItemServiceProvider);
    final updated = await service.transitionStatus(
      orderRef,
      itemId,
      status,
      reason: reason,
    );
    final current = state.value ?? [];
    state = AsyncData(
      current.map((i) => i.id == itemId ? updated : i).toList(),
    );
    return updated;
  }
}

final orderWorkItemsProvider =
    AsyncNotifierProvider.family<
      OrderWorkItemsNotifier,
      List<WorkItem>,
      String
    >(OrderWorkItemsNotifier.new);

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
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return txn;
  }

  Future<PaymentTransaction> edit(
    String txnId, {
    required double amount,
    required String type,
    required String method,
    required String notes,
  }) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final updated = await service.updateTransaction(
      orderRef,
      txnId,
      amount: amount,
      type: type,
      method: method,
      notes: notes,
    );
    final current = state.value ?? [];
    state = AsyncData(current.map((t) => t.id == txnId ? updated : t).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }

  Future<void> remove(String txnId) async {
    final service = ref.read(paymentTransactionServiceProvider);
    await service.deleteTransaction(orderRef, txnId);
    final current = state.value ?? [];
    state = AsyncData(current.where((t) => t.id != txnId).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
  }

  Future<PaymentTransaction> invalidate(
    String txnId, {
    String reason = '',
  }) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final invalidatedBy = ref.read(loggedByProvider);
    final updated = await service.invalidateTransaction(
      orderRef,
      txnId,
      invalidatedBy: invalidatedBy,
      reason: reason,
    );
    final current = state.value ?? [];
    state = AsyncData(current.map((t) => t.id == txnId ? updated : t).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }

  Future<PaymentTransaction> restore(String txnId) async {
    final service = ref.read(paymentTransactionServiceProvider);
    final updated = await service.restoreTransaction(orderRef, txnId);
    final current = state.value ?? [];
    state = AsyncData(current.map((t) => t.id == txnId ? updated : t).toList());
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }
}

final orderPaymentTransactionsProvider =
    AsyncNotifierProvider.family<
      OrderPaymentTransactionsNotifier,
      List<PaymentTransaction>,
      String
    >(OrderPaymentTransactionsNotifier.new);
