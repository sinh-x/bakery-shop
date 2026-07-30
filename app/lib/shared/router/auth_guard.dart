import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';

/// Auth-redirect guard (FR14/FR15, AC8/AC9).
///
/// - When the auth state is `unauthenticated`, any route other than `/login`
///   redirects to `/login`.
/// - When the auth state is `authenticated`, `/login` redirects to `/orders`
///   (the main shell).
/// - While the auth state is `unknown` (initial boot, before the notifier has
///   resolved the stored token) the guard does nothing — the splash/loading
///   state is owned by the `/login` route's initial frame.
///
/// Role-based gating (FR16/AC10/AC11): when authenticated, staff users are
/// blocked from the admin-only routes listed in [adminOnlyRoutes]. They are
/// redirected to the dedicated [adminAccessRoute] page so deep links do not
/// silently land on a blank screen. Admin users pass through unaffected.
String? authRedirect(GoRouterState state, AuthStatus status, String? role) {
  final location = state.uri.path;
  final onLogin = location == '/login';
  switch (status) {
    case AuthStatus.authenticated:
      if (onLogin) return '/orders';
      if (role != 'admin' && isAdminOnlyRoute(location)) {
        return adminAccessRoute;
      }
      return null;
    case AuthStatus.unauthenticated:
      return onLogin ? null : '/login';
    case AuthStatus.unknown:
      return null;
  }
}

/// Admin-only routes (FR16). Staff users are redirected away from these.
///
/// NOTE: `/audit-log` is wired to the real filterable audit log screen as of
/// Phase 8 (FR24/AC20); the route itself was already admin-gated in Phase 7.
///
/// DG-029 Phase 5.6 follow-up Item 3 (Sinh-approved 2026-07-14):
/// `/stock/reconciliation` and `/stock/reconciliation/history` were removed
/// from this set so STAFF can now reach the reconciliation screen and
/// submit (backend submit gate was also removed). History is reachable
/// because the reconciliation screen links to it.
const Set<String> adminOnlyRoutes = {
  '/checklist/config',
  '/categories/manage',
  '/audit-log',
  '/customers/duplicates',
};

/// Match admin-only routes that take path parameters (e.g.
/// `/stock/reconciliation/history/123`). Prefix match is used for those.
bool isAdminOnlyRoute(String location) {
  if (adminOnlyRoutes.contains(location)) return true;
  for (final route in adminOnlyRoutes) {
    if (location.startsWith('$route/')) return true;
  }
  return false;
}

const String adminAccessRoute = '/admin-access';