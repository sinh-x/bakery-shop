import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order.dart';
import 'order_crud_providers.dart';

/// IDs of critical orders that have already triggered an in-app alert in this
/// app session (NFR-4 — in-memory dedupe).
final _alertedOrderRefs = <String>{};

/// Whether an in-app critical-order alert is currently being shown.
final alertActiveProvider = NotifierProvider<_AlertActiveNotifier, bool>(
  _AlertActiveNotifier.new,
);

class _AlertActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool active) {
    state = active;
  }
}

/// Checks for newly-appeared critical orders and returns their count.
///
/// Call every poll cycle from the order list or dashboard screen. Once an
/// order ref is returned it is deduplicated — it will not be returned again
/// in this app session.
///
/// Returns 0 if no new critical orders were found.
int checkNewCriticalOrders(WidgetRef ref) {
  final orders = ref.read(orderListProvider).asData?.value ?? [];
  final newCritical = <Order>[];

  for (final order in orders) {
    if (order.urgency == 'critical' && !_alertedOrderRefs.contains(order.orderRef)) {
      newCritical.add(order);
    }
  }

  if (newCritical.isEmpty) return 0;

  for (final order in newCritical) {
    _alertedOrderRefs.add(order.orderRef);
  }

  return newCritical.length;
}
