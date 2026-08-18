// ignore_for_file: prefer_const_declarations  // DG-138#todo: replace with per-line suppressions after const declaration audit
import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/expandable_item_card.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';

const _nhanBanhAttribute = EnumAttribute(
  attributeType: 'nhan_banh',
  labelVi: 'Nhân bánh',
  defaultOptionId: 3,
  options: [
    EnumOption(id: 1, valueVi: 'Sầu riêng'),
    EnumOption(id: 2, valueVi: 'Sô-cô-la'),
    EnumOption(id: 3, valueVi: 'Việt quất', isDefault: true),
    EnumOption(id: 4, valueVi: 'Chanh dây'),
    EnumOption(id: 5, valueVi: 'Dâu'),
  ],
);

Product _productWithEnum({
  List<EnumAttribute> enums = const [_nhanBanhAttribute],
  List<PriceChip> priceChips = const [],
}) {
  return Product(
    id: 100,
    name: 'Bánh kem',
    category: 'cake',
    basePrice: 200000,
    priceChips: priceChips,
    enumAttributes: enums,
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
  group('ExpandableItemCard enum chips', () {
    testWidgets(
      'AC-2: renders label + 5 chips with default pre-selected',
      (tester) async {
        final item = DraftOrderItem(product: _productWithEnum());

        await _pumpCard(tester, item);

        expect(find.text('Nhân bánh'), findsOneWidget);

        for (final v in [
          'Sầu riêng',
          'Sô-cô-la',
          'Việt quất',
          'Chanh dây',
          'Dâu',
        ]) {
          expect(find.widgetWithText(ChoiceChip, v), findsOneWidget);
        }

        final defaultChip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Việt quất'),
        );
        expect(defaultChip.selected, isTrue);
        expect(item.attributes['nhan_banh'], 'Việt quất');

        final nonDefault = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Sầu riêng'),
        );
        expect(nonDefault.selected, isFalse);
      },
    );

    testWidgets(
      'AC-3: tapping a non-default chip selects it and deselects the previous',
      (tester) async {
        final item = DraftOrderItem(product: _productWithEnum());
        await _pumpCard(tester, item);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Sô-cô-la'));
        await tester.pump();

        final tapped = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Sô-cô-la'),
        );
        final prev = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Việt quất'),
        );
        expect(tapped.selected, isTrue);
        expect(prev.selected, isFalse);
        expect(item.attributes['nhan_banh'], 'Sô-cô-la');
      },
    );

    testWidgets(
      'AC-1: product without enum attributes renders no enum row',
      (tester) async {
        final item = DraftOrderItem(product: _productWithEnum(enums: const []));
        await _pumpCard(tester, item);

        expect(find.text('Nhân bánh'), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        expect(item.attributes, isEmpty);
      },
    );

    testWidgets('skips chips for inactive options', (tester) async {
      final inactive = const EnumAttribute(
        attributeType: 'nhan_banh',
        labelVi: 'Nhân bánh',
        options: [
          EnumOption(id: 1, valueVi: 'Sầu riêng', isDefault: true),
          EnumOption(id: 2, valueVi: 'Đã ngừng', active: 0),
        ],
      );
      final item = DraftOrderItem(
        product: _productWithEnum(enums: [inactive]),
      );
      await _pumpCard(tester, item);

      expect(find.widgetWithText(ChoiceChip, 'Sầu riêng'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Đã ngừng'), findsNothing);
    });

    testWidgets(
      'R4: enum tap does not change price_chip_label and price tap does not change nhan_banh',
      (tester) async {
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000),
          PriceChip(id: 2, label: 'Lớn', price: 400000),
        ];
        final product = _productWithEnum(priceChips: priceChips);
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

        // Pre-state
        expect(item.attributes['nhan_banh'], 'Việt quất');
        expect(item.attributes.containsKey('price_chip_label'), isFalse);

        // Tap an enum chip — should not introduce price_chip_label
        await tester.tap(find.widgetWithText(ChoiceChip, 'Sầu riêng'));
        await tester.pump();
        expect(item.attributes['nhan_banh'], 'Sầu riêng');
        expect(item.attributes.containsKey('price_chip_label'), isFalse);

        // Tap a price chip — should not change nhan_banh
        await tester.tap(find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ'));
        await tester.pump();
        expect(item.attributes['price_chip_label'], 'Lớn');
        expect(item.attributes['nhan_banh'], 'Sầu riêng');
      },
    );

    testWidgets(
      'chip select sets DraftOrderItem.priceChipId and shows stock qty',
      (tester) async {
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000, stockQty: 3),
          PriceChip(id: 2, label: 'Lớn', price: 400000, stockQty: 7),
        ];
        final product = _productWithEnum(priceChips: priceChips);
        final item = DraftOrderItem(product: product);

        await _pumpCard(tester, item);

        expect(item.priceChipId, isNull);

        expect(find.widgetWithText(ChoiceChip, 'Nhỏ · 200.000đ (3)'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ (7)'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Lớn · 400.000đ (7)'));
        await tester.pump();

        expect(item.priceChipId, 2);
        expect(item.attributes['price_chip_label'], 'Lớn');
      },
    );

    testWidgets(
      'new trung bay item shows useInventory off and keeps toggle state',
      (tester) async {
        final item = DraftOrderItem(
          product: const Product(
            id: 200,
            name: 'Bánh trưng bày',
            attributes: {'trung_bay': 'true'},
          ),
        );

        await _pumpCard(tester, item);

        final switchFinder = find.byType(Switch);
        expect(find.text(StockLabels.useInventory), findsOneWidget);
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<Switch>(switchFinder).value, isFalse);
        expect(item.attributes['useInventory'], 'false');

        await tester.tap(find.text(StockLabels.useInventory));
        await tester.pump();

        expect(tester.widget<Switch>(switchFinder).value, isTrue);
        expect(item.attributes['useInventory'], 'true');
      },
    );

    // ── DG-296 Phase 4: regular order flow markup ──────────────────────────

    testWidgets(
      'AC1: trưng bày item shows Giá gốc and editable Giá bán (thousands)',
      (tester) async {
        final item = DraftOrderItem(
          product: const Product(
            id: 300,
            name: 'Bánh trưng bày',
            basePrice: 200000,
            attributes: {'trung_bay': 'true'},
          ),
        );

        await _pumpCard(tester, item);

        // "Giá gốc" label shows the assigned price (200.000đ).
        expect(find.textContaining('${OrdersLabels.giaGoc}:'), findsOneWidget);
        expect(find.text('200.000đ'), findsWidgets);
        // "Giá bán" editable field is present (not "Đơn giá").
        expect(find.text(OrdersLabels.giaBan), findsOneWidget);
        expect(find.text(OrdersLabels.itemPrice), findsNothing);
        // Default selling price == assigned price (no markup yet).
        expect(item.unitPrice, 200000);
        expect(item.assignedPrice, 200000);
      },
    );

    testWidgets(
      'AC1: editing Giá bán upward sets the selling price above assigned',
      (tester) async {
        final item = DraftOrderItem(
          product: const Product(
            id: 301,
            name: 'Bánh trưng bày',
            basePrice: 200000,
            attributes: {'trung_bay': 'true'},
          ),
        );

        await _pumpCard(tester, item);

        // Enter 250 (= 250.000đ) in the Giá bán field.
        await tester.enterText(find.byType(TextFormField).first, '250');
        await tester.pump();

        expect(item.customUnitPrice, 250000);
        expect(item.unitPrice, 250000);
        // Assigned price (COGS anchor) stays at base price.
        expect(item.assignedPrice, 200000);
        // No floor warning since 250.000 >= 200.000.
        expect(find.text(OrdersLabels.markupFloorWarning), findsNothing);
      },
    );

    testWidgets(
      'AC3: entering a selling price below assigned shows floor warning and clamps',
      (tester) async {
        final item = DraftOrderItem(
          product: const Product(
            id: 302,
            name: 'Bánh trưng bày',
            basePrice: 200000,
            attributes: {'trung_bay': 'true'},
          ),
        );

        await _pumpCard(tester, item);

        // Enter 150 (= 150.000đ) — below the 200.000đ assigned price.
        await tester.enterText(find.byType(TextFormField).first, '150');
        await tester.pump();

        expect(find.text(OrdersLabels.markupFloorWarning), findsOneWidget);
        // DG-296 FR3/AC3 review-remediation: the editor now clamps the draft
        // item's customUnitPrice upward to the assigned price (COGS anchor)
        // instead of leaving the below-floor value in place. The floor warning
        // still surfaces so staff see that their entry was adjusted. The
        // draftItemToCart write-back is the second defense-in-depth.
        expect(item.customUnitPrice, 200000);
        expect(item.assignedPrice, 200000);
      },
    );

    testWidgets(
      'AC4: non-trưng bày item shows Đơn giá (no markup UI)',
      (tester) async {
        final item = DraftOrderItem(
          product: const Product(
            id: 303,
            name: 'Bánh thường',
            basePrice: 200000,
          ),
        );

        await _pumpCard(tester, item);

        expect(find.text(OrdersLabels.itemPrice), findsOneWidget);
        expect(find.text(OrdersLabels.giaBan), findsNothing);
        expect(find.textContaining('${OrdersLabels.giaGoc}:'), findsNothing);
        // assignedPrice stays null for non-trưng bày (FR8).
        expect(item.assignedPrice, isNull);
      },
    );

    testWidgets(
      'selecting a price chip resets assigned price for trưng bày',
      (tester) async {
        final priceChips = const [
          PriceChip(id: 1, label: 'Nhỏ', price: 200000),
          PriceChip(id: 2, label: 'Lớn', price: 300000),
        ];
        final item = DraftOrderItem(
          product: Product(
            id: 304,
            name: 'Bánh trưng bày',
            basePrice: 200000,
            priceChips: priceChips,
            attributes: const {'trung_bay': 'true'},
          ),
        );

        await _pumpCard(tester, item);

        // Tap the "Lớn" chip — assigned price should reset to 300.000đ.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Lớn · 300.000đ'));
        await tester.pump();

        expect(item.priceChipId, 2);
        expect(item.customUnitPrice, 300000);
        expect(item.assignedPrice, 300000);
        expect(find.text('300.000đ'), findsWidgets);
      },
    );
  });
}
