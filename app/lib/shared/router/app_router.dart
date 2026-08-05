import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/auth/force_change_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/password_change_screen.dart';
import '../../features/dashboard/management_dashboard_screen.dart';
import '../../features/orders/order_list_screen.dart';
import '../../features/products/product_catalog_screen.dart';
import '../../features/knowledge_base/knowledge_base_screen.dart';
import '../../features/events/event_list_screen.dart';
import '../../features/cash_drawer/cash_drawer_screen.dart';
import '../../features/checklist/checklist_screen.dart';
import '../../features/knowledge/knowledge_list_screen.dart';
import '../../features/pos/pos_screen.dart';
import '../widgets/admin_guard.dart';
import 'auth_guard.dart';
import 'routes/blanks_routes.dart';
import 'routes/events_routes.dart';
import 'routes/expenses_routes.dart';
import 'routes/misc_routes.dart';
import 'routes/orders_routes.dart';
import 'routes/products_routes.dart';
import 'widgets/shell_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Router provider — listens to [authProvider] so that auth state changes
/// (login, logout, 401 handling) trigger the redirect guard without needing
/// a manual `router.refresh()`.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/orders',
    redirect: (context, state) => authRedirect(
        state, authState.status, authState.role,
        forcePasswordChange: authState.forcePasswordChange),
    routes: [
      // Login — full-screen, outside the shell (FR14/AC8).
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      // Password change — full-screen, outside the shell (DG-319 Phase 5 /
      // FR5 / FR9). Shared by the self-service (Settings → /change-password)
      // and forced-change (guard redirect when forcePasswordChange=true)
      // flows. The host screen is selected by the [ForceChangeScreen] vs
      // [PasswordChangeScreen] builder based on the auth state flag.
      GoRoute(
        path: '/change-password',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final force = ref.read(authProvider).forcePasswordChange;
          return force
              ? const ForceChangeScreen()
              : const PasswordChangeScreen();
        },
      ),
      // Admin access denied — shown when staff hit an admin-only route (FR16).
      GoRoute(
        path: adminAccessRoute,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AdminAccessScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ManagementDashboardScreen()),
          ),
          GoRoute(
            path: '/orders',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: OrderListScreen()),
          ),
          GoRoute(
            path: '/products',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProductCatalogScreen()),
          ),
          GoRoute(
            path: '/knowledge-base',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: KnowledgeBaseScreen()),
          ),
          GoRoute(
            path: '/events',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EventListScreen()),
          ),
          GoRoute(
            path: '/checklist',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ChecklistScreen()),
          ),
          GoRoute(
            path: '/cash-drawer',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: CashDrawerScreen()),
          ),
          GoRoute(
            path: '/knowledge',
            pageBuilder: (context, state) => NoTransitionPage(
              child: KnowledgeListScreen(
                initialType: state.uri.queryParameters['type'],
              ),
            ),
          ),
          GoRoute(
            path: '/pos',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PosScreen()),
          ),
        ],
      ),
      // Per-feature route modules (DG-308 Phase 4.2 / FR-FL-4).
      ...ordersRoutes(),
      ...productsRoutes(),
      ...eventsRoutes(),
      ...expensesRoutes(),
      ...blanksRoutes(),
      ...miscRoutes(),
    ],
  );
});