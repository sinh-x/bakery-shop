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
    if (item.cashFee != null) {
      attrs['cash_fee'] = item.cashFee!.toInt().toString();
    }
    if (item.cashAmount != null) {
      attrs['cash_amount'] = item.cashAmount!.toInt().toString();
    }
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
    assignedPrice: item.assignedPrice,
    isBirthday: item.isBirthday,
    age: item.age,
    candleType: item.candleType,
    attributes: attrs,
    notes: item.notes,
    pendingPhotos: item.pendingPhotos,
  );
}

/// Converts a [DraftOrderItem] (wizard Stage 1 working copy) back into a
/// [PosCartItem], preserving all attributes so the POS cart stays the single
/// source of truth at submit (DG-218 FR-2, DG-223 FR-3).
PosCartItem draftItemToCart(
  DraftOrderItem item, {
  bool includePendingPhotos = true,
}) {
  final useInventory = item.attributes['useInventory']?.toString() != 'false';
  final rutTien = item.attributes['rut_tien']?.toString() == 'true';
  final cashFeeStr = item.attributes['cash_fee']?.toString();
  final cashAmountStr = item.attributes['cash_amount']?.toString();
  // FR3/AC3 price floor enforcement (DG-296 review-remediation): clamp the
  // selling price to the assigned price (COGS anchor) when the wizard Stage 1
  // editor produced a `customUnitPrice` below `assignedPrice`. This is the
  // final defense-in-depth on the wizard→cart write-back path so the POS cart
  // (the single source of truth at submit) can never carry a trưng bày item
  // with unitPrice < assignedPrice. Non-trưng bày items keep `assignedPrice`
  // null and are unaffected.
  final assigned = item.assignedPrice;
  double? selectedPrice = item.customUnitPrice;
  if (assigned != null &&
      assigned > 0 &&
      selectedPrice != null &&
      selectedPrice < assigned) {
    selectedPrice = assigned;
  }
  return PosCartItem(
    product: item.product,
    quantity: item.quantity,
    isGift: item.isGift,
    useInventory: useInventory,
    isBirthday: item.isBirthday,
    age: item.age,
    candleType: item.candleType,
    rutTien: rutTien,
    cashFee: cashFeeStr != null && cashFeeStr.isNotEmpty
        ? double.tryParse(cashFeeStr)
        : null,
    cashAmount: cashAmountStr != null && cashAmountStr.isNotEmpty
        ? double.tryParse(cashAmountStr)
        : null,
    selectedPrice: selectedPrice,
    selectedChipId: item.priceChipId,
    selectedChipLabel: _resolveChipLabel(item),
    assignedPrice: item.assignedPrice,
    notes: item.notes,
    pendingPhotos: includePendingPhotos
        ? List<XFile>.from(item.pendingPhotos)
        : const <XFile>[],
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

/// Seeds the wizard `items` from the current POS cart so Stage 1 (product
/// selection) displays the cart contents for editing. The POS cart remains the
/// source of truth at submit; this only populates the wizard working copy
/// (DG-218 Phase 3, FR-2).
///
/// [provider] selects which wizard state instance to seed. When null, it
/// defaults to [orderCreateStateProvider] for backward compatibility; the POS
/// checkout flow (DG-322 Phase 4) passes [posOrderStateProvider] so the shared
/// orchestrator can drive cart sync for either workflow via the same function
/// (FR7).
void syncCartToWizardItems(
  WidgetRef ref, {
  NotifierProvider<OrderCreateStateNotifier, OrderCreateState>? provider,
}) {
  final cart = ref.read(posCartProvider);
  final drafts = cart.items.map(cartItemToDraft).toList();
  ref.read((provider ?? orderCreateStateProvider).notifier).updateItems(drafts);
}

/// Writes the wizard Stage 1 working copy (`<provider>.items`) back to the
/// POS cart so the cart stays the single source of truth at submit
/// (DG-218 Phase 3, FR-2). Empty items are ignored (cart unchanged) because
/// Stage 1's continue button is disabled when no items are selected.
///
/// [provider] selects which wizard state instance to read from. When null,
/// it defaults to [orderCreateStateProvider] for backward compatibility; the
/// POS checkout flow (DG-322 Phase 4) passes [posOrderStateProvider] (FR7).
void syncWizardItemsToCart(
  WidgetRef ref, {
  NotifierProvider<OrderCreateStateNotifier, OrderCreateState>? provider,
}) {
  final items = ref.read(provider ?? orderCreateStateProvider).items;
  if (items.isEmpty) return;
  final cartItems = items.map(draftItemToCart).toList();
  ref.read(posCartProvider.notifier).replaceCart(cartItems);
}
