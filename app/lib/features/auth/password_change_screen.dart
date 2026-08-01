import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/labels/auth.dart';
import 'widgets/password_change_form.dart';

/// Self-service password change screen (DG-319 Phase 5 / FR5).
///
/// Reached from Settings → General tab ("Đổi mật khẩu"). It is registered as
/// a full-screen route (outside the app shell) at `/change-password`. On a
/// successful change the backend revokes all sessions, so the auth notifier
/// transitions to `unauthenticated` and the router guard redirects to
/// `/login` for a fresh login with the new password.
///
/// For the forced-change flow (admin `--force-change`), [ForceChangeScreen]
/// wraps the same [PasswordChangeForm] but clears the local
/// `force_password_change` flag and redirects to `/orders` on success.
class PasswordChangeScreen extends ConsumerWidget {
  const PasswordChangeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text(AuthLabels.changePasswordTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: PasswordChangeForm(
                title: AuthLabels.changePasswordTitle,
                // The auth notifier clears the session on success; the router
                // guard then redirects to /login. No explicit navigation here.
                onSuccess: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}
