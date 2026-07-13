import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/labels/auth.dart';
import 'auth_provider.dart';

/// Login screen (FR14).
///
/// Renders username + password fields, a login button, and an error banner.
/// On a successful login the auth notifier transitions to `authenticated` and
/// the router guard redirects to the main shell (orders tab). On failure the
/// HTTP status code is mapped to a Vietnamese error message.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authProvider.notifier).login(
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // On success the router redirect guard will navigate to /orders; no
      // explicit navigation here.
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _mapDioError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthLabels.loginErrorGeneric);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _mapDioError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) return AuthLabels.invalidCredentials;
    if (code == 423) return AuthLabels.accountLocked;
    if (code == 429) return AuthLabels.tooManyAttempts;
    return AuthLabels.loginErrorGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.bakery_dining_rounded,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      AuthLabels.loginTitle,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _UsernameField(controller: _usernameCtrl),
                    const SizedBox(height: 16),
                    _PasswordField(
                      controller: _passwordCtrl,
                      obscure: _obscurePassword,
                      onToggleObscure: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
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
                          : const Text(AuthLabels.loginButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsernameField extends StatelessWidget {
  const _UsernameField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: AuthLabels.usernameLabel,
        hintText: AuthLabels.usernameHint,
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person_outline),
      ),
      textInputAction: TextInputAction.next,
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? AuthLabels.usernameLabel : null,
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: AuthLabels.passwordLabel,
        hintText: AuthLabels.passwordHint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: onToggleObscure,
        ),
      ),
      textInputAction: TextInputAction.done,
      validator: (value) =>
          (value == null || value.isEmpty) ? AuthLabels.passwordLabel : null,
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