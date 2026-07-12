import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/order_helpers.dart';
import 'order_crud_providers.dart';

/// Count of active orders with completeness "incomplete".
///
/// Derived from [orderListProvider] so it updates automatically whenever the
/// order list refreshes (handled by AutoRefreshMixin's 15s poll cycle).
///
/// Design decision: returns 0 (empty) on API error rather than showing stale
/// counts. This means badges will be hidden during API outages — degraded UX
/// is intentional to avoid displaying potentially incorrect counts.
final incompleteCountProvider = Provider<int>((ref) {
  final orders = ref.watch(orderListProvider).asData?.value ?? [];
  return orders.where((o) => o.completeness == completenessIncomplete).length;
});
