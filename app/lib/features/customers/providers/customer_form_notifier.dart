import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/customer.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

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
    this.newDraft = const CustomerFormDraft(),
  });

  final bool saving;
  final List<Customer> sharedPhone;

  /// Bumped to force a widget rebuild for phone-list structural changes
  /// (add/remove row, primary reassignment). The phone rows themselves hold
  /// `TextEditingController`s that stay on the widget (acceptable-use); this
  /// counter gives the widget a Riverpod-driven rebuild signal in place of
  /// the former `setState` calls.
  final int rebuildCounter;
  final CustomerFormDraft newDraft;

  CustomerFormState copyWith({
    bool? saving,
    List<Customer>? sharedPhone,
    int? rebuildCounter,
    CustomerFormDraft? newDraft,
  }) {
    return CustomerFormState(
      saving: saving ?? this.saving,
      sharedPhone: sharedPhone ?? this.sharedPhone,
      rebuildCounter: rebuildCounter ?? this.rebuildCounter,
      newDraft: newDraft ?? this.newDraft,
    );
  }
}

class CustomerFormDraft {
  const CustomerFormDraft({
    this.name = '',
    this.phones = const <CustomerPhone>[],
  });

  final String name;
  final List<CustomerPhone> phones;
}

/// `Notifier` that owns the customer-form business-logic state
/// (DG-404 Phase 4.7). All mutations that previously lived in `setState`
/// closures inside `_CustomerFormState` are now exposed as notifier
/// methods. The widget reads the state via [customerFormProvider] and
/// rebuilds on change — no `setState` is required.
class CustomerFormNotifier extends Notifier<CustomerFormState> {
  CustomerFormNotifier([this.context]);

  final FormDraftContext? context;
  bool _initialized = false;

  @override
  CustomerFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    final draft = context == null
        ? null
        : ref
              .read(formDraftSessionProvider.notifier)
              .readDraft<CustomerFormDraft>(context!);
    _initialized = draft != null;
    return CustomerFormState(newDraft: draft ?? const CustomerFormDraft());
  }

  void initialize(CustomerFormDraft baseline) {
    if (hasRetainedDraft) return;
    state = state.copyWith(newDraft: baseline);
    _initialized = true;
  }

  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);
  CustomerFormDraft get draftSnapshot => state.newDraft;

  void setSaving(bool value) => state = state.copyWith(saving: value);

  /// Bump the rebuild counter to force a widget rebuild for phone-list
  /// structural changes (add/remove/primary) without changing any other
  /// business-logic field.
  void rebuild() =>
      state = state.copyWith(rebuildCounter: state.rebuildCounter + 1);

  void startSubmit() =>
      state = state.copyWith(saving: true, sharedPhone: const <Customer>[]);

  void setSharedPhone(List<Customer> customers) =>
      state = state.copyWith(sharedPhone: customers);

  void clearSaving() => state = state.copyWith(saving: false);

  void updateNewDraft({
    required String name,
    required List<CustomerPhone> phones,
  }) {
    state = state.copyWith(
      newDraft: CustomerFormDraft(name: name, phones: phones),
    );
    if (context != null && _initialized) {
      ref
          .read(formDraftSessionProvider.notifier)
          .retainDraft(context!, state.newDraft);
    }
  }

  void clearNewDraft() {
    state = const CustomerFormState();
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(CustomerFormDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) state = const CustomerFormState();
    return cleared;
  }
}

/// Provider for the customer-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final customerFormProvider =
    NotifierProvider<CustomerFormNotifier, CustomerFormState>(
      CustomerFormNotifier.new,
    );

final contextualCustomerFormProvider =
    NotifierProvider.family<
      CustomerFormNotifier,
      CustomerFormState,
      FormDraftContext
    >(CustomerFormNotifier.new);
