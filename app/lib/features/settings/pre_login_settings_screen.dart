import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Pre-login technical settings screen placeholder (DG-367 Phase 1).
///
/// This is the route target registered in Phase 1 so the auth guard exemption
/// for `/settings/connection` resolves to a real route. Phase 2 replaces this
/// with the full screen (server URL input, test connection, save) reusing
/// ApiBaseUrlNotifier and the existing connection test pattern.
class PreLoginSettingsScreen extends StatelessWidget {
  const PreLoginSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: const SizedBox.shrink(),
    );
  }
}