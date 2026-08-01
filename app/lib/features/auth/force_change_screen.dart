import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/labels/auth.dart';
import 'widgets/password_change_form.dart';

/// Forced password change screen (DG-319 Phase 5 / FR9 / FR10 / AC7 / AC8).
///
/// Reached when the login response reports `force_password_change: true`
/// (set by admin `baker user set-password --force-change`). The router guard
/// redirects here before the user can access the app shell.
///
/// Unlike [PasswordChangeScreen] (self-service), this screen:
///   - shows the forced-change title and an explanatory message banner, and
///   - on success redirects to `/login` for a fresh login. The backend revoked
///     all sessions on the change and `changePassword()` cleared local state to
///     `unauthenticated`, so the router guard routes to `/login`. After re-login
///     the login response no longer carries the flag (the backend cleared it,
///     FR10), so the router routes to `/orders`.
class ForceChangeScreen extends ConsumerWidget {
  const ForceChangeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AuthLabels.forcePasswordChangeTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_reset,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AuthLabels.forcePasswordChangeMessage,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  PasswordChangeForm(
                    title: AuthLabels.forcePasswordChangeTitle,
                    onSuccess: () {
                      // changePassword() already cleared local state to
                      // `unauthenticated` (backend revoked all sessions), so the
                      // router guard redirects to /login for a fresh login.
                      context.go('/login');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
