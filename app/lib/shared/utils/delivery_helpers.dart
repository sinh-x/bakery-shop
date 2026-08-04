import 'package:bakery_app/shared/labels/orders.dart';

import '../../data/api/staff_service.dart';
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

/// Finds the date of the next upcoming non-terminal delivery order — the
/// order whose `dueDate` is closest to the current time (past or future)
/// among non-terminal delivery orders (FR2/FR3/AC2/AC3). Returns `null`
/// when there are no qualifying orders, in which case callers should fall
/// back to `DateTime.now()` (AC4).
///
/// Orders without a `dueDate` (or with an unparseable one) are excluded from
/// the "closest" comparison; they do not influence the result. The returned
/// [DateTime] is date-only (time-of-day stripped) since it feeds calendar
/// day/week navigation.
DateTime? findNextDueDate(List<Order> orders) {
  final now = DateTime.now();
  DateTime? best;
  Duration? bestDelta;
  for (final o in orders) {
    if (!isDeliveryType(o.deliveryType)) continue;
    if (!activeOrderStatuses.contains(o.status)) continue;
    final due = parseApiDate(o.dueDate);
    if (due == null) continue;
    final delta = due.difference(now).abs();
    if (bestDelta == null || delta < bestDelta) {
      best = DateTime(due.year, due.month, due.day);
      bestDelta = delta;
    }
  }
  return best;
}

/// Resolves the display name for an assigned staff member (DG-329 Phase 2 /
/// FR3 / AC2).
///
/// Returns `null` when [assignedStaffId] is null/empty (the order is
/// unassigned — callers should render the "Chưa có nhân viên giao hàng"
/// label themselves).
///
/// Resolution order:
/// 1. When [assignedStaffName] is non-empty (the backend already JOINed the
///    real staff name, including deactivated staff whose `staff` row still
///    exists), return it as-is.
/// 2. Otherwise, look up [assignedStaffId] in [staffList]. If found, return
///    that staff member's `name` (covers the rare case the backend returned
///    an empty name but the client-side list still has the record).
/// 3. When the staff record is missing entirely (deleted), return
///    `OrdersLabels.assignStaffMissing(staffId)` ("NV #`<id>`") — NOT the
///    misleading "NV #`<id>` (đã ngưng)" combo, since we cannot know whether
///    a missing record was deactivated or removed.
///
/// Callers that need to distinguish deactivated staff (to append the
/// "(đã ngưng)" suffix in the assignment dropdown) should use
/// [isAssignedStaffInactive] separately.
String? resolveAssignedStaffDisplayName({
  required String? assignedStaffId,
  required String assignedStaffName,
  required List<StaffMember> staffList,
}) {
  if (assignedStaffId == null || assignedStaffId.isEmpty) return null;
  if (assignedStaffName.isNotEmpty) return assignedStaffName;
  final match = staffList
      .where((s) => s.id.toString() == assignedStaffId)
      .toList(growable: false);
  if (match.isNotEmpty) return match.first.name;
  return OrdersLabels.assignStaffMissing(assignedStaffId);
}

/// Whether the assigned staff member exists in [staffList] but is marked
/// inactive (DG-329 Phase 2 / FR3 / AC2). Used by the assignment dropdown to
/// decide whether to append the "(đã ngưng)" suffix. Returns `false` when
/// the staff record is missing entirely (the dropdown then shows the
/// "NV #`<id>`" fallback from [resolveAssignedStaffDisplayName]).
bool isAssignedStaffInactive({
  required String? assignedStaffId,
  required List<StaffMember> staffList,
}) {
  if (assignedStaffId == null || assignedStaffId.isEmpty) return false;
  return staffList.any(
    (s) => s.id.toString() == assignedStaffId && !s.active,
  );
}

/// `assignedStaffId` matches (FR3). When [staffId] is null or empty, all
/// orders are returned unchanged (the "All" option — FR4/NFR1).
///
/// This is a pure client-side predicate over already-loaded orders: it makes
/// no additional API call (NFR1). It does not re-apply the delivery-type or
/// status filters — callers should pass the output of [filterDeliveryOrders]
/// (or another already-filtered list) so the staff filter composes cleanly
/// after the existing today/status filters.
List<Order> filterDeliveryOrdersByStaff(List<Order> orders, {String? staffId}) {
  if (staffId == null || staffId.isEmpty) return List<Order>.from(orders);
  return orders
      .where((o) => o.assignedStaffId == staffId)
      .toList();
}

/// A single staff member's workload count for today's non-terminal delivery
/// orders (FR6). Used by [computeWorkloadSummary] to build the per-staff list.
class WorkloadEntry {
  final StaffMember staff;
  final int count;

  WorkloadEntry({required this.staff, required this.count});
}

/// Computes a per-staff count of today's non-terminal delivery orders for the
/// given active staff list (FR6/NFR3). [orders] should already be filtered to
/// today's non-terminal delivery orders (the output of
/// `filterDeliveryOrders(orders, todayOnly: true)`), so this function does a
/// single O(n) pass over [orders] and an O(m) build of the per-staff counter
/// (where m = number of active staff) — overall O(n + m) (NFR3).
///
/// [deliveryStaff] is expected to be ALL active staff (any role), not just
/// `giao-hang`-role staff (DG-329 Phase 5 / FR6). Orders whose
/// `assignedStaffId` is null/empty/unknown are counted under the "unassigned"
/// bucket (returned via [unassignedCount]); only staff present in
/// [deliveryStaff] appear as [WorkloadEntry] results. The returned list is
/// ordered to match [deliveryStaff] input order (typically the dropdown order).
({List<WorkloadEntry> entries, int unassignedCount}) computeWorkloadSummary(
  List<Order> orders,
  List<StaffMember> deliveryStaff,
) {
  final counts = <String, int>{
    for (final s in deliveryStaff) s.id.toString(): 0,
  };
  var unassigned = 0;
  for (final o in orders) {
    final id = o.assignedStaffId;
    if (id == null || id.isEmpty || !counts.containsKey(id)) {
      unassigned++;
      continue;
    }
    counts[id] = counts[id]! + 1;
  }
  final entries = <WorkloadEntry>[];
  for (final s in deliveryStaff) {
    entries.add(WorkloadEntry(staff: s, count: counts[s.id.toString()]!));
  }
  return (entries: entries, unassignedCount: unassigned);
}
