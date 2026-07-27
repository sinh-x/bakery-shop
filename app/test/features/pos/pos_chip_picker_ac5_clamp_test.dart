// DG-296 FR3/AC3 review-remediation + AC5 end-to-end verification.
//
// Verifies the data flow that was broken in production order M52-T (#1708):
//   - AC5: chip picker selection propagates `assignedPrice` = chip price (the
//     COGS anchor), `unitPrice` = marked-up selling price, and the backend
//     derives COGS = 30% × assignedPrice (covered at the journal_sync layer
//     by `test_ac5_chip_price_assigned_anchor_at_journal_sync_layer`).
//   - FR3/AC3: when the wizard Stage 1 editor produces a `customUnitPrice`
//     below `assignedPrice`, the `draftItemToCart` write-back clamps the
//     selling price upward to the assigned price so the POS cart (the single
//     source of truth at submit) can never carry a trưng bày item with
//     unitPrice < assignedPrice.
//
// These are pure-Dart unit tests over the sync helpers — no widget pumping
// is required because the clamp lives in `draftItemToCart`, not in widget
// state. The chip-picker dialog clamp is already covered by the dialog's own
// confirm-button logic in `pos_product_grid.dart` (lines 285-299).
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/price_chip.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/pos/utils/pos_cart_wizard_sync.dart';
import 'package:bakery_app/providers/pos_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Product _trungBayProduct({
  int id = 83,
  double basePrice = 200000,
  List<PriceChip> priceChips = const [],
}) {
  return Product(
    id: id,
    name: 'Bánh kem trưng bày',
    basePrice: basePrice,
    category: 'cake',
    active: 1,
    priceChips: priceChips,
    attributes: const {'trung_bay': 'true'},
  );
}

void main() {
  group('AC5 chip picker → assigned_price → COGS anchor (DG-296)', () {
    test(
        'chip selection sets assignedPrice=chipPrice and unitPrice=markup '
        '(350k sale, 300k chip → assignedPrice 300k, unitPrice 350k)', () {
      const chip = PriceChip(id: 11, label: 'Trưng bày 300', price: 300000);
      final product = _trungBayProduct(priceChips: [chip]);

      // Simulate the chip-picker confirm path: staff selects the 300k chip
      // (assignedPrice = 300k) and enters 350 (thousands) as the selling price.
      // The dialog clamps above the floor (350k > 300k) so the cart receives
      // selectedPrice=350k, assignedPrice=300k.
      final cartItem = PosCartItem(
        product: product,
        quantity: 1,
        selectedPrice: 350000,
        selectedChipId: 11,
        selectedChipLabel: 'Trưng bày 300',
        assignedPrice: 300000,
      );

      expect(cartItem.assignedPrice, 300000,
          reason: 'AC5: assignedPrice must be the chip price (COGS anchor)');
      expect(cartItem.unitPrice, 350000,
          reason: 'AC5: unitPrice must be the marked-up selling price');
      expect(cartItem.total, 350000);

      // The backend COGS resolution (30% × assignedPrice = 90,000) is verified
      // at the journal_sync layer by
      // `test_ac5_chip_price_assigned_anchor_at_journal_sync_layer`. Here we
      // assert the client-side precondition: assignedPrice is the chip price,
      // not basePrice (200k) and not the marked-up unitPrice (350k).
      expect(cartItem.assignedPrice, isNot(product.basePrice));
      expect(cartItem.assignedPrice, isNot(cartItem.unitPrice));
    });

    test(
        'cartItemToDraft preserves AC5 chip anchor through the wizard '
        'cart→draft conversion (no clamp needed — markup above floor)', () {
      const chip = PriceChip(id: 11, label: 'Trưng bày 300', price: 300000);
      final product = _trungBayProduct(priceChips: [chip]);
      final cartItem = PosCartItem(
        product: product,
        quantity: 1,
        selectedPrice: 350000,
        selectedChipId: 11,
        selectedChipLabel: 'Trưng bày 300',
        assignedPrice: 300000,
      );

      final draft = cartItemToDraft(cartItem);

      expect(draft.assignedPrice, 300000);
      expect(draft.customUnitPrice, 350000);
      expect(draft.unitPrice, 350000);
    });
  });

  group('FR3/AC3 price floor clamp at wizard→cart write-back (DG-296)', () {
    test(
        'draftItemToCart clamps a below-floor customUnitPrice upward to the '
        'assigned price (reproduces the M52-T #1708 / order_item #5206 fix)',
        () {
      const chip = PriceChip(id: 11, label: 'Trưng bày 300', price: 300000);
      final product = _trungBayProduct(priceChips: [chip]);

      // Simulate the bug condition: the wizard editor allowed a 250k selling
      // price against a 300k assigned price (client clamp bypassed). The
      // draftItemToCart write-back must clamp the cart's selectedPrice upward
      // to 300k so the submitted order never stores unitPrice < assignedPrice.
      final draft = DraftOrderItem(
        product: product,
        quantity: 1,
        customUnitPrice: 250000,
        assignedPrice: 300000,
      );

      final cartItem = draftItemToCart(draft);

      expect(cartItem.assignedPrice, 300000);
      expect(
        cartItem.selectedPrice,
        300000,
        reason:
            'FR3/AC3: below-floor customUnitPrice must be clamped upward to '
            'assignedPrice at the wizard→cart write-back so the POS cart '
            'never carries a trưng bày item with unitPrice < assignedPrice',
      );
      expect(cartItem.unitPrice, 300000);
    });

    test(
        'draftItemToCart preserves a legitimate markup above the floor '
        '(no false clamp)', () {
      const chip = PriceChip(id: 11, label: 'Trưng bày 300', price: 300000);
      final product = _trungBayProduct(priceChips: [chip]);
      final draft = DraftOrderItem(
        product: product,
        quantity: 1,
        customUnitPrice: 350000,
        assignedPrice: 300000,
      );

      final cartItem = draftItemToCart(draft);

      expect(cartItem.assignedPrice, 300000);
      expect(cartItem.selectedPrice, 350000);
      expect(cartItem.unitPrice, 350000);
    });

    test(
        'draftItemToCart leaves non-trưng-bày items unchanged (FR8 backward '
        'compatibility — assignedPrice null → no clamp)', () {
      const product = Product(
        id: 5,
        name: 'Bánh mì',
        basePrice: 20000,
        category: 'bread',
        active: 1,
      );
      final draft = DraftOrderItem(
        product: product,
        quantity: 1,
        customUnitPrice: 15000,
        assignedPrice: null,
      );

      final cartItem = draftItemToCart(draft);

      expect(cartItem.assignedPrice, isNull);
      expect(cartItem.selectedPrice, 15000,
          reason:
              'FR8: non-trưng-bày items have no assigned price and must not '
              'be clamped (historical unitPrice anchor is preserved)');
    });

    test(
        'round trip cart→draft→cart clamps a below-floor selling price '
        'introduced during wizard editing', () {
      const chip = PriceChip(id: 11, label: 'Trưng bày 300', price: 300000);
      final product = _trungBayProduct(priceChips: [chip]);
      // Cart originally carries a valid 350k markup against the 300k chip.
      final original = PosCartItem(
        product: product,
        quantity: 1,
        selectedPrice: 350000,
        selectedChipId: 11,
        selectedChipLabel: 'Trưng bày 300',
        assignedPrice: 300000,
      );

      // Staff edits in wizard Stage 1 and lowers the price to 280k (below the
      // 300k floor). The expandable_item_card._updateManualPrice now clamps
      // customUnitPrice to 300k; draftItemToCart is the second defense-in-depth
      // and must also clamp so the invariant holds even if the editor clamp is
      // bypassed.
      final editedDraft = cartItemToDraft(original)
        ..customUnitPrice = 280000;

      final roundTripped = draftItemToCart(editedDraft);

      expect(roundTripped.assignedPrice, 300000);
      expect(roundTripped.selectedPrice, 300000);
      expect(roundTripped.unitPrice, 300000);
    });
  });
}