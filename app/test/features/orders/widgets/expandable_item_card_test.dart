// DG-358 Phase 3 — chip stock display in ExpandableItemCard.
// ignore_for_file: prefer_const_declarations  // DG-138#todo: per-line suppressions after const declaration audit
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/expandable_item_card.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'package:flutter/material.dart';
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

Future<void> _pumpCard(
  WidgetTester tester,
  DraftOrderItem item, {
  VoidCallback? onStateChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpandableItemCard(
            item: item,
            onRemove: () {},
            onQtyChanged: (_) {},
            onStateChanged: onStateChanged ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('DG-358 Phase 3: ExpandableItemCard chip stock labels', () {
    testWidgets(
      'FR1/AC1: base-price chip label shows merged stock (chip stock + base stock)',
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
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

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
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

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
      'FR3: _stockInlineText shows merged stock when base-price chip selected',
      (tester) async {
        // Trưng bày product so the useInventory toggle + _stockInlineText
        // subtitle render. Total stock = 15. Base-price chip "Nhỏ" stock = 3.
        // Base (unassigned) stock = 15 - 3 - 6 = 6. Merged = 3 + 6 = 9.
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000, stockQty: 3),
          PriceChip(id: 2, label: 'Lớn', price: 400000, stockQty: 6),
        ];
        final product = _productWithChips(
          stockQty: 15,
          priceChips: priceChips,
          basePrice: 200000,
          attributes: const {'trung_bay': 'true'},
        );
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

        // Select the base-price chip "Nhỏ".
        await tester.tap(find.widgetWithText(ChoiceChip, 'Nhỏ · 200.000đ (9)'));
        await tester.pump();

        expect(item.priceChipId, 1);

        // Enable the useInventory toggle so _stockInlineText subtitle appears.
        await tester.tap(find.text(StockLabels.useInventory));
        await tester.pump();

        // _stockInlineText should show merged stock (9), not raw (3).
        expect(find.text('${StockLabels.stockRemaining}: 9'), findsOneWidget);
      },
    );

    testWidgets(
      'FR3: _stockInlineText shows raw stock when non-base-price chip selected',
      (tester) async {
        // Same product as above. Selecting non-base-price "Lớn" (stock 6)
        // should show raw stock only (no merge).
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000, stockQty: 3),
          PriceChip(id: 2, label: 'Lớn', price: 400000, stockQty: 6),
        ];
        final product = _productWithChips(
          stockQty: 15,
          priceChips: priceChips,
          basePrice: 200000,
          attributes: const {'trung_bay': 'true'},
        );
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

        // Select non-base-price chip "Lớn".
        await tester.tap(find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ (6)'));
        await tester.pump();

        expect(item.priceChipId, 2);

        // Enable useInventory toggle to surface _stockInlineText.
        await tester.tap(find.text(StockLabels.useInventory));
        await tester.pump();

        // Raw chip stock (6) shown — no merge for non-base-price chips.
        expect(find.text('${StockLabels.stockRemaining}: 6'), findsOneWidget);
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
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

        expect(find.widgetWithText(ChoiceChip, 'Nhỏ · 200.000đ'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ'), findsOneWidget);
        // No chip label carries a stock suffix.
        expect(find.textContaining('(0)'), findsNothing);
      },
    );
  });
}
