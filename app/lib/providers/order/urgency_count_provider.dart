import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/order_helpers.dart';
import 'order_crud_providers.dart';

/// Count of active orders with urgency "critical" or "urgent".
///
/// Only counts orders whose status is currently active (new, confirmed,
/// in_progress, ready, delivered). Completed and cancelled orders are
/// excluded even if they are critical or urgent.
///
/// Derived from [orderListProvider] so it updates automatically whenever the
/// order list refreshes (handled by AutoRefreshMixin's 15s poll cycle).
///
/// Design decision: returns 0 (empty) on API error rather than showing stale
/// counts. This means badges will be hidden during API outages — degraded UX
/// is intentional to avoid displaying potentially incorrect counts.
final urgencyCountProvider = Provider<int>((ref) {
  final orders = ref.watch(orderListProvider).asData?.value ?? [];
  const activeStatuses = [
    'new',
    'confirmed',
    'in_progress',
    'ready',
    'delivered',
  ];
  return orders
      .where(
        (o) =>
            (o.urgency == urgencyCritical || o.urgency == urgencyUrgent) &&
            activeStatuses.contains(o.status),
      )
      .length;
});
