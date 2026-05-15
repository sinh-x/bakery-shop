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

void main() {
  test('builds cache-busted stock product photo URL', () {
    expect(
      stockProductPhotoUrl('http://localhost:8000', 9, cacheBuster: '11'),
      'http://localhost:8000/api/products/9/photo?v=11',
    );
  });

  GoRouter buildRouter() {
    return GoRouter(
      routes: [
        GoRoute(
          path: '/stock',
          builder: (context, state) => const StockScreen(),
        ),
      ],
      initialLocation: '/stock',
    );
  }

  testWidgets('groups by category with collapsed sections by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final stockService = _FakeStockService([
      StockOverviewItem(
        productId: 1,
        productName: 'Bánh dâu',
        category: 'banh_kem',
        quantity: 5,
        basePrice: 100000,
        perChip: const [],
      ),
      StockOverviewItem(
        productId: 2,
        productName: 'Nến số',
        category: 'phu_kien',
        quantity: 2,
        basePrice: 5000,
        perChip: const [],
      ),
    ]);
    final categoryService = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'phu_kien',
        name: 'Phụ kiện',
        codePrefix: 'PK',
        active: 1,
        position: 1,
      ),
      Category(
        id: 2,
        slug: 'banh_kem',
        name: 'Bánh kem',
        codePrefix: 'BK',
        active: 1,
        position: 2,
      ),
    ]);

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

    expect(find.text('Phụ kiện'), findsOneWidget);
    expect(find.text('Bánh kem'), findsOneWidget);
    expect(find.text('Nến số'), findsNothing);
    expect(find.text('Bánh dâu'), findsNothing);

    await tester.tap(find.text('Phụ kiện'));
    await tester.pumpAndSettle();
    expect(find.text('Nến số'), findsOneWidget);
    expect(find.text(VN.nhapHang), findsOneWidget);
    expect(find.text(VN.haoHut), findsOneWidget);
    expect(find.text(VN.dieuChinh), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(find.byIcon(Icons.remove), findsWidgets);
    expect(find.byIcon(Icons.edit), findsWidgets);
  });
}
