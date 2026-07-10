import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/widgets/pos_checkout_cart_item_tile.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

Product _product() {
  return const Product(
    id: 1,
    name: 'Banh mi',
    basePrice: 20000,
    category: 'bread',
    active: 1,
  );
}

class _SeededCartNotifier extends PosCartNotifier {
  _SeededCartNotifier();
  @override
  PosCartState build() => PosCartState();
}

void main() {
  group('PosCheckoutCartItemTile badge (DG-223 MAJOR-2)', () {
    testWidgets('renders "Dùng tồn kho" badge when useInventory is true',
        (tester) async {
      final item = PosCartItem(
        product: _product(),
        quantity: 1,
        useInventory: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posCartProvider.overrideWith(_SeededCartNotifier.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosCheckoutCartItemTile(item: item),
            ),
          ),
        ),
      );

      expect(find.text(VN.useInventory), findsOneWidget);
    });

    testWidgets('does not render "Dùng tồn kho" badge when useInventory is false',
        (tester) async {
      final item = PosCartItem(
        product: _product(),
        quantity: 1,
        useInventory: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posCartProvider.overrideWith(_SeededCartNotifier.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosCheckoutCartItemTile(item: item),
            ),
          ),
        ),
      );

      expect(find.text(VN.useInventory), findsNothing,
          reason: 'MAJOR-2: force-sell item must not show the inventory badge');
    });
  });
}
