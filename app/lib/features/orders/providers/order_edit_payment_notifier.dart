import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Order edit-payment sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_type`, `_method`, `_paymentSource`, `_createdAt`, and
/// `_submitting` fields previously mutated via `setState` inside
/// `_OrderEditPaymentSheetState`. The widget reads [orderEditPaymentProvider]
/// and invokes the notifier's mutators; no `setState` is required.
///
/// `_createdAt` (DG-415 Phase 3 / FR2) is seeded from the existing transaction
/// so the edit sheet's picker opens pre-filled with the stored timestamp.
class OrderEditPaymentState {
  const OrderEditPaymentState({
    required this.type,
    required this.method,
    this.paymentSource,
    this.createdAt,
    this.submitting = false,
  });

  final String type;
  final String method;
  final String? paymentSource;
  final DateTime? createdAt;
  final bool submitting;

  OrderEditPaymentState copyWith({
    String? type,
    String? method,
    String? paymentSource,
    DateTime? createdAt,
    bool? submitting,
    bool clearPaymentSource = false,
    bool clearCreatedAt = false,
  }) =>
      OrderEditPaymentState(
        type: type ?? this.type,
        method: method ?? this.method,
        paymentSource:
            clearPaymentSource ? null : (paymentSource ?? this.paymentSource),
        createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
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
  /// from the widget's `initState` before any mutation. `createdAt` (FR2)
  /// pre-fills the date+time picker with the existing transaction timestamp.
  void seed({
    required String type,
    required String method,
    String? paymentSource,
    DateTime? createdAt,
  }) =>
      state = OrderEditPaymentState(
        type: type,
        method: method,
        paymentSource: paymentSource,
        createdAt: createdAt,
      );

  void setType(String type) => state = state.copyWith(type: type);

  void setMethod(String method) => state = state.copyWith(
        method: method,
        clearPaymentSource: method != 'transfer',
      );

  void setPaymentSource(String? value) =>
      state = state.copyWith(paymentSource: value);

  /// FR2/FR7: replace the picker's date component while keeping the time.
  void setCreatedDate(DateTime date) {
    final current = state.createdAt ?? DateTime.now();
    state = state.copyWith(
      createdAt: DateTime(
        date.year,
        date.month,
        date.day,
        current.hour,
        current.minute,
        current.second,
      ),
    );
  }

  /// FR2: replace the picker's time component while keeping the date.
  void setCreatedTime(TimeOfDay time) {
    final current = state.createdAt ?? DateTime.now();
    state = state.copyWith(
      createdAt: DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void setSubmitting(bool value) =>
      state = state.copyWith(submitting: value);
}

final orderEditPaymentProvider =
    NotifierProvider<OrderEditPaymentNotifier, OrderEditPaymentState>(
        OrderEditPaymentNotifier.new);