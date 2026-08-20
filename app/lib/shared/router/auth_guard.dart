import 'package:go_router/go_router.dart';

import '../../shared/providers/auth_provider.dart';

/// Auth-redirect guard (FR14/FR15, AC8/AC9, DG-319 Phase 5 force-change AC7).
///
/// - When the auth state is `unauthenticated`, any route other than the ones
///   in [unauthenticatedRoutes] redirects to `/login`.
/// - When the auth state is `authenticated`, `/login` redirects to `/orders`
///   (the main shell).
/// - When the auth state is `authenticated` with `forcePasswordChange=true`,
///   any route other than `/change-password` redirects to `/change-password`
///   so the user must change their password before accessing the app (FR9 /
///   AC7). `/login` is excluded by the unauthenticated guard above (a forced
///   user still has a valid token, so this branch runs), but a forced user
///   tapping the back button to `/login` is redirected to `/change-password`,
///   not `/orders` — the change must happen first.
/// - While the auth state is `unknown` (initial boot, before the notifier has
///   resolved the stored token) the guard does nothing — the splash/loading
///   state is owned by the `/login` route's initial frame.
///
/// Role-based gating (FR16/AC10/AC11): when authenticated, staff users are
/// blocked from the admin-only routes listed in [adminOnlyRoutes]. They are
/// redirected to the dedicated [adminAccessRoute] page so deep links do not
/// silently land on a blank screen. Admin users pass through unaffected.
String? authRedirect(
  GoRouterState state,
  AuthStatus status,
  String? role, {
  bool forcePasswordChange = false,
}) {
  final location = state.uri.path;
  final onLogin = location == '/login';
  final onChangePassword = location == '/change-password';
  switch (status) {
    case AuthStatus.authenticated:
      // FR9/AC7: force-change redirects before any app access. The
      // `/change-password` route builder picks ForceChangeScreen vs
      // PasswordChangeScreen based on this same flag, so the user lands on
      // the forced-change UI rather than the self-service form.
      if (forcePasswordChange && !onChangePassword) {
        return '/change-password';
      }
      if (onLogin) return '/orders';
      if (role != 'admin' && isAdminOnlyRoute(location)) {
        return adminAccessRoute;
      }
      return null;
    case AuthStatus.unauthenticated:
      return unauthenticatedRoutes.contains(location) ? null : '/login';
    case AuthStatus.unknown:
      return null;
  }
}

/// Routes an unauthenticated user may access without being redirected to
/// `/login` (DG-367 Phase 1 / FR4 / AC5). `/login` is the original member;
/// `/settings/connection` is the pre-login technical settings route so users
/// can fix a broken server URL before authenticating.
const Set<String> unauthenticatedRoutes = {
  '/login',
  '/settings/connection',
};

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