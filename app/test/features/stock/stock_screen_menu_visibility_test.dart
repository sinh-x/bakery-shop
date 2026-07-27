import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/category_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/features/stock/stock_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/login_screen_test_helpers.dart';

class _FakeStockService extends StockService {
  _FakeStockService(this._items) : super(Dio());

  final List<StockOverviewItem> _items;

  @override
  Future<List<StockOverviewItem>> getStockOverview() async => _items;
}

class _FakeCategoryService extends CategoryService {
  _FakeCategoryService(this._categories) : super(Dio());

  final List<Category> _categories;

  @override
  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    return _categories;
  }
}

/// DG-264 Phase 3 — verifies the Stock screen overflow menu shows
/// reconciliation entries for all authenticated roles (staff and admin) and
/// that tapping a reconciliation entry navigates to the correct route.
void main() {
  late SharedPreferences prefs;
  late _FakeCategoryService categoryService;
  late _FakeStockService stockService;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    stockService = _FakeStockService([
      StockOverviewItem(
        productId: 1,
        productName: 'Bánh dâu',
        category: 'banh_kem',
        quantity: 5,
        basePrice: 100000,
        perChip: const [],
      ),
    ]);
    categoryService = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'banh_kem',
        name: 'Bánh kem',
        codePrefix: 'BK',
        active: 1,
        position: 1,
      ),
    ]);
  });

  GoRouter buildRouter() {
    return GoRouter(
      routes: [
        GoRoute(
          path: '/stock',
          builder: (context, state) => const StockScreen(),
        ),
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
      initialLocation: '/stock',
    );
  }

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

  group('DG-264 Phase 3 — Stock overflow menu visibility', () {
    testWidgets(
      'AC2: staff sees reconciliation menu items on Stock overflow menu',
      (tester) async {
        await seedRole('staff');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              stockServiceProvider.overrideWithValue(stockService),
              categoryServiceProvider.overrideWithValue(categoryService),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip(VN.moreActions));
        await tester.pumpAndSettle();

        expect(find.text(VN.openStockReconciliation), findsOneWidget);
        expect(find.text(VN.openStockReconciliationHistory), findsOneWidget);
      },
    );

    testWidgets(
      'AC4: admin still sees reconciliation menu items on Stock overflow menu (no regression)',
      (tester) async {
        await seedRole('admin');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              stockServiceProvider.overrideWithValue(stockService),
              categoryServiceProvider.overrideWithValue(categoryService),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
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
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              stockServiceProvider.overrideWithValue(stockService),
              categoryServiceProvider.overrideWithValue(categoryService),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
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
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              stockServiceProvider.overrideWithValue(stockService),
              categoryServiceProvider.overrideWithValue(categoryService),
            ],
            child: MaterialApp.router(routerConfig: buildRouter()),
          ),
        );
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