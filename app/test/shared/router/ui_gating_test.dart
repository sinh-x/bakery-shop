import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/shared/router/app_router.dart';
import 'package:bakery_app/shared/widgets/admin_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/login_screen_test_helpers.dart';

/// Helper to build a ProviderContainer seeded with the given role.
ProviderContainer _container(SharedPreferences prefs, {String role = 'staff'}) {
  final token = buildJwt({
    'sub': role == 'admin' ? 'Sinh' : 'An',
    'role': role,
    'exp': 9999999999,
    'jti': 'test-jti-$role',
  });
  prefs.setString('auth_token', token);
  prefs.setString('auth_username', role == 'admin' ? 'Sinh' : 'An');
  prefs.setString('auth_role', role);
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AdminOnly widget (FR16)', () {
    testWidgets('renders child when admin', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = _container(prefs, role: 'admin');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AdminOnly(child: Text('ADMIN_SECRET')),
          ),
        ),
      );
      expect(find.text('ADMIN_SECRET'), findsOneWidget);
    });

    testWidgets('hides child when staff', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = _container(prefs, role: 'staff');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AdminOnly(child: Text('ADMIN_SECRET')),
          ),
        ),
      );
      expect(find.text('ADMIN_SECRET'), findsNothing);
    });
  });

  group('Router role redirect guard (FR16/AC10/AC11)', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    Widget buildApp(ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      );
    }

    testWidgets('staff is redirected from /checklist/config to /admin-access',
        (tester) async {
      final container = _container(prefs, role: 'staff');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      // Try navigating to a gated route.
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/checklist/config');
      await tester.pumpAndSettle();
      expect(
        find.text(VNForTest.accessDeniedTitle),
        findsWidgets,
      );
    });

    testWidgets('staff is redirected from /categories/manage to /admin-access',
        (tester) async {
      final container = _container(prefs, role: 'staff');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/categories/manage');
      await tester.pumpAndSettle();
      expect(find.text(VNForTest.accessDeniedTitle), findsWidgets);
    });

    testWidgets(
        'staff is redirected from /stock/reconciliation to /admin-access',
        (tester) async {
      final container = _container(prefs, role: 'staff');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/stock/reconciliation');
      await tester.pumpAndSettle();
      expect(find.text(VNForTest.accessDeniedTitle), findsWidgets);
    });

    testWidgets('staff is redirected from /audit-log to /admin-access',
        (tester) async {
      final container = _container(prefs, role: 'staff');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/audit-log');
      await tester.pumpAndSettle();
      expect(find.text(VNForTest.accessDeniedTitle), findsWidgets);
    });

    testWidgets('staff is redirected from /stock/reconciliation/history/:id',
        (tester) async {
      final container = _container(prefs, role: 'staff');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/stock/reconciliation/history/123');
      await tester.pumpAndSettle();
      expect(find.text(VNForTest.accessDeniedTitle), findsWidgets);
    });

    testWidgets('admin can reach /checklist/config (not redirected)',
        (tester) async {
      final container = _container(prefs, role: 'admin');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/checklist/config');
      await tester.pumpAndSettle();
      expect(find.text(VNForTest.accessDeniedTitle), findsNothing);
    });

    testWidgets('admin can reach /audit-log placeholder (AC11)',
        (tester) async {
      final container = _container(prefs, role: 'admin');
      await tester.pumpWidget(buildApp(container));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/audit-log');
      await tester.pumpAndSettle();
      expect(find.text(VNForTest.openAuditLog), findsWidgets);
    });
  });
}

/// Local VN label mirror so the test does not depend on the full VN class
/// surface — only the two labels exercised by the gating UI.
class VNForTest {
  static const accessDeniedTitle = 'Không có quyền truy cập';
  static const openAuditLog = 'Nhật ký thay đổi';
}