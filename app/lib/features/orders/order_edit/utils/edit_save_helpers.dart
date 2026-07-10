import 'package:flutter/material.dart';

import '../../../../data/api/customer_service.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/models/order.dart';
import '../../../../shared/utils/order_helpers.dart';
import '../../../../shared/widgets/vietnamese_labels.dart';
import '../../../../shared/labels/customers.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// FR1: auto-create-and-link a customer when name+phone are present but no
/// customer is linked. Mirrors `order_create_screen.dart:137-151`. No dedup
/// (matches create behavior per §16). Returns the new customer (and sets
/// `touched = true` via the returned tuple's second value).
///
/// `failed` is `true` when an auto-create was attempted but threw — the caller
/// surfaces a non-blocking snackbar (CQ-6) so the operator knows the order
/// saved without a linked customer.
Future<({Customer? customer, bool touched, bool failed})>
    maybeAutoCreateCustomer({
  required Customer? selectedCustomer,
  required String name,
  required String phone,
  required CustomerService customerService,
}) async {
  final customerId = selectedCustomer?.id;
  if (customerId != null) {
    return (customer: selectedCustomer, touched: false, failed: false);
  }
  if (name.trim().isEmpty || phone.trim().isEmpty) {
    return (customer: selectedCustomer, touched: false, failed: false);
  }
  try {
    final result = await customerService.createCustomer(
      name: name.trim(),
      phone: phone.trim(),
    );
    return (customer: result.customer, touched: true, failed: false);
  } catch (e) {
    debugPrint('[OrderEdit] auto-create-customer failed: $e');
    return (customer: selectedCustomer, touched: false, failed: true);
  }
}

/// Shows the post-save snackbars: the public-code change notice (if the visual
/// code changed) and the saved confirmation, then pops.
void showEditSaveResult({
  required BuildContext context,
  required Order? originalOrder,
  required String orderRef,
  required Order updatedOrder,
}) {
  final oldVisualCode = visualOrderCode(
    orderRef: originalOrder?.orderRef ?? orderRef,
    publicOrderCode: originalOrder?.publicOrderCode,
  );
  final newVisualCode = visualOrderCode(
    orderRef: updatedOrder.orderRef,
    publicOrderCode: updatedOrder.publicOrderCode,
  );
  if (oldVisualCode != newVisualCode) {
    showTopSnackBar(context, '${VN.publicCodeChangedNotice} $newVisualCode');
  }
  showTopSnackBar(context, VN.orderEditSaved);
}