import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/expandable_item_card.dart';
import 'package:bakery_app/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
