import 'package:bakery_app/shared/labels/orders.dart';

import '../../data/models/order.dart';
import 'date_formatting.dart';
import 'order_helpers.dart';

/// Filters delivery-type orders with non-terminal statuses.
/// [todayOnly]: when true, includes only orders with dueDate ≤ today
/// or null/empty dueDate; when false, includes all regardless of dueDate.
List<Order> filterDeliveryOrders(List<Order> orders, {required bool todayOnly}) {
  return orders.where((o) {
    if (!isDeliveryType(o.deliveryType)) return false;
    if (!activeOrderStatuses.contains(o.status)) return false;
    if (todayOnly) {
      if (o.dueDate == null || o.dueDate!.isEmpty) return true;
      final due = parseApiDate(o.dueDate);
      if (due == null) return true;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return !due.isAfter(today);
    }
    return true;
  }).toList();
}

/// Groups delivery orders by status in workflow order:
/// new → confirmed → in_progress → ready → delivered.
/// Within each group, orders without a due date appear first,
/// then by dueDate ascending, then by dueTime ascending.
Map<String, List<Order>> groupDeliveryOrdersByStatus(List<Order> orders) {
  const workflowOrder = ['new', 'confirmed', 'in_progress', 'ready', 'delivered'];
  final result = <String, List<Order>>{};
  for (final status in workflowOrder) {
    final statusOrders = orders.where((o) => o.status == status).toList();
    statusOrders.sort((a, b) {
      final aHasDate = a.dueDate != null && a.dueDate!.isNotEmpty;
      final bHasDate = b.dueDate != null && b.dueDate!.isNotEmpty;
      if (!aHasDate && bHasDate) return -1;
      if (aHasDate && !bHasDate) return 1;
      if (!aHasDate && !bHasDate) return 0;
      final dateCmp = a.dueDate!.compareTo(b.dueDate!);
      if (dateCmp != 0) return dateCmp;
      final aTime = a.dueTime ?? '';
      final bTime = b.dueTime ?? '';
      return aTime.compareTo(bTime);
    });
    result[status] = statusOrders;
  }
  return result;
}

/// Groups delivery orders by 1-hour `deliveryTimeSlot` value (FR3/FR5).
///
/// Returns an ordered map keyed by slot label ("7:00" … "20:00"). Orders whose
/// `deliveryTimeSlot` is null/empty or outside the predefined slots land under
/// [OrdersLabels.deliveryCalendarNoSlot] ("Chưa có giờ") at the end.
/// Within each slot, orders sort by dueDate ascending then dueTime ascending
/// (mirroring [groupDeliveryOrdersByStatus]).
Map<String, List<Order>> groupDeliveryOrdersByTimeSlot(List<Order> orders) {
  final slots = <String, List<Order>>{
    for (final slot in OrdersLabels.deliveryTimeSlots) slot: <Order>[],
  };
  final noSlot = <Order>[];

  for (final o in orders) {
    final slot = o.deliveryTimeSlot;
    if (slot == null || slot.isEmpty || !slots.containsKey(slot)) {
      noSlot.add(o);
      continue;
    }
    slots[slot]!.add(o);
  }

  int compareOrders(Order a, Order b) {
    final aHas = a.dueDate != null && a.dueDate!.isNotEmpty;
    final bHas = b.dueDate != null && b.dueDate!.isNotEmpty;
    if (!aHas && bHas) return -1;
    if (aHas && !bHas) return 1;
    if (!aHas && !bHas) return 0;
    final c = a.dueDate!.compareTo(b.dueDate!);
    if (c != 0) return c;
    return (a.dueTime ?? '').compareTo(b.dueTime ?? '');
  }

  final result = <String, List<Order>>{};
  for (final slot in OrdersLabels.deliveryTimeSlots) {
    final list = slots[slot]!;
    if (list.isEmpty) continue;
    list.sort(compareOrders);
    result[slot] = list;
  }
  if (noSlot.isNotEmpty) {
    noSlot.sort(compareOrders);
    result[OrdersLabels.deliveryCalendarNoSlot] = noSlot;
  }
  return result;
}
