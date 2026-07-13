import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// A widget that hides its [child] unless the authenticated user is an admin.
///
/// Used for UI gating (FR16/AC10): admin-only navigation entries, menu items,
/// and tabs render only when the JWT `role` claim is `admin`. When the user is
/// a staff member (or auth state is not authenticated), this widget renders
/// nothing instead of [child].
///
/// For route-level gating use [AdminAccessScreen] or the router redirect guard
/// in `app_router.dart`.
class AdminOnly extends ConsumerWidget {
  const AdminOnly({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.isAuthenticated && auth.isAdmin) {
      return child;
    }
    return const SizedBox.shrink();
  }
}

/// Full-screen page shown when a staff user attempts to navigate directly to
/// an admin-only route (the router redirect guard forwards here).
///
/// This is a fallback affordance — under normal flow staff users never see the
/// navigation entry that would push the gated route. The screen exists so a
/// deep link or manual `context.go()` does not silently show a blank page.
class AdminAccessScreen extends StatelessWidget {
  const AdminAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(VN.accessDeniedTitle)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                VN.accessDeniedTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                VN.accessDeniedBody,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}