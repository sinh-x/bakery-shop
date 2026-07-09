import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/product_summary_card.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

Product _product({Map<String, String> attributes = const {}}) {
  return Product(
    id: 1,
    name: 'Bánh kem Socola',
    category: 'banh_kem',
    basePrice: 200000,
    attributes: attributes,
  );
}

DraftOrderItem _item({
  Map<String, String> productAttributes = const {},
  Map<String, dynamic> itemAttributes = const {},
}) {
  return DraftOrderItem(
    product: _product(attributes: productAttributes),
    quantity: 2,
    attributes: itemAttributes,
  );
}

void main() {
  group('ProductSummaryCard inventory label (FR-7, AC6)', () {
    testWidgets(
        'shows the VN inventory label only (no ": true", no English) when item uses inventory',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductSummaryCard(items: [
              _item(
                productAttributes: {'trung_bay': 'true'},
                itemAttributes: {'useInventory': 'true'},
              ),
            ]),
          ),
        ),
      );

      expect(find.text(VN.useInventory), findsOneWidget);
      // No ": true" suffix anywhere in the rendered tree.
      expect(
        find.textContaining('${VN.useInventory}: true'),
        findsNothing,
        reason: 'FR-7: the inventory line must not append ": true"',
      );
      // No English fallback value rendered.
      expect(find.textContaining('true'), findsNothing);
    });

    testWidgets('does not render the inventory line when item does not use inventory',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductSummaryCard(items: [
              _item(
                productAttributes: {'trung_bay': 'true'},
                itemAttributes: {'useInventory': 'false'},
              ),
            ]),
          ),
        ),
      );

      expect(find.text(VN.useInventory), findsNothing,
          reason: 'AC6: when the item does not use inventory, no line is shown');
    });

    testWidgets('does not render the inventory line when useInventory is absent',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductSummaryCard(items: [_item()]),
          ),
        ),
      );

      expect(find.text(VN.useInventory), findsNothing);
    });

    testWidgets('renders other attribute lines (notes, birthday) correctly',
        (tester) async {
      final item = _item(
        productAttributes: {'trung_bay': 'true'},
        itemAttributes: {'useInventory': 'true'},
      );
      item.notes = 'Ghi chú';
      item.isBirthday = true;
      item.age = '5';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductSummaryCard(items: [item])),
        ),
      );

      expect(find.textContaining(VN.notes), findsOneWidget);
      expect(find.textContaining(VN.birthdayWithAge), findsOneWidget);
      expect(find.text(VN.useInventory), findsOneWidget);
    });
  });
}