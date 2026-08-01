import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/labels/auth.dart';
import '../auth_provider.dart';

/// Reusable password-change form (DG-319 Phase 5 / FR5).
///
/// Renders three fields (old, new, confirm) with client-side validation
/// (AC3, AC4) and an error banner. On success it calls [onSuccess] so the
/// hosting screen decides routing (self-service stays on the previous screen
/// via the session-clear redirect; forced change navigates to /orders).
///
/// Both [PasswordChangeScreen] (Settings → self-service) and
/// [ForceChangeScreen] (forced, full-screen) embed this widget so the form
/// logic lives in one place.
class PasswordChangeForm extends ConsumerStatefulWidget {
  const PasswordChangeForm({
    super.key,
    required this.onSuccess,
    this.title = AuthLabels.changePasswordTitle,
  });

  /// Called on the main thread after a successful password change. The auth
  /// state has already been cleared (the backend revoked all sessions), so
  /// the host screen typically navigates or lets the router guard redirect.
  final VoidCallback onSuccess;

  /// Optional override of the title text (defaults to self-service label).
  /// The forced-change screen passes [AuthLabels.forcePasswordChangeTitle].
  final String title;

  @override
  ConsumerState<PasswordChangeForm> createState() => _PasswordChangeFormState();
}

class _PasswordChangeFormState extends ConsumerState<PasswordChangeForm> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authProvider.notifier).changePassword(
            oldPassword: _oldCtrl.text,
            newPassword: _newCtrl.text,
            confirmPassword: _confirmCtrl.text,
          );
      if (!mounted) return;
      widget.onSuccess();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _mapDioError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthLabels.changePasswordFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _mapDioError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) return AuthLabels.oldPasswordIncorrect;
    if (code == 422) return AuthLabels.passwordsDoNotMatch;
    return AuthLabels.changePasswordFailed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _PasswordField(
            controller: _oldCtrl,
            label: AuthLabels.oldPasswordLabel,
            hint: AuthLabels.oldPasswordHint,
            obscure: _obscureOld,
            onToggleObscure: () =>
                setState(() => _obscureOld = !_obscureOld),
            validator: (value) => (value == null || value.isEmpty)
                ? AuthLabels.passwordRequired
                : null,
          ),
          const SizedBox(height: 16),
          _PasswordField(
            controller: _newCtrl,
            label: AuthLabels.newPasswordLabel,
            hint: AuthLabels.newPasswordHint,
            obscure: _obscureNew,
            onToggleObscure: () =>
                setState(() => _obscureNew = !_obscureNew),
            validator: (value) => (value == null || value.isEmpty)
                ? AuthLabels.passwordRequired
                : null,
          ),
          const SizedBox(height: 16),
          _PasswordField(
            controller: _confirmCtrl,
            label: AuthLabels.confirmPasswordLabel,
            hint: AuthLabels.confirmPasswordHint,
            obscure: _obscureConfirm,
            onToggleObscure: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
            // AC3: new != confirm → validation error before submission.
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AuthLabels.passwordRequired;
              }
              if (value != _newCtrl.text) {
                return AuthLabels.passwordsDoNotMatch;
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Text(AuthLabels.changePasswordButton),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.onToggleObscure,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
          onPressed: onToggleObscure,
        ),
      ),
      textInputAction: TextInputAction.next,
      validator: validator,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
