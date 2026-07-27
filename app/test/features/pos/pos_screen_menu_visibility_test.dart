import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/pos_screen.dart';
import 'package:bakery_app/providers/categories_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/login_screen_test_helpers.dart';

class _TestCategoriesNotifier extends CategoriesNotifier {
  _TestCategoriesNotifier(this._categories);

  final List<Category> _categories;

  @override
  Future<List<Category>> build() async => _categories;
}

class _TestProductsNotifier extends ProductsNotifier {
  _TestProductsNotifier(this._products);

  final List<Product> _products;

  @override
  Future<List<Product>> build() async => _products;
}

/// DG-264 Phase 3 — verifies the POS overflow menu shows reconciliation
/// entries for all authenticated roles (staff and admin) and that tapping
/// a reconciliation entry navigates to the correct route.
void main() {
  final categories = <Category>[
    const Category(
      id: 1,
      slug: 'banh_kem',
      name: 'Banh kem',
      codePrefix: 'BK',
      active: 1,
      position: 1,
    ),
  ];

  final products = <Product>[
    const Product(
      id: 1,
      name: 'Kem dau',
      basePrice: 25000,
      category: 'banh_kem',
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 5,
    ),
  ];

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildScreen({required String role}) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const PosScreen()),
        GoRoute(
          path: '/stock/reconciliation',
          builder: (context, state) =>
              const Scaffold(body: Text('reconciliation-route')),
        ),
        GoRoute(
          path: '/stock/reconciliation/history',
          builder: (context, state) =>
              const Scaffold(body: Text('reconciliation-history-route')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        categoriesProvider.overrideWith(
          () => _TestCategoriesNotifier(categories),
        ),
        productsProvider.overrideWith(() => _TestProductsNotifier(products)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Seeds [prefs] with a valid auth session for the given [role] so the
  /// test environment reflects an authenticated staff/admin user. The POS
  /// screen itself no longer reads the auth role (Phase 1 removed the
  /// `isAdmin` gate), but seeding keeps the test representative of an
  /// authenticated session.
  Future<void> seedRole(String role) async {
    final token = buildJwt({
      'sub': role == 'admin' ? 'Sinh' : 'An',
      'role': role,
      'exp': 9999999999,
      'jti': 'test-jti-$role',
    });
    prefs.setString('auth_token', token);
    prefs.setString('auth_username', role == 'admin' ? 'Sinh' : 'An');
    prefs.setString('auth_role', role);
  }

  group('DG-264 Phase 3 — POS overflow menu visibility', () {
    testWidgets(
      'AC1: staff sees reconciliation menu items on POS overflow menu',
      (tester) async {
        await seedRole('staff');
        await tester.pumpWidget(buildScreen(role: 'staff'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip(VN.moreActions));
        await tester.pumpAndSettle();

        expect(find.text(VN.openStockReconciliation), findsOneWidget);
        expect(find.text(VN.openStockReconciliationHistory), findsOneWidget);
      },
    );

    testWidgets(
      'AC4: admin still sees reconciliation menu items on POS overflow menu (no regression)',
      (tester) async {
        await seedRole('admin');
        await tester.pumpWidget(buildScreen(role: 'admin'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip(VN.moreActions));
        await tester.pumpAndSettle();

        expect(find.text(VN.openStockReconciliation), findsOneWidget);
        expect(find.text(VN.openStockReconciliationHistory), findsOneWidget);
      },
    );

    testWidgets(
      'AC3: tapping "Đối soát tồn kho hôm nay" navigates to /stock/reconciliation',
      (tester) async {
        await seedRole('staff');
        await tester.pumpWidget(buildScreen(role: 'staff'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip(VN.moreActions));
        await tester.pumpAndSettle();

        await tester.tap(find.text(VN.openStockReconciliation));
        await tester.pumpAndSettle();

        expect(find.text('reconciliation-route'), findsOneWidget);
      },
    );

    testWidgets(
      'AC3: tapping "Lịch sử đối soát tồn kho" navigates to /stock/reconciliation/history',
      (tester) async {
        await seedRole('staff');
        await tester.pumpWidget(buildScreen(role: 'staff'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip(VN.moreActions));
        await tester.pumpAndSettle();

        await tester.tap(find.text(VN.openStockReconciliationHistory));
        await tester.pumpAndSettle();

        expect(find.text('reconciliation-history-route'), findsOneWidget);
      },
    );
  });
}