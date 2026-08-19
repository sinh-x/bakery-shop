import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local form state for the reconciliation sale/waste modal bottom
/// sheets (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_paymentMethod`, `_paymentMethodError` (sale modal) and
/// `_wasteReasonError` (waste modal) fields previously mutated via
/// `setState` inside the modal content states. The quantity / unit
/// price / waste reason `TextEditingController`s stay on the widget
/// because `TextEditingController` lifecycle is an acceptable-use case
/// (see DG-404 guardrails). A `rebuildToken` counter is exposed so the
/// waste modal can force a rebuild when its waste-qty controller
/// listener fires (the controller text drives conditional UI). The
/// widget reads [reconciliationSellWasteModalProvider] and invokes the
/// notifier's mutators; no `setState` is required.
class ReconciliationSellWasteModalState {
  const ReconciliationSellWasteModalState({
    this.paymentMethod,
    this.paymentMethodError = false,
    this.wasteReasonError = false,
    this.rebuildToken = 0,
  });

  final String? paymentMethod;
  final bool paymentMethodError;
  final bool wasteReasonError;
  final int rebuildToken;

  ReconciliationSellWasteModalState copyWith({
    String? paymentMethod,
    bool? paymentMethodError,
    bool? wasteReasonError,
    int? rebuildToken,
  }) {
    return ReconciliationSellWasteModalState(
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentMethodError:
          paymentMethodError ?? this.paymentMethodError,
      wasteReasonError: wasteReasonError ?? this.wasteReasonError,
      rebuildToken: rebuildToken ?? this.rebuildToken,
    );
  }
}

/// `Notifier` that owns the local form state for the reconciliation
/// sale/waste modal bottom sheets (DG-404 Phase 4.7 / FR2). Keyed by
/// the option key via a family provider so each modal instance
/// maintains its own form state.
/// Following the codebase convention for `NotifierProvider.family`
/// (arg as constructor param, see `ExpenseHistoryPhotoNotifier`).
class ReconciliationSellWasteModalNotifier
    extends Notifier<ReconciliationSellWasteModalState> {
  final String optionKey;

  ReconciliationSellWasteModalNotifier(this.optionKey);

  @override
  ReconciliationSellWasteModalState build() =>
      const ReconciliationSellWasteModalState();

  /// Seed the initial payment method (sale modal) from the editing row
  /// or the cash default. Called once from `initState`.
  void seedPaymentMethod(String? method) =>
      state = state.copyWith(paymentMethod: method);

  void setPaymentMethod(String? value) => state = state.copyWith(
        paymentMethod: value,
        paymentMethodError: false,
      );

  void setPaymentMethodError(bool value) =>
      state = state.copyWith(paymentMethodError: value);

  void setWasteReasonError(bool value) =>
      state = state.copyWith(wasteReasonError: value);

  void clearWasteReasonError() =>
      state = state.copyWith(wasteReasonError: false);

  /// Bump the rebuild token so watchers rebuild (used by the waste
  /// modal's waste-qty controller listener to refresh conditional UI).
  void rebuild() =>
      state = state.copyWith(rebuildToken: state.rebuildToken + 1);
}

/// Family provider for the reconciliation sale/waste modal form state,
/// keyed by the option key.
final reconciliationSellWasteModalProvider = NotifierProvider.family<
    ReconciliationSellWasteModalNotifier,
    ReconciliationSellWasteModalState,
    String>(ReconciliationSellWasteModalNotifier.new);