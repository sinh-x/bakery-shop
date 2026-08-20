// DG-358 Phase 4 — chip stock display in WorkItemEditCard.
// ignore_for_file: prefer_const_declarations  // DG-138#todo: per-line suppressions after const declaration audit
import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/features/orders/order_edit/widgets/work_item_edit_card.dart';
import 'package:bakery_app/data/providers/products_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Product _productWithChips({
  required int? stockQty,
  required List<PriceChip> priceChips,
  double basePrice = 200000,
  Map<String, String> attributes = const {},
}) {
  return Product(
    id: 1,
    name: 'Bánh test',
    category: 'cake',
    basePrice: basePrice,
    priceChips: priceChips,
    stockQty: stockQty,
    attributes: attributes,
  );
}

WorkItem _workItem(Product product) {
  return WorkItem(
    id: '10',
    orderId: 'ORD-1',
    productId: '${product.id}',
    productName: product.name,
    unitPrice: product.basePrice,
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  WorkItem item,
  List<Product> products,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productsProvider.overrideWith(() => _FakeProductsNotifier(products)),
        apiBaseUrlProvider.overrideWith(() => _FakeApiBaseUrlNotifier('http://test.local')),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkItemEditCard(orderRef: 'ORD-1', item: item),
          ),
        ),
      ),
    ),
  );
  // productsProvider is an async notifier; let its future resolve so
  // _findProduct() returns a product and the chip section renders.
  await tester.pumpAndSettle();
}

class _FakeProductsNotifier extends ProductsNotifier {
  _FakeProductsNotifier(this._products);
  final List<Product> _products;

  @override
  Future<List<Product>> build() async => _products;
}

class _FakeApiBaseUrlNotifier extends ApiBaseUrlNotifier {
  _FakeApiBaseUrlNotifier(this._url);
  final String _url;

  @override
  String build() => _url;
}

void main() {
  group('DG-358 Phase 4: WorkItemEditCard chip stock labels', () {
    testWidgets(
      'FR2/AC2: base-price chip label shows merged stock (chip stock + base stock)',
      (tester) async {
        // Product total stock = 20. Chip "Nhỏ" (base price 200000) has 5
        // chip-specific stock. Base (unassigned) stock = 20 - 5 - 8 = 7.
        // Expected merged display for "Nhỏ" = 5 + 7 = 12.
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000, stockQty: 5),
          PriceChip(id: 2, label: 'Lớn', price: 400000, stockQty: 8),
        ];
        final product = _productWithChips(
          stockQty: 20,
          priceChips: priceChips,
          basePrice: 200000,
        );
        final item = _workItem(product);

        await _pumpCard(tester, item, [product]);

        // Base-price chip "Nhỏ" should show merged stock (12), not raw (5).
        expect(
          find.widgetWithText(ChoiceChip, 'Nhỏ · 200.000đ (12)'),
          findsOneWidget,
        );
        // Non-base-price chip "Lớn" should show raw stock (8) only.
        expect(
          find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ (8)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'FR4/AC3: non-base-price chip shows raw per-chip stock only (no merge)',
      (tester) async {
        // Product total stock = 30. Both chips are non-base-price (300000,
        // 400000; base price is 200000). No chip qualifies for merge.
        final priceChips = const [
          PriceChip(id: 10, label: 'Vừa', price: 300000, stockQty: 4),
          PriceChip(id: 11, label: 'Lớn', price: 400000, stockQty: 9),
        ];
        final product = _productWithChips(
          stockQty: 30,
          priceChips: priceChips,
          basePrice: 200000,
        );
        final item = _workItem(product);

        await _pumpCard(tester, item, [product]);

        expect(
          find.widgetWithText(ChoiceChip, 'Vừa · 300.000đ (4)'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ (9)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'no stock label rendered when display stock is zero',
      (tester) async {
        // Product stockQty null, chips have no stockQty. displayStock = 0
        // for both → no "(N)" suffix appended.
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000),
          PriceChip(id: 2, label: 'Lớn', price: 400000),
        ];
        final product = _productWithChips(
          stockQty: null,
          priceChips: priceChips,
          basePrice: 200000,
        );
        final item = _workItem(product);

        await _pumpCard(tester, item, [product]);

        expect(find.widgetWithText(ChoiceChip, 'Nhỏ · 200.000đ'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ'), findsOneWidget);
        // No chip label carries a stock suffix.
        expect(find.textContaining('(0)'), findsNothing);
      },
    );
  });
}
