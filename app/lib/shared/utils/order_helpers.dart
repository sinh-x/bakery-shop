import 'package:flutter/material.dart';

/// Shared order/work-item helper functions.
/// Eliminates duplication across OrderCard, CakeQueueCard, DeliveryOrderCard.

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
  } catch (_) {}
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
  } catch (_) {}
  return false;
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
