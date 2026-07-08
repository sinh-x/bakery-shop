import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/order_draft.dart';
import '../../../../data/models/product.dart';
import '../../../../data/models/work_item.dart';
import '../../../../providers/config_provider.dart';
import '../../../../shared/utils/config_parsers.dart';
import '../../../../shared/utils/date_formatting.dart';

/// Default shipping fee (VND) for bus delivery when the config provider is
/// still loading or returns an error. Kept as a module-level constant so the
/// fallback value is documented in one place instead of being a magic number.
const _defaultShippingFeeBus = 25000.0;

/// Default shipping fee (VND) for door delivery when the config provider is
/// still loading or returns an error.
const _defaultShippingFeeDoor = 20000.0;

/// Converts a [WorkItem] (server-side work item) into a [DraftOrderItem] with
/// a minimal [Product] stub so the summary cards can render the edit-order
/// summary cards with real data. The summary cards only read `product.name`,
/// `quantity`, `unitPrice`, `isExtra`, and `isGift`, so a minimal stub is
/// sufficient (FB-6).
DraftOrderItem workItemToDraft(WorkItem w) {
  final stub = Product(
    id: int.tryParse(w.productId) ?? 0,
    name: w.productName,
    basePrice: w.unitPrice,
  );
  return DraftOrderItem(
    product: stub,
    quantity: w.quantity,
    notes: w.notes,
    isBirthday: w.isBirthday,
    isExtra: w.isExtra,
    isGift: w.isGift,
    attributes: Map<String, dynamic>.from(w.attributes),
  );
}

/// Maps a list of server-side [WorkItem]s into [DraftOrderItem]s for the
/// edit-order summary cards.
List<DraftOrderItem> summaryItemsFromWorkItems(List<WorkItem> workItems) {
  return workItems.map(workItemToDraft).toList();
}

/// Resolves the bus/door shipping-fee defaults from the config providers,
/// falling back to [_defaultShippingFeeBus] / [_defaultShippingFeeDoor] while
/// loading or on error.
({double bus, double door}) shippingFeeDefaults(WidgetRef ref) {
  final busAsync = ref.watch(shippingFeeBusProvider);
  final doorAsync = ref.watch(shippingFeeDoorProvider);
  final bus = busAsync.when(
    data: (values) => firstFeeOrFallback(values, _defaultShippingFeeBus),
    loading: () => _defaultShippingFeeBus,
    error: (_, _) => _defaultShippingFeeBus,
  );
  final door = doorAsync.when(
    data: (values) => firstFeeOrFallback(values, _defaultShippingFeeDoor),
    loading: () => _defaultShippingFeeDoor,
    error: (_, _) => _defaultShippingFeeDoor,
  );
  return (bus: bus, door: door);
}

/// Returns the shipping fee for a delivery type, using the configured bus /
/// door defaults and zero for pickup.
double shippingFeeForDeliveryType(
  String type, {
  required double busDefault,
  required double doorDefault,
}) {
  switch (type) {
    case 'bus':
      return busDefault;
    case 'door':
      return doorDefault;
    case 'pickup':
    default:
      return 0;
  }
}

/// Parses an order's due date string into a [DateTime], logging invalid
/// values. Returns null when the date is absent or unparseable.
DateTime? parseDueDate(String? dueDate) {
  if (dueDate == null) return null;
  final parsed = parseApiDate(dueDate);
  if (parsed == null) {
    debugPrint('order_edit: invalid due date "$dueDate"');
  }
  return parsed;
}

/// Parses an order's due time string ("HH:mm") into a [TimeOfDay]. Returns
/// null when the time is absent or malformed.
TimeOfDay? parseDueTime(String? dueTime) {
  if (dueTime == null) return null;
  final parts = dueTime.split(':');
  if (parts.length != 2) return null;
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: int.tryParse(parts[1]) ?? 0,
  );
}