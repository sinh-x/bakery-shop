import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/order_service.dart';
import '../../models/order.dart';
import '../../../shared/services/session_cache.dart';
import '../../../shared/providers/logged_by_provider.dart';
import 'order_list_providers.dart';

class OrderDetailNotifier extends AsyncNotifier<Order> {
  final String orderRef;

  OrderDetailNotifier(this.orderRef);

  /// DG-409 Phase 5 (FR13, AC6): invalidate the session-level order-history
  /// cache after any order mutation so the next history-tab visit re-fetches
  /// fresh data instead of serving stale cached pages.
  void _invalidateOrderHistoryCache() {
    ref.read(sessionCacheProvider).invalidateEntityType(
      SessionCacheEntity.orderHistory,
    );
  }

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
    _invalidateOrderHistoryCache();
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
    // DG-304 Phase 5: admin staff assignment (FR8/FR9/AC5). Sent explicitly
    // (incl. null to unassign) only when the admin touched the dropdown.
    String? assignedStaffId,
    bool assignedStaffTouched = false,
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
      assignedStaffId: assignedStaffId,
      assignedStaffTouched: assignedStaffTouched,
    );
    state = AsyncData(updated);
    ref.read(orderListProvider.notifier).refresh();
    _invalidateOrderHistoryCache();
    return updated;
  }

  /// DG-304 Phase 5: admin sets or clears the delivery staff assignment on
  /// any order (FR9/AC5). PATCHes only `assignedStaffId` (incl. null to
  /// unassign — FR6) so no other order field is clobbered; the change is
  /// logged in `order_history` via the backend `field_map` (FR7).
  Future<Order> saveAssignedStaff(String? assignedStaffId) async {
    final service = ref.read(orderServiceProvider);
    final changedBy = ref.read(loggedByProvider);
    final updated = await service.setAssignedStaff(
      orderRef,
      assignedStaffId: assignedStaffId,
      changedBy: changedBy,
    );
    state = AsyncData(updated);
    ref.read(orderListProvider.notifier).refresh();
    _invalidateOrderHistoryCache();
    return updated;
  }
}

final orderDetailProvider =
    AsyncNotifierProvider.family<OrderDetailNotifier, Order, String>(
      OrderDetailNotifier.new,
    );