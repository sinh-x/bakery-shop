import '../../data/models/cake_queue_item.dart';
import '../../features/orders/widgets/date_filter_chips.dart';
import 'date_formatting.dart';

/// Filters a [CakeQueueItem] list by [DateFilterOption] using each item's
/// `dueDate`.
///
/// Semantics (matches the "Làm bánh" view — items still to be made):
/// - [DateFilterOption.today]: items whose `dueDate` is today **or earlier**
///   (overdue items still need making), plus items with null/empty `dueDate`
///   (no due date = should appear in today's queue).
/// - [DateFilterOption.tomorrow]: items whose `dueDate` is exactly tomorrow.
/// - [DateFilterOption.todayTomorrow]: union of today and tomorrow (items
///   with null/empty `dueDate` are included via the "today" branch).
/// - [DateFilterOption.all]: no filter — every item is returned unchanged.
///
/// Dates are parsed with [parseApiDate] (handles `yyyy-MM-dd` and full
/// ISO-8601 strings). Unparseable `dueDate` values are treated like
/// null/empty (included only under the "today" branch).
List<CakeQueueItem> filterCakeQueueByDate(
  List<CakeQueueItem> items,
  DateFilterOption option,
) {
  if (option == DateFilterOption.all) return items;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  bool isToday(CakeQueueItem item) {
    final due = parseApiDate(item.dueDate);
    if (due == null) return true;
    return !due.isAfter(today);
  }

  bool isTomorrow(CakeQueueItem item) {
    final due = parseApiDate(item.dueDate);
    if (due == null) return false;
    return due.year == tomorrow.year &&
        due.month == tomorrow.month &&
        due.day == tomorrow.day;
  }

  switch (option) {
    case DateFilterOption.today:
      return items.where(isToday).toList();
    case DateFilterOption.tomorrow:
      return items.where(isTomorrow).toList();
    case DateFilterOption.todayTomorrow:
      return items.where((item) => isToday(item) || isTomorrow(item)).toList();
    case DateFilterOption.all:
      return items;
  }
}

/// Groups [CakeQueueItem]s by their parent order's `orderStatus` in workflow
/// order: `new` → `confirmed` → `in_progress` → `ready` → `delivered`.
///
/// Within each group, items are sorted so that:
/// 1. items without a `dueDate` (null or empty) appear first,
/// 2. then by `dueDate` ascending,
/// 3. then by `dueTime` ascending (null/empty `dueTime` sorts before
///    non-empty `dueTime`).
///
/// Mirrors the `groupDeliveryOrdersByStatus` pattern in `delivery_helpers.dart`,
/// keying groups by the parent order status workflow (not the work item
/// status). Statuses outside the five-value workflow are dropped (per §11
/// risk mitigation: unknown statuses skipped rather than mis-grouped).
Map<String, List<CakeQueueItem>> groupCakeQueueByStatus(
  List<CakeQueueItem> items,
) {
  const workflowOrder = ['new', 'confirmed', 'in_progress', 'ready', 'delivered'];
  final result = <String, List<CakeQueueItem>>{};
  for (final status in workflowOrder) {
    final statusItems =
        items.where((i) => i.orderStatus == status).toList();
    statusItems.sort(_compareByDueDateAndTime);
    result[status] = statusItems;
  }
  return result;
}

int _compareDueTime(String? a, String? b) {
  final aEmpty = a == null || a.isEmpty;
  final bEmpty = b == null || b.isEmpty;
  if (aEmpty && bEmpty) return 0;
  if (aEmpty) return -1;
  if (bEmpty) return 1;
  return a.compareTo(b);
}

int _compareByDueDateAndTime(CakeQueueItem a, CakeQueueItem b) {
  final aHasDate = a.dueDate != null && a.dueDate!.isNotEmpty;
  final bHasDate = b.dueDate != null && b.dueDate!.isNotEmpty;
  if (!aHasDate && bHasDate) return -1;
  if (aHasDate && !bHasDate) return 1;
  if (!aHasDate && !bHasDate) {
    return _compareDueTime(a.dueTime, b.dueTime);
  }
  final aDate = a.dueDate!;
  final bDate = b.dueDate!;
  final dateCmp = aDate.compareTo(bDate);
  if (dateCmp != 0) return dateCmp;
  return _compareDueTime(a.dueTime, b.dueTime);
}
