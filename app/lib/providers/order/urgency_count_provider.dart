import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_crud_providers.dart';

/// Count of active orders with urgency "critical" or "urgent".
///
/// Derived from [orderListProvider] so it updates automatically whenever the
/// order list refreshes (handled by AutoRefreshMixin's 15s poll cycle).
final urgencyCountProvider = Provider<int>((ref) {
  final orders = ref.watch(orderListProvider).asData?.value ?? [];
  return orders.where((o) => o.urgency == 'critical' || o.urgency == 'urgent').length;
});
