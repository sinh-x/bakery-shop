import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order_draft.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../providers/pos_provider.dart';

/// Converts a [PosCartItem] into the equivalent [DraftOrderItem] so the POS
/// cart contents can seed the order-wizard Stage 1 (product selection).
///
/// The cart is the single source of truth at submit; Stage 1 edits a working
/// copy in `orderCreateStateProvider.items` and writes it back via
/// [draftItemsToCart].
DraftOrderItem cartItemToDraft(PosCartItem item) {
  final isExtra = item.isGift || item.product.category == 'phu_kien';
  Map<String, dynamic>? attrs;
  attrs = <String, dynamic>{...item.attributes};
  if (!item.useInventory) {
    attrs['useInventory'] = 'false';
  } else {
    attrs['useInventory'] = 'true';
  }
  if (item.rutTien) {
    attrs['rut_tien'] = 'true';
    if (item.cashFee != null) attrs['cash_fee'] = item.cashFee!.toInt().toString();
    if (item.cashAmount != null) attrs['cash_amount'] = item.cashAmount!.toInt().toString();
  } else {
    attrs.remove('rut_tien');
    attrs.remove('cash_fee');
    attrs.remove('cash_amount');
  }
  return DraftOrderItem(
    product: item.product,
    quantity: item.quantity,
    isExtra: isExtra,
    isGift: item.isGift,
    customUnitPrice: item.selectedPrice,
    priceChipId: item.selectedChipId,
    isBirthday: item.isBirthday,
    age: item.age,
    attributes: attrs,
    notes: item.notes,
    pendingPhotos: item.pendingPhotos,
  );
}

/// Converts a [DraftOrderItem] (wizard Stage 1 working copy) back into a
/// [PosCartItem], preserving all attributes so the POS cart stays the single
/// source of truth at submit (DG-218 FR-2, DG-223 FR-3).
PosCartItem draftItemToCart(DraftOrderItem item) {
  final useInventory =
      item.attributes['useInventory']?.toString() != 'false';
  final rutTien = item.attributes['rut_tien']?.toString() == 'true';
  final cashFeeStr = item.attributes['cash_fee']?.toString();
  final cashAmountStr = item.attributes['cash_amount']?.toString();
  return PosCartItem(
    product: item.product,
    quantity: item.quantity,
    isGift: item.isGift,
    useInventory: useInventory,
    isBirthday: item.isBirthday,
    age: item.age,
    rutTien: rutTien,
    cashFee: cashFeeStr != null && cashFeeStr.isNotEmpty
        ? double.tryParse(cashFeeStr)
        : null,
    cashAmount: cashAmountStr != null && cashAmountStr.isNotEmpty
        ? double.tryParse(cashAmountStr)
        : null,
    selectedPrice: item.customUnitPrice,
    selectedChipId: item.priceChipId,
    selectedChipLabel: _resolveChipLabel(item),
    notes: item.notes,
    pendingPhotos: List<XFile>.from(item.pendingPhotos),
    attributes: Map<String, dynamic>.from(item.attributes),
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