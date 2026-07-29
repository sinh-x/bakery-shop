import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/order_service.dart';
import '../../data/models/order.dart';
import '../events_provider.dart';
import 'order_list_providers.dart';

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
    String? deliveryPhone,
    String? deliveryAddress,
    String? deliveryType,
    String? source,
    String? publicCodeDateChangeDecision,
    String? customerName,
    int? customerId,
    bool customerTouched = false,
    double? shippingFee,
    double? latitude,
    double? longitude,
    String? googleMapsUrl,
    String? deliveryTimeSlot,
  }) async {
    final service = ref.read(orderServiceProvider);
    final changedBy = ref.read(loggedByProvider);
    final updated = await service.editOrder(
      orderRef,
      notes: notes,
      dueDate: dueDate,
      dueTime: dueTime,
      customerPhone: customerPhone,
      deliveryPhone: deliveryPhone,
      deliveryAddress: deliveryAddress,
      deliveryType: deliveryType,
      source: source,
      publicCodeDateChangeDecision: publicCodeDateChangeDecision,
      customerName: customerName,
      customerId: customerId,
      customerTouched: customerTouched,
      changedBy: changedBy,
      shippingFee: shippingFee,
      latitude: latitude,
      longitude: longitude,
      googleMapsUrl: googleMapsUrl,
      deliveryTimeSlot: deliveryTimeSlot,
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