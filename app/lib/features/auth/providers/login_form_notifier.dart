import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Form state for the login screen (DG-404 Phase 4.7).
///
/// Holds the fields previously mutated via `setState` inside
/// `_LoginScreenState`: the password-visibility toggle
/// (`obscurePassword`), the `submitting` flag, and the `errorMessage`
/// string. The widget reads [loginFormProvider] and invokes the
/// notifier's mutators; no `setState` is required.
/// `TextEditingController`-backed fields (username, password) remain on
/// the widget (acceptable use).
class LoginFormState {
  const LoginFormState({
    this.obscurePassword = true,
    this.submitting = false,
    this.errorMessage,
  });

  final bool obscurePassword;
  final bool submitting;
  final String? errorMessage;

  LoginFormState copyWith({
    bool? obscurePassword,
    bool? submitting,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return LoginFormState(
      obscurePassword: obscurePassword ?? this.obscurePassword,
      submitting: submitting ?? this.submitting,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// `Notifier` that owns the login form state (DG-404 Phase 4.7).
///
/// All mutations that previously lived in `setState` closures inside
/// `_LoginScreenState` are now exposed as notifier methods. The widget
/// reads the state via [loginFormProvider] and rebuilds on change — no
/// `setState` is required.
class LoginFormNotifier extends Notifier<LoginFormState> {
  @override
  LoginFormState build() => const LoginFormState();

  void toggleObscurePassword() =>
      state = state.copyWith(obscurePassword: !state.obscurePassword);

  void startSubmitting() => state = state.copyWith(
        submitting: true,
        clearErrorMessage: true,
      );

  void setErrorMessage(String message) =>
      state = state.copyWith(errorMessage: message);

  void setSubmitting(bool value) =>
      state = state.copyWith(submitting: value);
}

/// Provider for the login form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final loginFormProvider =
    NotifierProvider<LoginFormNotifier, LoginFormState>(
    LoginFormNotifier.new);