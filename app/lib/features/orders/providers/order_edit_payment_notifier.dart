import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Order edit-payment sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_type`, `_method`, `_paymentSource`, and `_submitting` fields
/// previously mutated via `setState` inside `_OrderEditPaymentSheetState`.
/// The widget reads [orderEditPaymentProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class OrderEditPaymentState {
  const OrderEditPaymentState({
    required this.type,
    required this.method,
    this.paymentSource,
    this.submitting = false,
  });

  final String type;
  final String method;
  final String? paymentSource;
  final bool submitting;

  OrderEditPaymentState copyWith({
    String? type,
    String? method,
    String? paymentSource,
    bool? submitting,
    bool clearPaymentSource = false,
  }) =>
      OrderEditPaymentState(
        type: type ?? this.type,
        method: method ?? this.method,
        paymentSource:
            clearPaymentSource ? null : (paymentSource ?? this.paymentSource),
        submitting: submitting ?? this.submitting,
      );
}

class OrderEditPaymentNotifier extends Notifier<OrderEditPaymentState> {
  @override
  OrderEditPaymentState build() => const OrderEditPaymentState(
        type: 'deposit',
        method: 'cash',
      );

  /// Seed the initial values from the transaction being edited. Called once
  /// from the widget's `initState` before any mutation.
  void seed({
    required String type,
    required String method,
    String? paymentSource,
  }) =>
      state = OrderEditPaymentState(
        type: type,
        method: method,
        paymentSource: paymentSource,
      );

  void setType(String type) => state = state.copyWith(type: type);

  void setMethod(String method) => state = state.copyWith(
        method: method,
        clearPaymentSource: method != 'transfer',
      );

  void setPaymentSource(String? value) =>
      state = state.copyWith(paymentSource: value);

  void setSubmitting(bool value) =>
      state = state.copyWith(submitting: value);
}

final orderEditPaymentProvider =
    NotifierProvider<OrderEditPaymentNotifier, OrderEditPaymentState>(
        OrderEditPaymentNotifier.new);