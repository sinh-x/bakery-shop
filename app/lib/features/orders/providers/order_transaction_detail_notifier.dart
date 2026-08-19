import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Order transaction detail sheet acting-flag state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_acting` field previously mutated via `setState` inside
/// `_OrderTransactionDetailSheetState`. The widget reads
/// [orderTransactionDetailProvider] and invokes the notifier's
/// [setActing] method; no `setState` is required.
class OrderTransactionDetailNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setActing(bool value) => state = value;
}

final orderTransactionDetailProvider =
    NotifierProvider<OrderTransactionDetailNotifier, bool>(
        OrderTransactionDetailNotifier.new);