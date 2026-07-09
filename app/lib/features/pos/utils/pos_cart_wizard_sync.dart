import '../../../data/models/order_draft.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../providers/pos_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Converts a [PosCartItem] into the equivalent [DraftOrderItem] so the POS
/// cart contents can seed the order-wizard Stage 1 (product selection).
///
/// The cart is the single source of truth at submit; Stage 1 edits a working
/// copy in `orderCreateStateProvider.items` and writes it back via
/// [draftItemsToCart].
DraftOrderItem cartItemToDraft(PosCartItem item) {
  return DraftOrderItem(
    product: item.product,
    quantity: item.quantity,
    // POS cart gifts map to wizard extras-with-gift so the unified
    // ProductSummaryCard renders them in the extras section with the gift
    // suffix and excludes them from the regular total (DG-218 Phase 4, FR-6).
    isExtra: item.isGift,
    isGift: item.isGift,
    customUnitPrice: item.selectedPrice,
    priceChipId: item.selectedChipId,
    attributes: item.useInventory
        ? null
        : const <String, dynamic>{'useInventory': 'false'},
  );
}

/// Converts a [DraftOrderItem] (wizard Stage 1 working copy) back into a
/// [PosCartItem], preserving the chip selection and inventory flag so the
/// POS cart stays the single source of truth at submit (DG-218 FR-2).
PosCartItem draftItemToCart(DraftOrderItem item) {
  final useInventory =
      item.attributes['useInventory']?.toString() != 'false';
  return PosCartItem(
    product: item.product,
    quantity: item.quantity,
    isGift: item.isGift,
    useInventory: useInventory,
    selectedPrice: item.customUnitPrice,
    selectedChipId: item.priceChipId,
    selectedChipLabel: _resolveChipLabel(item),
  );
}

String? _resolveChipLabel(DraftOrderItem item) {
  final chipId = item.priceChipId;
  if (chipId == null) return null;
  for (final chip in item.product.priceChips) {
    if (chip.id == chipId) return chip.label;
  }
  return null;
}

/// Seeds `orderCreateStateProvider.items` from the current POS cart so Stage 1
/// (product selection) displays the cart contents for editing. The POS cart
/// remains the source of truth at submit; this only populates the wizard
/// working copy (DG-218 Phase 3, FR-2).
void syncCartToWizardItems(WidgetRef ref) {
  final cart = ref.read(posCartProvider);
  final drafts = cart.items.map(cartItemToDraft).toList();
  ref.read(orderCreateStateProvider.notifier).updateItems(drafts);
}

/// Writes the wizard Stage 1 working copy (`orderCreateStateProvider.items`)
/// back to the POS cart so the cart stays the single source of truth at
/// submit (DG-218 Phase 3, FR-2). Empty items are ignored (cart unchanged)
/// because Stage 1's continue button is disabled when no items are selected.
void syncWizardItemsToCart(WidgetRef ref) {
  final items = ref.read(orderCreateStateProvider).items;
  if (items.isEmpty) return;
  final cartItems = items.map(draftItemToCart).toList();
  ref.read(posCartProvider.notifier).replaceCart(cartItems);
}