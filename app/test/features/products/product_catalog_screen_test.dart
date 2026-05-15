import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/category_service.dart';
import 'package:bakery_app/data/api/product_service.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/products/product_catalog_screen.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCategoryService extends CategoryService {
  _FakeCategoryService(this._categories) : super(Dio());

  final List<Category> _categories;

  @override
  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    return _categories;
  }
}

class _FakeProductService extends ProductService {
  _FakeProductService({
    required List<Product> activeProducts,
    required List<Product> inactiveProducts,
  }) : _activeProducts = List<Product>.from(activeProducts),
       _inactiveProducts = List<Product>.from(inactiveProducts),
       super(Dio());

  final List<Product> _activeProducts;
  final List<Product> _inactiveProducts;

  @override
  Future<List<Product>> listProducts({
    String? category,
    String? code,
    int active = 1,
    bool trungBay = false,
  }) async {
    final source = active == 0 ? _inactiveProducts : _activeProducts;
    if (category == null) {
      return List<Product>.from(source);
    }
    return source.where((product) => product.category == category).toList();
  }

  @override
  Future<Product> updateProduct(
    int id, {
    String? name,
    String? category,
    double? basePrice,
    double? cost,
    String? recipeNotes,
    int? active,
    String? productCode,
  }) async {
    final existing = _inactiveProducts.firstWhere(
      (product) => product.id == id,
      orElse: () => throw ArgumentError.value(
        id,
        'id',
        'Inactive product not found in test fake',
      ),
    );
    final updated = existing.copyWith(active: active ?? existing.active);
    _inactiveProducts.removeWhere((product) => product.id == id);
    _activeProducts.add(updated);
    return updated;
  }
}

GoRouter _buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductCatalogScreen(),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SizedBox()),
      GoRoute(
        path: '/categories/manage',
        builder: (context, state) => const SizedBox(),
      ),
      GoRoute(
        path: '/products/browse',
        builder: (context, state) => const SizedBox(),
      ),
      GoRoute(
        path: '/products/new',
        builder: (context, state) => const SizedBox(),
      ),
      GoRoute(
        path: '/products/:id/edit',
        builder: (context, state) => const SizedBox(),
      ),
    ],
    initialLocation: '/products',
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeProductService productService,
  required _FakeCategoryService categoryService,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        productServiceProvider.overrideWithValue(productService),
        categoryServiceProvider.overrideWithValue(categoryService),
      ],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows inactive section below active content', (tester) async {
    final productService = _FakeProductService(
      activeProducts: const [
        Product(id: 1, name: 'Banh kem dau', category: 'banh_kem', active: 1),
      ],
      inactiveProducts: const [
        Product(id: 2, name: 'Banh kem cu', category: 'banh_kem', active: 0),
      ],
    );
    final categoryService = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'banh_kem',
        name: 'Banh kem',
        codePrefix: 'BK',
        active: 1,
      ),
    ]);

    await _pumpScreen(
      tester,
      productService: productService,
      categoryService: categoryService,
    );

    expect(find.text('Banh kem dau'), findsOneWidget);
    expect(find.text(VN.hiddenProducts), findsOneWidget);
    expect(find.text('Banh kem cu'), findsOneWidget);
    expect(find.text(VN.showProduct), findsOneWidget);

    final activeY = tester.getCenter(find.text('Banh kem dau')).dy;
    final hiddenHeaderY = tester.getCenter(find.text(VN.hiddenProducts)).dy;
    expect(hiddenHeaderY, greaterThan(activeY));
  });

  testWidgets('reactivate action moves inactive product to active state', (
    tester,
  ) async {
    final productService = _FakeProductService(
      activeProducts: const [
        Product(id: 1, name: 'Banh kem dau', category: 'banh_kem', active: 1),
      ],
      inactiveProducts: const [
        Product(id: 2, name: 'Banh kem cu', category: 'banh_kem', active: 0),
      ],
    );
    final categoryService = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'banh_kem',
        name: 'Banh kem',
        codePrefix: 'BK',
        active: 1,
      ),
    ]);

    await _pumpScreen(
      tester,
      productService: productService,
      categoryService: categoryService,
    );

    await tester.tap(find.text(VN.showProduct));
    await tester.pumpAndSettle();

    expect(find.text(VN.hiddenProducts), findsNothing);
    expect(find.text('Banh kem cu'), findsOneWidget);
  });
}
