import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/order_breakdown_mode.dart';

/// Sync state for the order-breakdown section dropdown (DG-404 Phase
/// 4.7 / FR2). Owns the selected display mode previously held as a
/// `setState` field inside `_OrderBreakdownSectionState`.
class OrderBreakdownSectionState {
  const OrderBreakdownSectionState({
    this.mode = OrderBreakdownMode.countRevenue,
  });

  final OrderBreakdownMode mode;

  OrderBreakdownSectionState copyWith({OrderBreakdownMode? mode}) {
    return OrderBreakdownSectionState(mode: mode ?? this.mode);
  }
}

/// `Notifier` that owns the order-breakdown section dropdown state
/// (DG-404 Phase 4.7 / FR2). Sync state because the mutation is local.
class OrderBreakdownSectionNotifier
    extends Notifier<OrderBreakdownSectionState> {
  @override
  OrderBreakdownSectionState build() => const OrderBreakdownSectionState();

  void setMode(OrderBreakdownMode mode) =>
      state = state.copyWith(mode: mode);
}

/// Provider for the order-breakdown section dropdown state.
final orderBreakdownSectionProvider =
    NotifierProvider<OrderBreakdownSectionNotifier,
        OrderBreakdownSectionState>(OrderBreakdownSectionNotifier.new);