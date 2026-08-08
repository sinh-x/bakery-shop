import 'package:bakery_app/features/auth/auth_provider.dart';
import 'package:bakery_app/shared/router/auth_guard.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Minimal fake [GoRouterState] — only the bits [authRedirect] touches
/// (the `uri.path` accessor). go_router's constructor requires a full
/// configuration, so we borrow a throwaway [GoRouter]'s `configuration`.
GoRouterState _stateFor(String path) {
  final uri = Uri.parse(path);
  final router = GoRouter(routes: const <RouteBase>[]);
  return GoRouterState(
    router.configuration,
    uri: uri,
    matchedLocation: path,
    fullPath: path,
    pathParameters: const <String, String>{},
    pageKey: const ValueKey<String>('test'),
  );
}

void main() {
  group('authRedirect force-change (DG-319 Phase 5 / FR9 / AC7)', () {
    test('authenticated + forcePasswordChange redirects to /change-password',
        () {
      final state = _stateFor('/orders');
      final result = authRedirect(
        state,
        AuthStatus.authenticated,
        'staff',
        forcePasswordChange: true,
      );
      expect(result, '/change-password');
    });

    test('authenticated + forcePasswordChange stays on /change-password', () {
      final state = _stateFor('/change-password');
      final result = authRedirect(
        state,
        AuthStatus.authenticated,
        'staff',
        forcePasswordChange: true,
      );
      expect(result, isNull);
    });

    test('authenticated + forcePasswordChange true overrides /login redirect',
        () {
      // A forced user tapping back to /login should NOT go to /orders; they
      // must change first. The guard redirects to /change-password instead.
      final state = _stateFor('/login');
      final result = authRedirect(
        state,
        AuthStatus.authenticated,
        'staff',
        forcePasswordChange: true,
      );
      expect(result, '/change-password');
    });

    test('authenticated without force flag passes through to /orders', () {
      final state = _stateFor('/orders');
      final result = authRedirect(
        state,
        AuthStatus.authenticated,
        'staff',
        forcePasswordChange: false,
      );
      expect(result, isNull);
    });

    test('unauthenticated still redirects to /login regardless of force flag',
        () {
      final state = _stateFor('/orders');
      final result = authRedirect(
        state,
        AuthStatus.unauthenticated,
        null,
        forcePasswordChange: false,
      );
      expect(result, '/login');
    });

    test('authenticated admin on /login redirects to /orders (no force)', () {
      final state = _stateFor('/login');
      final result = authRedirect(
        state,
        AuthStatus.authenticated,
        'admin',
        forcePasswordChange: false,
      );
      expect(result, '/orders');
    });

    test('unknown status does nothing', () {
      final state = _stateFor('/orders');
      final result = authRedirect(
        state,
        AuthStatus.unknown,
        null,
        forcePasswordChange: false,
      );
      expect(result, isNull);
    });
  });

  group('authRedirect pre-login settings (DG-367 Phase 1 / FR4 / AC5)', () {
    test('unauthenticated on /settings/connection is allowed (no redirect)',
        () {
      final state = _stateFor('/settings/connection');
      final result = authRedirect(
        state,
        AuthStatus.unauthenticated,
        null,
        forcePasswordChange: false,
      );
      expect(result, isNull);
    });

    test('unauthenticated on /login still allowed', () {
      final state = _stateFor('/login');
      final result = authRedirect(
        state,
        AuthStatus.unauthenticated,
        null,
        forcePasswordChange: false,
      );
      expect(result, isNull);
    });

    test('unauthenticated on other route still redirects to /login', () {
      final state = _stateFor('/orders');
      final result = authRedirect(
        state,
        AuthStatus.unauthenticated,
        null,
        forcePasswordChange: false,
      );
      expect(result, '/login');
    });

    test('authenticated on /settings/connection passes through (not /login)',
        () {
      // An authenticated user opening the pre-login settings route should not
      // be bounced — it is a valid route, just not the /login redirect.
      final state = _stateFor('/settings/connection');
      final result = authRedirect(
        state,
        AuthStatus.authenticated,
        'admin',
        forcePasswordChange: false,
      );
      expect(result, isNull);
    });
  });
}
