import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/pos_screen.dart';
import 'package:bakery_app/providers/categories_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    const Category(
      id: 2,
      slug: 'nuoc',
      name: 'Nuoc',
      codePrefix: 'N',
      active: 1,
      position: 2,
    ),
  ];

  final products = <Product>[
    const Product(
      id: 1,
      name: 'Kem dau',
      category: 'banh_kem',
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 5,
    ),
    const Product(
      id: 2,
      name: 'Su kem',
      category: 'banh_kem',
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 2,
    ),
    const Product(
      id: 3,
      name: 'Tra dao',
      category: 'nuoc',
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 10,
    ),
  ];

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildScreen() {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const PosScreen()),
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

  testWidgets('removes category filter chips and starts sections collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Banh kem'), findsOneWidget);
    expect(find.text('Nuoc'), findsOneWidget);
    expect(find.text('Kem dau'), findsNothing);
    expect(find.text('Tra dao'), findsNothing);
  });

  testWidgets('expands and collapses section on header tap', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    expect(find.text('Kem dau'), findsOneWidget);

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    expect(find.text('Kem dau'), findsNothing);
  });

  testWidgets('search expands matching sections and hides non-matching', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tra');
    await tester.pumpAndSettle();

    expect(find.text('Nuoc'), findsOneWidget);
    expect(find.text('Banh kem'), findsNothing);
    expect(find.text('Tra dao'), findsOneWidget);
  });
}
