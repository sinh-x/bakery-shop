import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';

/// Form state for the reusable password-change form (DG-404 Phase 4.7).
///
/// Holds the fields previously mutated via `setState` inside
/// `_PasswordChangeFormState`: the three password-visibility toggles
/// (`obscureOld`, `obscureNew`, `obscureConfirm`), the `submitting` flag,
/// and the `errorMessage` string. The widget reads
/// [passwordChangeFormProvider] and invokes the notifier's mutators; no
/// `setState` is required. `TextEditingController`-backed fields (old,
/// new, confirm) remain on the widget (acceptable use).
class PasswordChangeFormState {
  const PasswordChangeFormState({
    this.obscureOld = true,
    this.obscureNew = true,
    this.obscureConfirm = true,
    this.submitting = false,
    this.errorMessage,
  });

  final bool obscureOld;
  final bool obscureNew;
  final bool obscureConfirm;
  final bool submitting;
  final String? errorMessage;

  PasswordChangeFormState copyWith({
    bool? obscureOld,
    bool? obscureNew,
    bool? obscureConfirm,
    bool? submitting,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return PasswordChangeFormState(
      obscureOld: obscureOld ?? this.obscureOld,
      obscureNew: obscureNew ?? this.obscureNew,
      obscureConfirm: obscureConfirm ?? this.obscureConfirm,
      submitting: submitting ?? this.submitting,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

/// `Notifier` that owns the password-change form state (DG-404 Phase 4.7).
///
/// All mutations that previously lived in `setState` closures inside
/// `_PasswordChangeFormState` are now exposed as notifier methods. The
/// widget reads the state via [passwordChangeFormProvider] and rebuilds
/// on change — no `setState` is required.
class PasswordChangeFormNotifier extends Notifier<PasswordChangeFormState> {
  @override
  PasswordChangeFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    return const PasswordChangeFormState();
  }

  void toggleObscureOld() =>
      state = state.copyWith(obscureOld: !state.obscureOld);

  void toggleObscureNew() =>
      state = state.copyWith(obscureNew: !state.obscureNew);

  void toggleObscureConfirm() =>
      state = state.copyWith(obscureConfirm: !state.obscureConfirm);

  void startSubmitting() =>
      state = state.copyWith(submitting: true, clearErrorMessage: true);

  void setErrorMessage(String message) =>
      state = state.copyWith(errorMessage: message);

  void setSubmitting(bool value) => state = state.copyWith(submitting: value);

  void reset() => state = const PasswordChangeFormState();
}

/// Provider for the password-change form state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final passwordChangeFormProvider =
    NotifierProvider<PasswordChangeFormNotifier, PasswordChangeFormState>(
      PasswordChangeFormNotifier.new,
    );
