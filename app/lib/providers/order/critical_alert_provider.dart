import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order.dart';
import '../../shared/utils/order_helpers.dart';
import '../../shared/widgets/in_app_alert.dart';
import 'order_crud_providers.dart';

/// IDs of critical orders that have already triggered an in-app alert in this
/// app session (NFR-4 — in-memory dedupe), managed as reactive state.
final alertedOrderRefsProvider = NotifierProvider<_AlertedOrderRefsNotifier, Set<String>>(
  _AlertedOrderRefsNotifier.new,
);

class _AlertedOrderRefsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void addRef(String ref) {
    state = {...state, ref};
  }

  void pruneStaleRefs(Set<String> activeRefs) {
    state = state.where((r) => activeRefs.contains(r)).toSet();
  }
}

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
  final alertedNotifier = ref.read(alertedOrderRefsProvider.notifier);

  final activeRefs = orders.map((o) => o.orderRef).toSet();
  alertedNotifier.pruneStaleRefs(activeRefs);

  final alertedRefs = ref.read(alertedOrderRefsProvider);
  final newCritical = <Order>[];

  for (final order in orders) {
    if (order.urgency == urgencyCritical && !alertedRefs.contains(order.orderRef)) {
      newCritical.add(order);
    }
  }

  if (newCritical.isEmpty) return 0;

  for (final order in newCritical) {
    alertedNotifier.addRef(order.orderRef);
  }

  return newCritical.length;
}

/// Shared helper that checks for new critical orders and shows the in-app alert
/// if any are found. Extracted to eliminate duplication between
/// [DashboardScreen] and [OrderListScreen].
void checkAndShowCriticalAlert({
  required WidgetRef ref,
  required BuildContext context,
  required bool mounted,
}) {
  if (ref.read(alertActiveProvider)) return;
  final count = checkNewCriticalOrders(ref);
  if (count > 0 && mounted) {
    ref.read(alertActiveProvider.notifier).setActive(true);
    InAppAlert.show(
      context: context,
      count: count,
      onDismiss: () {
        ref.read(alertActiveProvider.notifier).setActive(false);
      },
    );
  }
}
