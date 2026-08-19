import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';

/// State for the customer add/edit form (DG-404 Phase 4.7).
///
/// Owns the business-logic fields previously mutated via `setState`
/// inside `_CustomerFormState`: the `saving` flag and the
/// `sharedPhone` list returned by the create/update call. The
/// `TextEditingController`-backed name + phone entry controllers stay on
/// the widget (acceptable-use). The widget reads [customerFormProvider]
/// and invokes the notifier's mutators; no `setState` is required.
class CustomerFormState {
  const CustomerFormState({
    this.saving = false,
    this.sharedPhone = const <Customer>[],
    this.rebuildCounter = 0,
  });

  final bool saving;
  final List<Customer> sharedPhone;

  /// Bumped to force a widget rebuild for phone-list structural changes
  /// (add/remove row, primary reassignment). The phone rows themselves hold
  /// `TextEditingController`s that stay on the widget (acceptable-use); this
  /// counter gives the widget a Riverpod-driven rebuild signal in place of
  /// the former `setState` calls.
  final int rebuildCounter;

  CustomerFormState copyWith({
    bool? saving,
    List<Customer>? sharedPhone,
    int? rebuildCounter,
  }) {
    return CustomerFormState(
      saving: saving ?? this.saving,
      sharedPhone: sharedPhone ?? this.sharedPhone,
      rebuildCounter: rebuildCounter ?? this.rebuildCounter,
    );
  }
}

/// `Notifier` that owns the customer-form business-logic state
/// (DG-404 Phase 4.7). All mutations that previously lived in `setState`
/// closures inside `_CustomerFormState` are now exposed as notifier
/// methods. The widget reads the state via [customerFormProvider] and
/// rebuilds on change — no `setState` is required.
class CustomerFormNotifier extends Notifier<CustomerFormState> {
  @override
  CustomerFormState build() => const CustomerFormState();

  void setSaving(bool value) => state = state.copyWith(saving: value);

  /// Bump the rebuild counter to force a widget rebuild for phone-list
  /// structural changes (add/remove/primary) without changing any other
  /// business-logic field.
  void rebuild() =>
      state = state.copyWith(rebuildCounter: state.rebuildCounter + 1);

  void startSubmit() => state = state.copyWith(
        saving: true,
        sharedPhone: const <Customer>[],
      );

  void setSharedPhone(List<Customer> customers) =>
      state = state.copyWith(sharedPhone: customers);

  void clearSaving() => state = state.copyWith(saving: false);
}

/// Provider for the customer-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final customerFormProvider =
    NotifierProvider<CustomerFormNotifier, CustomerFormState>(
  CustomerFormNotifier.new,
);