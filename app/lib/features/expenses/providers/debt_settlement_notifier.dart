import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event.dart';
import '../../../shared/labels/expenses.dart';
import '../../../shared/labels/orders.dart';

/// State for the debt-settlement screen (DG-404 Phase 4.1 / FR2).
///
/// Owns the loaded [BakeryEvent] plus its derived totals (total debt,
/// settled-so-far), the loading and submitting flags, the load-error
/// string, and the form fields (`paymentMethod`, `paymentSource`)
/// previously held as `setState` fields inside
/// `_DebtSettlementScreenState`.
class DebtSettlementState {
  const DebtSettlementState({
    this.event,
    this.totalDebt = 0,
    this.settledSoFar = 0,
    this.loading = false,
    this.submitting = false,
    this.loadError,
    this.paymentMethod = OrdersLabels.methodCash,
    this.paymentSource = ExpensesLabels.paymentSourceDrawerCash,
  });

  final BakeryEvent? event;
  final int totalDebt;
  final int settledSoFar;
  final bool loading;
  final bool submitting;
  final String? loadError;
  final String paymentMethod;
  final String paymentSource;

  int get remaining {
    final r = totalDebt - settledSoFar;
    return r < 0 ? 0 : r;
  }

  DebtSettlementState copyWith({
    BakeryEvent? event,
    int? totalDebt,
    int? settledSoFar,
    bool? loading,
    bool? submitting,
    String? loadError,
    String? paymentMethod,
    String? paymentSource,
    bool clearLoadError = false,
  }) {
    return DebtSettlementState(
      event: event ?? this.event,
      totalDebt: totalDebt ?? this.totalDebt,
      settledSoFar: settledSoFar ?? this.settledSoFar,
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentSource: paymentSource ?? this.paymentSource,
    );
  }
}

/// `Notifier` that owns the debt-settlement screen state (DG-404 Phase
/// 4.1 / FR2). The widget reads [debtSettlementProvider] and invokes
/// mutators; no `setState` is required.
class DebtSettlementNotifier extends Notifier<DebtSettlementState> {
  @override
  DebtSettlementState build() => const DebtSettlementState();

  void startLoading() => state = state.copyWith(
        loading: true,
        clearLoadError: true,
      );

  void setLoadedEvent({
    required BakeryEvent event,
    required int totalDebt,
    required int settledSoFar,
  }) =>
      state = state.copyWith(
        event: event,
        totalDebt: totalDebt,
        settledSoFar: settledSoFar,
        loading: false,
        clearLoadError: true,
      );

  void setLoadError(String message) => state = state.copyWith(
        loadError: message,
        loading: false,
      );

  void setSubmitting(bool value) =>
      state = state.copyWith(submitting: value);

  void setPaymentMethod(String value) =>
      state = state.copyWith(paymentMethod: value);

  void setPaymentSource(String value) =>
      state = state.copyWith(paymentSource: value);
}

/// Provider for the debt-settlement screen state.
final debtSettlementProvider =
    NotifierProvider<DebtSettlementNotifier, DebtSettlementState>(
  DebtSettlementNotifier.new,
);