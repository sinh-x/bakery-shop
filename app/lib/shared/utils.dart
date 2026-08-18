import 'package:flutter/material.dart';

import 'labels/blanks.dart';
import 'labels/expenses.dart';
import 'labels/orders.dart';
import 'labels/products.dart';
import 'labels/shared.dart';

// Category mapping (new slugs)
const categoryMap = {
  'banh_mi': ProductsLabels.catBanhMi,
  'banh_kem': ProductsLabels.catBanhKem,
  'banh_ngot': ProductsLabels.catBanhNgot,
  'cookie': ProductsLabels.catCookie,
  'khac': ProductsLabels.catKhac,
};

// Category emoji mapping (new slugs)
const categoryEmojiMap = {
  'banh_mi': ProductsLabels.emojiBanhMi,
  'banh_kem': ProductsLabels.emojiBanhKem,
  'banh_ngot': ProductsLabels.emojiBanhNgot,
  'cookie': ProductsLabels.emojiCookie,
  'khac': ProductsLabels.emojiKhac,
};

// Status mapping
const statusMap = {
  'new': OrdersLabels.statusNew,
  'confirmed': OrdersLabels.statusConfirmed,
  'in_progress': OrdersLabels.statusInProgress,
  'ready': OrdersLabels.statusReady,
  'delivered': OrdersLabels.statusDelivered,
  'completed': OrdersLabels.statusCompleted,
  'cancelled': OrdersLabels.statusCancelled,
};

// Valid transitions (from CLI validate_transition logic)
const validTransitions = {
  'new': ['confirmed', 'cancelled'],
  'confirmed': ['in_progress', 'cancelled'],
  'in_progress': ['ready', 'cancelled'],
  'ready': ['delivered', 'completed', 'cancelled'],
  'delivered': ['completed'],
  'completed': <String>[],
  'cancelled': <String>[],
};

/// Returns the button label for transitioning to [targetStatus].
String statusActionLabel(String targetStatus) {
  switch (targetStatus) {
    case 'confirmed':
      return OrdersLabels.actionConfirm;
    case 'in_progress':
      return OrdersLabels.actionStart;
    case 'ready':
      return OrdersLabels.actionReady;
    case 'delivered':
      return OrdersLabels.actionDeliver;
    case 'completed':
      return OrdersLabels.actionComplete;
    case 'cancelled':
      return BlanksLabels.actionCancel;
    default:
      return targetStatus;
  }
}

String txnTypeLabel(String type) {
  switch (type) {
    case 'deposit':
      return OrdersLabels.txnTypeDeposit;
    case 'payment':
      return OrdersLabels.txnTypePayment;
    case 'full_payment':
      return OrdersLabels.txnTypeFullPayment;
    case 'refund':
      return OrdersLabels.txnTypeRefund;
    case 'tien_rut':
      return OrdersLabels.txnTypeRutTien;
    default:
      return type;
  }
}

String paymentMethodLabel(String method) {
  switch (method) {
    case 'cash':
      return OrdersLabels.methodCash;
    case 'transfer':
      return OrdersLabels.methodTransfer;
    case 'debt':
      return OrdersLabels.methodDebt;
    default:
      return method;
  }
}

/// Optional target bank account options for payment transactions (DG-244).
/// Empty default is represented by `null`/empty string at the call boundary;
/// this list holds only the selectable VCB accounts (FR2).
const paymentTargetAccounts = <String>[
  ExpensesLabels.paymentSourcePhuongVCB,
  ExpensesLabels.paymentSourceAnVCB,
];

// Work item status mapping
const workItemStatusMap = {
  'pending': OrdersLabels.workItemPending,
  'confirmed': OrdersLabels.workItemConfirmed,
  'working': OrdersLabels.workItemWorking,
  'ready': OrdersLabels.workItemReady,
  'delivered': OrdersLabels.workItemDelivered,
  'cancelled': OrdersLabels.workItemCancelled,
};

String workItemStatusLabel(String status) =>
    workItemStatusMap[status] ?? status;

// Work item status colors
const workItemStatusColors = {
  'pending': Colors.grey,
  'confirmed': Colors.blue,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

// Valid work item transitions
const workItemValidTransitions = {
  'pending': ['confirmed', 'working', 'cancelled'],
  'confirmed': ['working', 'cancelled'],
  'working': ['ready', 'cancelled'],
  'ready': ['delivered', 'cancelled'],
  'delivered': ['cancelled'],
  'cancelled': <String>[],
};

/// Shows a SnackBar anchored to the top of the screen.
void showTopSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}

/// Format VND: 150000.0 → "150.000đ"
String formatVND(double amount) {
  final formatted = amount.toInt().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$formatted${SharedLabels.currency}';
}