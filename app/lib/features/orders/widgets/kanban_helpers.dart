import '../../../data/models/order.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/utils/order_helpers.dart' show isDeliveryType;

/// Active Kanban columns in order workflow.
///
/// 'to_deliver' is a virtual status for ready orders with bus/door delivery.
/// 'awaiting_payment' is a virtual status for delivered+unpaid orders.
const kanbanStatuses = [
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'to_deliver',
  'awaiting_payment',
];

/// Groups active orders into Kanban columns.
///
/// Handles virtual columns:
/// - 'ready' = status=ready AND is pickup (not bus/door)
/// - 'to_deliver' = status=ready AND deliveryType is bus or door
/// - 'awaiting_payment' = status=delivered AND not paid
///
/// Terminal statuses (completed, cancelled) are not included in any column.
///
/// Within each column orders are sorted by `dueDate` ascending; orders with
/// a null `dueDate` sort last (FR5 / AC5 / AC6).
Map<String, List<Order>> groupOrdersByKanbanStatus(List<Order> orders) {
  DateTime? dueDateOf(Order o) => parseApiDate(o.dueDate);
  int compareByDueDate(Order a, Order b) {
    final da = dueDateOf(a);
    final db = dueDateOf(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1; // nulls last
    if (db == null) return -1;
    return da.compareTo(db);
  }

  List<Order> sorted(Iterable<Order> input) =>
      input.toList()..sort(compareByDueDate);

  final result = <String, List<Order>>{};
  for (final status in kanbanStatuses) {
    if (status == 'to_deliver') {
      // Ready orders that need delivery (bus/door-to-door)
      result[status] = sorted(orders.where(
        (o) =>
            o.status == 'ready' &&
            isDeliveryType(o.deliveryType),
      ));
    } else if (status == 'ready') {
      // Ready orders excluding delivery ones (pickup only)
      result[status] = sorted(orders.where(
        (o) =>
            o.status == 'ready' &&
            !isDeliveryType(o.deliveryType),
      ));
    } else if (status == 'awaiting_payment') {
      result[status] = sorted(
          orders.where((o) => o.status == 'delivered' && !o.isPaid));
    } else {
      result[status] = sorted(orders.where((o) => o.status == status));
    }
  }
  return result;
}