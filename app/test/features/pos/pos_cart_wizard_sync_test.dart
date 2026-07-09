import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/utils/pos_cart_wizard_sync.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

Product _product({int id = 1, double price = 20000, String name = 'Banh mi'}) {
  return Product(
    id: id,
    name: name,
    basePrice: price,
    category: 'bread',
    active: 1,
  );
}

void main() {
  group('pos_cart_wizard_sync (pure conversions)', () {
    test('cartItemToDraft preserves quantity, gift, chip, and inventory flag',
        () {
      final product = _product();
      final cartItem = PosCartItem(
        product: product,
        quantity: 3,
        useInventory: false,
        selectedPrice: 25000,
        selectedChipId: 7,
      );

      final draft = cartItemToDraft(cartItem);

      expect(draft.product.id, product.id);
      expect(draft.quantity, 3);
      expect(draft.isGift, isFalse);
      expect(draft.customUnitPrice, 25000);
      expect(draft.priceChipId, 7);
      expect(draft.attributes['useInventory'], 'false');
    });

    test('cartItemToDraft omits useInventory override when inventory is used',
        () {
      final cartItem = PosCartItem(product: _product(), quantity: 1);
      final draft = cartItemToDraft(cartItem);
      expect(draft.attributes['useInventory'], isNot('false'));
    });

    test('cartItemToDraft preserves gift flag', () {
      final cartItem = PosCartItem(
        product: _product(),
        quantity: 1,
        isGift: true,
      );
      final draft = cartItemToDraft(cartItem);
      expect(draft.isGift, isTrue);
    });

    test('draftItemToCart preserves quantity, chip selection, and inventory',
        () {
      const chip = PriceChip(id: 7, label: 'Lớn', price: 25000);
      const product = Product(
        id: 1,
        name: 'Banh mi',
        basePrice: 20000,
        category: 'bread',
        active: 1,
        priceChips: [chip],
      );
      final draft = DraftOrderItem(
        product: product,
        quantity: 2,
        customUnitPrice: 25000,
        priceChipId: 7,
        attributes: const {'useInventory': 'false'},
      );

      final cartItem = draftItemToCart(draft);

      expect(cartItem.product.id, 1);
      expect(cartItem.quantity, 2);
      expect(cartItem.selectedChipId, 7);
      expect(cartItem.selectedChipLabel, 'Lớn');
      expect(cartItem.selectedPrice, 25000);
      expect(cartItem.useInventory, isFalse);
    });

    test('draftItemToCart defaults useInventory true when not overridden', () {
      final draft = DraftOrderItem(product: _product(), quantity: 1);
      expect(draftItemToCart(draft).useInventory, isTrue);
    });

    test('cartItemToDraft preserves notes and pendingPhotos', () {
      final cartItem = PosCartItem(
        product: _product(),
        quantity: 1,
        notes: 'Không đường',
        pendingPhotos: <XFile>[],
      );
      final draft = cartItemToDraft(cartItem);
      expect(draft.notes, 'Không đường');
      expect(draft.pendingPhotos, isEmpty);
    });

    test('draftItemToCart preserves notes and pendingPhotos', () {
      final draft = DraftOrderItem(
        product: _product(),
        quantity: 1,
        notes: 'Ít ngọt',
        pendingPhotos: <XFile>[],
      );
      final cartItem = draftItemToCart(draft);
      expect(cartItem.notes, 'Ít ngọt');
      expect(cartItem.pendingPhotos, isEmpty);
    });

    test('round trip cart -> draft -> cart preserves notes and photos', () {
      final original = PosCartItem(
        product: _product(),
        quantity: 2,
        notes: 'Không đường, ít bơ',
        pendingPhotos: <XFile>[],
      );
      final roundTripped = draftItemToCart(cartItemToDraft(original));
      expect(roundTripped.notes, 'Không đường, ít bơ');
      expect(roundTripped.pendingPhotos, isEmpty);
    });

    test('round trip cart -> draft -> cart preserves line identity', () {
      const chip = PriceChip(id: 9, label: 'Nhỏ', price: 15000);
      const product = Product(
        id: 5,
        name: 'Banh cuon',
        basePrice: 15000,
        category: 'banh',
        active: 1,
        priceChips: [chip],
      );
      final original = PosCartItem(
        product: product,
        quantity: 4,
        useInventory: false,
        selectedPrice: 15000,
        selectedChipId: 9,
        selectedChipLabel: 'Nhỏ',
      );

      final roundTripped = draftItemToCart(cartItemToDraft(original));

      expect(roundTripped.product.id, 5);
      expect(roundTripped.quantity, 4);
      expect(roundTripped.useInventory, isFalse);
      expect(roundTripped.selectedChipId, 9);
      expect(roundTripped.selectedChipLabel, 'Nhỏ');
      expect(roundTripped.selectedPrice, 15000);
    });

    test('cartItemToDraft preserves isBirthday and age', () {
      final cartItem = PosCartItem(
        product: _product(),
        quantity: 1,
        isBirthday: true,
        age: '5',
      );
      final draft = cartItemToDraft(cartItem);
      expect(draft.isBirthday, isTrue);
      expect(draft.age, '5');
    });

    test('cartItemToDraft preserves rutTien with cash fee and amount', () {
      final cartItem = PosCartItem(
        product: _product(),
        quantity: 1,
        rutTien: true,
        cashFee: 5000,
        cashAmount: 20000,
      );
      final draft = cartItemToDraft(cartItem);
      expect(draft.attributes['rut_tien'], 'true');
      expect(draft.attributes['cash_fee'], '5000.0');
      expect(draft.attributes['cash_amount'], '20000.0');
    });

    test('draftItemToCart preserves isBirthday and age', () {
      final draft = DraftOrderItem(
        product: _product(),
        quantity: 1,
        isBirthday: true,
        age: '7',
      );
      final cartItem = draftItemToCart(draft);
      expect(cartItem.isBirthday, isTrue);
      expect(cartItem.age, '7');
    });

    test('draftItemToCart preserves rutTien, cashFee, cashAmount from attributes', () {
      final draft = DraftOrderItem(
        product: _product(),
        quantity: 1,
        attributes: {'rut_tien': 'true', 'cash_fee': '5000', 'cash_amount': '20000'},
      );
      final cartItem = draftItemToCart(draft);
      expect(cartItem.rutTien, isTrue);
      expect(cartItem.cashFee, 5000);
      expect(cartItem.cashAmount, 20000);
    });

    test('cartItemToDraft omits rut_tien attributes when rutTien is false', () {
      final cartItem = PosCartItem(product: _product(), quantity: 1, rutTien: false);
      final draft = cartItemToDraft(cartItem);
      expect(draft.attributes['rut_tien'], isNot('true'));
    });

    test('round trip cart -> draft -> cart preserves all birthday and rut_tien attributes', () {
      const chip = PriceChip(id: 1, label: 'Lớn', price: 25000);
      const product = Product(
        id: 1,
        name: 'Banh sinh nhat',
        basePrice: 200000,
        category: 'cake',
        active: 1,
        priceChips: [chip],
      );
      final original = PosCartItem(
        product: product,
        quantity: 2,
        isBirthday: true,
        age: '5',
        rutTien: true,
        cashFee: 10000,
        cashAmount: 50000,
        useInventory: false,
      );
      final roundTripped = draftItemToCart(cartItemToDraft(original));
      expect(roundTripped.isBirthday, isTrue);
      expect(roundTripped.age, '5');
      expect(roundTripped.rutTien, isTrue);
      expect(roundTripped.cashFee, 10000);
      expect(roundTripped.cashAmount, 50000);
      expect(roundTripped.useInventory, isFalse);
    });

    test('round trip with partial rutTien (true but no fee/amount)', () {
      final original = PosCartItem(
        product: _product(),
        quantity: 1,
        rutTien: true,
      );
      final roundTripped = draftItemToCart(cartItemToDraft(original));
      expect(roundTripped.rutTien, isTrue);
      expect(roundTripped.cashFee, isNull);
      expect(roundTripped.cashAmount, isNull);
    });

    test('round trip with null attributes map yields empty attributes', () {
      final original = PosCartItem(
        product: _product(),
        quantity: 1,
        attributes: null,
      );
      final roundTripped = draftItemToCart(cartItemToDraft(original));
      expect(roundTripped.attributes, isEmpty);
    });
  });

  group('syncWizardItemsToCart contract (M1)', () {
    testWidgets(
        'leaves the POS cart unchanged when wizard items is empty (M1)',
        (tester) async {
      final seededItems = [
        PosCartItem(product: _product(), quantity: 2),
      ];

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            posCartProvider.overrideWith(
              () => _SeededCartNotifier(seededItems),
            ),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(capturedRef.read(posCartProvider).items, hasLength(1));

      // Wizard items are empty by default (fresh state) — invoking the sync
      // must NOT clear the cart (M1: empty items are ignored).
      syncWizardItemsToCart(capturedRef);

      expect(
        capturedRef.read(posCartProvider).items,
        hasLength(1),
        reason: 'M1: empty wizard items must leave the cart unchanged',
      );
    });

    testWidgets('writes wizard items back to the cart when non-empty', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final product = _product(id: 2, name: 'Banh cuon');
      capturedRef
          .read(orderCreateStateProvider.notifier)
          .updateItems([DraftOrderItem(product: product, quantity: 3)]);

      syncWizardItemsToCart(capturedRef);

      final cart = capturedRef.read(posCartProvider);
      expect(cart.items, hasLength(1));
      expect(cart.items.single.product.id, 2);
      expect(cart.items.single.quantity, 3);
    });
  });
}

class _SeededCartNotifier extends PosCartNotifier {
  _SeededCartNotifier(this._items);
  final List<PosCartItem> _items;
  @override
  PosCartState build() => PosCartState(items: _items);
}