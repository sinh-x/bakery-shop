import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/utils/pos_cart_wizard_sync.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}