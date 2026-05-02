import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../data/api/order_service.dart';
import '../data/api/payment_transaction_service.dart';
import '../data/api/work_item_service.dart';
import '../data/models/enum_attribute.dart';
import '../data/models/order.dart';
import '../data/models/order_photo.dart';
import '../data/models/payment_transaction.dart';
import '../data/models/product.dart';
import '../data/models/work_item.dart';
import 'events_provider.dart';

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
    // Skip AsyncLoading to avoid destroying the form/scroll on edit screen.
    // The initial load is handled by build(); refresh just updates data silently.
    state = await AsyncValue.guard(() async {
      final service = ref.read(orderServiceProvider);
      return service.getOrder(orderRef);
    });
  }

  Future<Order> transitionTo(String targetStatus, {String reason = ''}) async {
    final service = ref.read(orderServiceProvider);
    final changedBy = ref.read(loggedByProvider);
    final updated =
        await service.updateStatus(orderRef, targetStatus, reason: reason, changedBy: changedBy);
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
    String? source,
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

  Future<OrderPhoto> upload(XFile file, {String tags = '', int? workItemId}) async {
    final service = ref.read(orderServiceProvider);
    final photo = await service.uploadOrderPhoto(orderRef, file, tags: tags, workItemId: workItemId);
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
    );
    final current = state.value ?? [];
    state = AsyncData([...current, item]);
    // Refresh order detail to update total/summary
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
    // Refresh order detail so Sản phẩm section and total_price reflect the change.
    await ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
  }


  Future<void> remove(String itemId) async {
    final service = ref.read(workItemServiceProvider);
    await service.deleteWorkItem(orderRef, itemId);
    final current = state.value ?? [];
    state = AsyncData(current.where((i) => i.id != itemId).toList());
    // Refresh order detail to update total/summary
    await ref.read(orderDetailProvider(orderRef).notifier).refresh();
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
    state = AsyncData(
      current.map((t) => t.id == txnId ? updated : t).toList(),
    );
    // Refresh order detail to update amountPaid.
    ref.read(orderDetailProvider(orderRef).notifier).refresh();
    return updated;
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

// ── Order creation draft ──────────────────────────────────────────────────────

/// A selected product in the order creation form.
class DraftOrderItem {
  final Product product;
  int quantity;
  String notes;
  bool isBirthday;
  String age;
  List<XFile> pendingPhotos;
  double? customUnitPrice;
  bool isExtra;
  bool isGift;
  Map<String, dynamic> attributes;
  bool daDuaTienRut;

  DraftOrderItem({
    required this.product,
    this.quantity = 1,
    this.notes = '',
    this.isBirthday = false,
    this.age = '',
    List<XFile>? pendingPhotos,
    this.customUnitPrice,
    this.isExtra = false,
    this.isGift = false,
    Map<String, dynamic>? attributes,
    this.daDuaTienRut = false,
  }) : pendingPhotos = pendingPhotos ?? [],
       attributes = _populateEnumDefaults(product, attributes);

  static Map<String, dynamic> _populateEnumDefaults(
    Product product,
    Map<String, dynamic>? provided,
  ) {
    final attrs = <String, dynamic>{...?provided};
    for (final ea in product.enumAttributes) {
      if (ea.options.isEmpty) continue;
      // caller wins
      if (attrs.containsKey(ea.attributeType)) continue;
      EnumOption? defaultOpt;
      for (final o in ea.options) {
        if (o.isDefault) {
          defaultOpt = o;
          break;
        }
      }
      if (defaultOpt == null && ea.defaultOptionId != null) {
        for (final o in ea.options) {
          if (o.id == ea.defaultOptionId) {
            defaultOpt = o;
            break;
          }
        }
      }
      if (defaultOpt == null) {
        for (final o in ea.options) {
          if (o.active == 1) {
            defaultOpt = o;
            break;
          }
        }
      }
      defaultOpt ??= ea.options.first;
      attrs[ea.attributeType] = defaultOpt.valueVi;
    }
    return attrs;
  }

  double get unitPrice => customUnitPrice ?? product.basePrice;
}

/// Creates a DraftOrderItem for an extra item (not from product catalog).
/// Uses a placeholder product with id=0 and the extra name as product name.
DraftOrderItem createExtraItem(String extraName, double extraPrice, {bool isGift = false}) {
  final fakeProduct = Product(
    id: 0,
    name: extraName,
    category: 'extra',
    basePrice: extraPrice,
  );
  return DraftOrderItem(
    product: fakeProduct,
    quantity: 1,
    isExtra: true,
    isGift: isGift,
    customUnitPrice: extraPrice,
  );
}

/// A pending photo in the order creation form.
class DraftPendingPhoto {
  final XFile file;
  Set<String> tags;
  DraftPendingPhoto({required this.file, Set<String>? tags})
      : tags = tags ?? {};
}

/// In-memory draft for the order creation form.
class OrderDraft {
  final String customerName;
  final String customerPhone;
  final List<DraftOrderItem> items;
  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final String deliveryType;
  final String deliveryAddress;
  final String notes;
  final bool depositEnabled;
  final String depositAmount;
  final String depositMethod;
  final List<DraftPendingPhoto> pendingPhotos;
  final String source;

  OrderDraft({
    this.customerName = '',
    this.customerPhone = '',
    List<DraftOrderItem>? items,
    this.dueDate,
    this.dueTime,
    this.deliveryType = 'pickup',
    this.deliveryAddress = '',
    this.notes = '',
    this.depositEnabled = false,
    this.depositAmount = '',
    this.depositMethod = 'cash',
    List<DraftPendingPhoto>? pendingPhotos,
    this.source = '',
  })  : items = items ?? [],
        pendingPhotos = pendingPhotos ?? [];

  bool get isNotEmpty =>
      customerName.isNotEmpty ||
      customerPhone.isNotEmpty ||
      items.isNotEmpty ||
      dueDate != null ||
      dueTime != null ||
      deliveryType != 'pickup' ||
      deliveryAddress.isNotEmpty ||
      notes.isNotEmpty ||
      depositEnabled ||
      depositAmount.isNotEmpty ||
      pendingPhotos.isNotEmpty ||
      source.isNotEmpty;
}

class OrderDraftNotifier extends Notifier<OrderDraft?> {
  @override
  OrderDraft? build() => null;

  void save(OrderDraft draft) => state = draft;
  void clear() => state = null;
}

final orderDraftProvider =
    NotifierProvider<OrderDraftNotifier, OrderDraft?>(
  OrderDraftNotifier.new,
);
