import 'package:flutter/material.dart';

import '../../data/models/order.dart';
import '../../data/models/order_draft.dart';
import '../templates/template_context.dart';
import 'widgets/order_wizard.dart';

/// Builds a [TemplateContext] from the order create wizard's in-progress
/// state (DG-375 Phase 4.3 / FR2 / AC2).
///
/// The create wizard has no `Order` yet — it holds [DraftOrderItem]s and an
/// [OrderWizardData] snapshot. This helper formats the items list and maps
/// the wizard fields onto [TemplateContext] fields. `orderCode` and
/// `publicOrderCode` are empty for a new order (not yet assigned by the
/// backend); templates referencing them will render `(trống)`.
TemplateContext buildTemplateContextFromCreateWizard({
  required List<DraftOrderItem> items,
  required OrderWizardData wizardData,
  required DateTime? dueDate,
  required TimeOfDay? dueTime,
  required String source,
  required String createdBy,
}) {
  return TemplateContext.fromWizard(
    customerName: wizardData.customerName,
    customerPhone: wizardData.customerPhone,
    orderCode: '',
    publicOrderCode: '',
    dueDate: dueDate,
    dueTime: dueTime,
    totalPrice: _wizardTotalPrice(items),
    itemsList: _formatDraftItemsList(items),
    deliveryType: wizardData.deliveryType,
    deliveryAddress: wizardData.deliveryAddress,
    shippingFee: wizardData.shippingFee,
    notes: wizardData.notes,
    source: source,
    createdBy: createdBy,
    status: 'new',
  );
}

/// Builds a [TemplateContext] from the order edit wizard's in-progress
/// state (DG-375 Phase 4.3 / FR3 / AC3).
///
/// The edit wizard operates on an existing [Order] (already loaded by the
/// screen). The wizard snapshot reflects the user's in-progress edits; the
/// order code / public code come from the saved order. [summaryItems] are
/// the `DraftOrderItem`s currently in the edit cart.
TemplateContext buildTemplateContextFromEditWizard({
  required Order order,
  required List<DraftOrderItem> summaryItems,
  required OrderWizardData wizardSnapshot,
  required DateTime? dueDate,
  required TimeOfDay? dueTime,
  required String createdBy,
}) {
  return TemplateContext.fromWizard(
    customerName: wizardSnapshot.customerName,
    customerPhone: wizardSnapshot.customerPhone,
    orderCode: order.orderRef,
    publicOrderCode: order.publicOrderCode,
    dueDate: dueDate,
    dueTime: dueTime,
    totalPrice: _wizardTotalPrice(summaryItems),
    itemsList: _formatDraftItemsList(summaryItems),
    deliveryType: wizardSnapshot.deliveryType,
    deliveryAddress: wizardSnapshot.deliveryAddress,
    shippingFee: wizardSnapshot.shippingFee,
    notes: wizardSnapshot.notes,
    source: wizardSnapshot.source,
    createdBy: createdBy,
    status: order.status,
  );
}

double _wizardTotalPrice(List<DraftOrderItem> items) {
  var total = 0.0;
  for (final i in items) {
    if (i.isGift) continue;
    total += i.unitPrice * i.quantity;
  }
  return total;
}

String _formatDraftItemsList(List<DraftOrderItem> items) {
  if (items.isEmpty) return '';
  final lines = <String>[];
  for (final item in items) {
    // Skip auto-added free gifts — the customer does not see them as line
    // items. All other items (products + extras) are listed.
    if (item.isGift) continue;
    final name = item.product.name;
    final qty = item.quantity > 1 ? ' x${item.quantity}' : '';
    lines.add('- $name$qty');
  }
  return lines.join('\n');
}