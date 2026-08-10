import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/auth_provider.dart';
import '../../../features/templates/template_management_screen.dart';

/// Message-template feature route definitions (DG-375 Phase 4 / FR10).
///
/// Exposes the template management screen. The route reads the current auth
/// state to determine whether the caller is an admin, so the management
/// screen can hide admin-only affordances (system-template editing) for
/// non-admin staff.
List<RouteBase> templatesRoutes() => [
      GoRoute(
        path: '/templates/manage',
        builder: (context, state) {
          final container = ProviderScope.containerOf(context, listen: false);
          final isAdmin = container.read(authProvider).isAdmin;
          return TemplateManagementScreen(isAdmin: isAdmin);
        },
      ),
    ];