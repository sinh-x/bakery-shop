import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/widgets/pos_product_grid.dart';
import 'package:bakery_app/features/pos/pos_screen.dart';
import 'package:bakery_app/providers/categories_provider.dart';
import 'package:bakery_app/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
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
      basePrice: 25000,
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
      stockQty: 0,
    ),
    const Product(
      id: 3,
      name: 'Tra dao',
      category: 'nuoc',
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 10,
    ),
    const Product(
      id: 4,
      name: 'Matcha da xay',
      category: 'nuoc',
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: null,
    ),
    const Product(
      id: 5,
      name: 'Banh kem chip',
      category: 'banh_kem',
      basePrice: 130000,
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 10,
      priceChips: <PriceChip>[
        PriceChip(id: 15, label: '130', price: 130000, stockQty: 0),
        PriceChip(id: 16, label: '140', price: 140000, stockQty: 2),
      ],
    ),
    const Product(
      id: 6,
      name: 'Banh kem base option',
      category: 'banh_kem',
      basePrice: 120000,
      active: 1,
      attributes: {'trung_bay': 'true'},
      stockQty: 3,
      priceChips: <PriceChip>[
        PriceChip(id: 17, label: '130', price: 130000, stockQty: 0),
        PriceChip(id: 18, label: '140', price: 140000, stockQty: 2),
      ],
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

  testWidgets('hides zero and null stock products by default', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    expect(find.text('Kem dau'), findsOneWidget);
    expect(find.text('Su kem'), findsNothing);

    expect(find.text('Nuoc'), findsNothing);
    expect(find.text('Matcha da xay'), findsNothing);
  });

  testWidgets('shows out-of-stock products when switch is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'su kem');
    await tester.pumpAndSettle();
    expect(find.text('Su kem'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'matcha');
    await tester.pumpAndSettle();
    expect(find.text('Matcha da xay'), findsOneWidget);
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

  testWidgets('search respects stock visibility switch', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'su kem');
    await tester.pumpAndSettle();
    expect(find.text('Su kem'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'su kem');
    await tester.pumpAndSettle();
    expect(find.text('Su kem'), findsOneWidget);
  });

  testWidgets('renders stock visibility switch with VN label', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text(VN.showOutOfStockProducts), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets(
    'in-stock add updates cart bar and badge without success overlay',
    (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Banh kem'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Kem dau'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kem dau'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('đã thêm vào giỏ'), findsNothing);
      expect(find.text('x1'), findsOneWidget);
      expect(find.text(formatVND(25000)), findsWidgets);
    },
  );

  test('same-price chip uses base stock bucket for POS display', () {
    final product = products.singleWhere((p) => p.id == 5);
    final chip130 = product.priceChips[0];
    final chip140 = product.priceChips[1];

    expect(posBaseStockQty(product), 8);
    expect(posBackendChipIdForSelection(product, chip130), isNull);
    expect(posChipDisplayStockQty(product, chip130), 8);
    expect(posBackendChipIdForSelection(product, chip140), 16);
    expect(posChipDisplayStockQty(product, chip140), 2);
  });

  testWidgets('chip picker shows per-option stock counts', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Banh kem chip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banh kem chip'));
    await tester.pumpAndSettle();

    expect(find.text('130 · ${formatVND(130000)}'), findsOneWidget);
    expect(find.text(VN.availableStock(8)), findsOneWidget);
    expect(find.text('140 · ${formatVND(140000)}'), findsOneWidget);
    expect(find.text(VN.lowStock(2)), findsOneWidget);
  });

  testWidgets('chip picker hides out-of-stock chips by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Banh kem base option'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banh kem base option'));
    await tester.pumpAndSettle();

    expect(find.text('${VN.giaCoSo} · ${formatVND(120000)}'), findsOneWidget);
    expect(find.text(VN.lowStock(1)), findsOneWidget);
    expect(find.text('130 · ${formatVND(130000)}'), findsNothing);
    expect(find.text('140 · ${formatVND(140000)}'), findsOneWidget);
    expect(find.text(VN.lowStock(2)), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text(formatVND(120000)), findsWidgets);
    expect(find.text(VN.sanPhamHetHang), findsNothing);
  });

  testWidgets('chip picker shows out-of-stock chips when switch is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Banh kem base option'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banh kem base option'));
    await tester.pumpAndSettle();

    expect(find.text('130 · ${formatVND(130000)}'), findsOneWidget);
    expect(find.text(VN.outOfStock), findsWidgets);
  });
}
