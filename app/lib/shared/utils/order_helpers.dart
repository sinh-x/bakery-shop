import 'package:flutter/material.dart';

import '../labels/orders.dart';
import '../theme/bakery_theme.dart';

/// Shared order/work-item helper functions.
/// Eliminates duplication across OrderCard, CakeQueueCard, DeliveryOrderCard.

const urgencyCritical = 'critical';
const urgencyUrgent = 'urgent';
const completenessComplete = 'complete';
const completenessIncomplete = 'incomplete';

/// Returns Vietnamese display label for a delivery type.
String deliveryTypeLabel(String type) {
  switch (type) {
    case 'bus':
      return VN.deliveryBus;
    case 'door':
      return VN.deliveryDoor;
    case 'pickup':
    default:
      return VN.pickup;
  }
}

/// Returns urgency border color: red for overdue, amber for same-day, null otherwise.
Color? urgencyBorderColor(String? dueDate) {
  if (dueDate == null || dueDate.isEmpty) return null;
  try {
    final due = DateTime.parse(dueDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDateOnly = DateTime(due.year, due.month, due.day);
    if (dueDateOnly.isBefore(today)) return Colors.red;
    if (dueDateOnly.isAtSameMomentAs(today)) return Colors.amber;
  } catch (error, stackTrace) {
    debugPrint('order_helpers: invalid dueDate "$dueDate": $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  return null;
}

/// Returns true if due within the next 2 hours.
bool isDueWithin2Hours(String? dueDate, String? dueTime) {
  if (dueDate == null || dueDate.isEmpty) return false;
  try {
    final now = DateTime.now();
    DateTime due;
    if (dueTime != null && dueTime.isNotEmpty) {
      due = DateTime.parse('$dueDate $dueTime');
    } else {
      due = DateTime.parse(dueDate);
    }
    return due.isAfter(now) && due.difference(now).inMinutes <= 120;
  } catch (error, stackTrace) {
    debugPrint(
      'order_helpers: invalid due date/time dueDate="$dueDate" dueTime="$dueTime": $error',
    );
    debugPrintStack(stackTrace: stackTrace);
  }
  return false;
}

/// Returns urgency tier color from backend-computed [urgency] field.
/// Uses `BakeryTheme.urgencyTierColors` as single source of truth.
Color? urgencyTierColor(String? urgency) {
  if (urgency == null || urgency == 'normal') return null;
  return BakeryTheme.urgencyTierColors[urgency];
}

/// Returns urgency tier icon data from backend-computed [urgency] field.
IconData? urgencyTierIcon(String? urgency) {
  if (urgency == null || urgency == 'normal') return null;
  return BakeryTheme.urgencyTierIcons[urgency];
}

/// Returns completeness tier color from backend-computed [completeness] field.
Color? completenessTierColor(String? completeness) {
  if (completeness == null || completeness == 'complete') return null;
  return BakeryTheme.completenessTierColors[completeness];
}

/// Returns completeness tier icon from backend-computed [completeness] field.
IconData? completenessTierIcon(String? completeness) {
  if (completeness == null || completeness == 'complete') return null;
  return BakeryTheme.completenessTierIcons[completeness];
}

/// Returns completeness tier label from backend-computed [completeness] field.
String completenessTierLabel(String? completeness) {
  if (completeness == 'incomplete') {
    return OrdersLabels.completenessIncompleteBadge;
  }
  return '';
}

/// Maps a backend missing-field key to a short VN display label for card use.
String missingFieldLabel(String field) {
  switch (field) {
    case 'customer_name':
      return OrdersLabels.missingFieldCustomerName;
    case 'items':
      return OrdersLabels.missingFieldItems;
    case 'total_price':
      return OrdersLabels.missingFieldTotalPrice;
    case 'due_date':
      return OrdersLabels.missingFieldDueDate;
    case 'due_time':
      return OrdersLabels.missingFieldDueTime;
    case 'delivery_address':
      return OrdersLabels.missingFieldDeliveryAddress;
    case 'customer_phone':
      return OrdersLabels.missingFieldCustomerPhone;
    case 'delivery_phone':
      return OrdersLabels.missingFieldDeliveryPhone;
    case 'source':
      return OrdersLabels.missingFieldSource;
    default:
      return field;
  }
}

/// Returns urgency tier label from backend-computed [urgency] field.
String urgencyTierLabel(String? urgency) {
  switch (urgency) {
    case 'critical':
      return OrdersLabels.urgencyCriticalBadge;
    case 'urgent':
      return OrdersLabels.urgencyUrgentBadge;
    default:
      return '';
  }
}

/// Returns delivery icon based on delivery type.
IconData deliveryIcon(String? deliveryType) {
  switch (deliveryType) {
    case 'bus':
      return Icons.directions_bus;
    case 'door':
      return Icons.local_shipping;
    case 'pickup':
    default:
      return Icons.storefront;
  }
}

/// Returns delivery icon color based on delivery type.
Color deliveryIconColor(String? deliveryType, Color defaultColor) {
  switch (deliveryType) {
    case 'bus':
      return Colors.orange;
    case 'door':
      return Colors.deepOrange;
    default:
      return defaultColor;
  }
}

/// Whether delivery type is bus or door (requires delivery).
bool isDeliveryType(String? deliveryType) =>
    deliveryType == 'bus' || deliveryType == 'door';

String visualOrderCode({required String orderRef, String? publicOrderCode}) {
  final code = (publicOrderCode ?? '').trim();
  if (code.isNotEmpty) return code;
  return orderRef;
}

/// Computes the default due date/time for new orders: [from] + 1 hour, rounded
/// UP to the next 30-minute slot. Seconds and milliseconds are dropped.
///
/// Rounding rule (ceil to next 30-min slot):
/// - minute == 0 or 30 → unchanged
/// - minute 1–29 → round up to :30
/// - minute 31–59 → round up to the next hour at :00 (carries into the hour,
///   and into the next day if needed)
///
/// Examples (relative to the +1h target): 16:00→17:00, 16:01→17:30,
/// 16:30→17:30, 16:31→18:00, 16:59→18:00.
DateTime defaultDueDateTime(DateTime from) {
  final target = DateTime(
    from.year,
    from.month,
    from.day,
    from.hour,
    from.minute,
  ).add(const Duration(hours: 1));
  final minute = target.minute;
  if (minute == 0 || minute == 30) {
    return target;
  }
  if (minute < 30) {
    return DateTime(target.year, target.month, target.day, target.hour, 30);
  }
  return DateTime(target.year, target.month, target.day, target.hour)
      .add(const Duration(hours: 1));
}

/// Computes the default due date/time for POS checkout: the current time
/// rounded UP to the next 15-minute slot, with NO +1 hour offset. Seconds and
/// milliseconds are dropped.
///
/// Rounding rule (ceil to next 15-min slot):
/// - minute % 15 == 0 (0, 15, 30, 45) → unchanged
/// - otherwise → round up to the next 15-min boundary (carries into the hour,
///   and into the next day if needed)
///
/// Examples: 16:00→16:00, 16:07→16:15, 16:14→16:15, 16:15→16:15,
/// 16:16→16:30, 16:45→16:45, 16:46→17:00, 23:59→00:00 (next day).
DateTime posDefaultDueDateTime(DateTime from) {
  final target = DateTime(
    from.year,
    from.month,
    from.day,
    from.hour,
    from.minute,
  );
  final minute = target.minute;
  if (minute % 15 == 0) {
    return target;
  }
  final remainder = minute % 15;
  final addMinutes = 15 - remainder;
  return target.add(Duration(minutes: addMinutes));
}
