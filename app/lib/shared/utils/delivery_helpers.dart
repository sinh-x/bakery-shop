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

/// Auto-derives a 1-hour delivery time slot from an order's `dueTime` hour
/// (FR1/AC4). Given `dueTime: "14:30"` the slot is `"14:00"`; given `"07:15"`
/// the slot is `"7:00"` (matching [OrdersLabels.deliveryTimeSlots] label
/// format, which omits the leading zero for single-digit hours). Returns
/// `null` when [dueTime] is null/empty/malformed.
///
/// The frontend derives the slot from `dueTime` and ignores the stored
/// `deliveryTimeSlot` DB column (the column is still persisted for backward
/// compatibility — see FR1 notes).
String? deriveTimeSlot(String? dueTime) {
  if (dueTime == null || dueTime.isEmpty) return null;
  final parts = dueTime.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  if (hour == null) return null;
  return '$hour:00';
}

/// Groups delivery orders by 1-hour time slot auto-derived from each order's
/// `dueTime` hour (FR1/FR3/FR5). Returns an ordered map keyed by slot label
/// ("6:00" … "21:00"). Orders whose `dueTime` is null/empty or whose derived
/// slot falls outside the predefined range land under
/// [OrdersLabels.deliveryCalendarNoSlot] ("Chưa có giờ") at the end. Within
/// each slot, orders sort by dueDate ascending then dueTime ascending
/// (mirroring [groupDeliveryOrdersByStatus]).
Map<String, List<Order>> groupDeliveryOrdersByTimeSlot(List<Order> orders) {
  final slots = <String, List<Order>>{
    for (final slot in OrdersLabels.deliveryTimeSlots) slot: <Order>[],
  };
  final noSlot = <Order>[];

  for (final o in orders) {
    final slot = deriveTimeSlot(o.dueTime);
    if (slot == null || !slots.containsKey(slot)) {
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

/// The week-grid layout key: a day column ("yyyy-MM-dd") plus the auto-derived
/// time-slot label ("6:00" … "21:00") or the unscheduled marker
/// [OrdersLabels.deliveryCalendarNoSlot] ("Chưa có giờ") when an order has no
/// `dueTime` (or its hour falls outside the 6:00–21:00 range).
typedef DaySlotKey = ({String day, String slot});

/// Groups delivery orders into week-grid cells keyed by day (`dueDate`,
/// `yyyy-MM-dd`) + auto-derived time slot (`dueTime` hour). Orders without a
/// `dueDate` are dropped — the calendar only renders dated orders (they remain
/// visible in the list view, which has no date constraint). Within each cell,
/// orders sort by `dueTime` ascending then by `orderRef` for stability.
///
/// The unscheduled marker [OrdersLabels.deliveryCalendarNoSlot] is used as the
/// `slot` for orders whose `dueTime` is null/empty/out-of-range, so each day
/// column can render a sticky "Chưa có giờ" row at the top (FR4/AC1).
Map<DaySlotKey, List<Order>> groupDeliveryOrdersByDayAndSlot(
  List<Order> orders,
) {
  final result = <DaySlotKey, List<Order>>{};

  int compareOrders(Order a, Order b) {
    final c = (a.dueTime ?? '').compareTo(b.dueTime ?? '');
    if (c != 0) return c;
    return a.orderRef.compareTo(b.orderRef);
  }

  for (final o in orders) {
    if (o.dueDate == null || o.dueDate!.isEmpty) continue;
    final slot = deriveTimeSlot(o.dueTime);
    final key = (
      day: o.dueDate!,
      slot: (slot != null && OrdersLabels.deliveryTimeSlots.contains(slot))
          ? slot
          : OrdersLabels.deliveryCalendarNoSlot,
    );
    result.putIfAbsent(key, () => <Order>[]).add(o);
  }

  for (final list in result.values) {
    list.sort(compareOrders);
  }
  return result;
}

/// Returns the Monday-anchored [DateTime] of the week containing [date]
/// (time-of-day stripped). Week starts Monday per the calendar grid layout
/// (Mon–Sun columns, FR3).
DateTime startOfWeek(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  // DateTime.weekday: Mon=1..Sun=7 → offset to Monday.
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Returns the 7 day-of-week Dates (Mon..Sun) for the week anchored at
/// [weekStart] (a Monday). Index 0 = Monday … 6 = Sunday.
List<DateTime> daysOfWeek(DateTime weekStart) {
  return List.generate(7, (i) => weekStart.add(Duration(days: i)));
}
