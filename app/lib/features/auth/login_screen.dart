import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/labels/auth.dart';
import '../../shared/labels/technical_settings.dart';
import '../../shared/providers/auth_provider.dart';
import 'providers/login_form_notifier.dart';
import 'widgets/error_banner.dart';
import 'widgets/password_field.dart';
import 'widgets/username_field.dart';

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

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(loginFormProvider.notifier);
    notifier.startSubmitting();
    try {
      await ref.read(authProvider.notifier).login(
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // On success the router redirect guard will navigate to /orders; no
      // explicit navigation here.
    } on DioException catch (e) {
      if (!mounted) return;
      notifier.setErrorMessage(_mapDioError(e));
    } catch (_) {
      if (!mounted) return;
      notifier.setErrorMessage(AuthLabels.loginErrorGeneric);
    } finally {
      if (mounted) notifier.setSubmitting(false);
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
    final formState = ref.watch(loginFormProvider);
    final obscurePassword = formState.obscurePassword;
    final submitting = formState.submitting;
    final errorMessage = formState.errorMessage;
    final notifier = ref.read(loginFormProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const Key('preLoginSettingsButton'),
            icon: const Icon(Icons.settings),
            tooltip: TechnicalSettingsLabels.openSettingsTooltip,
            onPressed: () => context.go('/settings/connection'),
          ),
        ],
      ),
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
                    UsernameField(controller: _usernameCtrl),
                    const SizedBox(height: 16),
                    PasswordField(
                      controller: _passwordCtrl,
                      obscure: obscurePassword,
                      onToggleObscure: notifier.toggleObscurePassword,
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(message: errorMessage),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: submitting ? null : _submit,
                      child: submitting
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