import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/order_helpers.dart';
import 'order_crud_providers.dart';

/// Count of active orders with completeness "incomplete".
///
/// Derived from [orderListProvider] so it updates automatically whenever the
/// order list refreshes (handled by AutoRefreshMixin's 15s poll cycle).
final incompleteCountProvider = Provider<int>((ref) {
  final orders = ref.watch(orderListProvider).asData?.value ?? [];
  return orders.where((o) => o.completeness == completenessIncomplete).length;
});
