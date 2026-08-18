import 'package:flutter/material.dart';

import '../../../../data/models/payment_transaction.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Shared status-rank maps and helpers extracted from `order_detail_screen.dart`
/// (DG-308 Phase 4.2 / FR-FL-1).
///
/// These were private top-level constants in the monolithic screen file. They
/// are used by both the order-level and work-item-level transition flows, so
/// they live here rather than in a single widget file.

const orderStatusRank = {
  'new': 0,
  'confirmed': 1,
  'in_progress': 2,
  'ready': 3,
  'delivered': 4,
  'completed': 5,
  'cancelled': 5,
};

const workItemStatusRank = {
  'pending': 0,
  'confirmed': 1,
  'working': 2,
  'ready': 3,
  'delivered': 4,
  'cancelled': 5,
};

const workItemStatusColors = {
  'pending': Colors.grey,
  'confirmed': Colors.blue,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

bool isBackward(String current, String target, Map<String, int> ranks) =>
    (ranks[target] ?? 0) < (ranks[current] ?? 0);

/// Shows a reason dialog for a status transition.
/// Returns the trimmed reason string, or null if cancelled.
Future<String?> showReasonDialog(
  BuildContext context,
  String targetStatus,
) async {
  final ctrl = TextEditingController();
  final isCancel = targetStatus == 'cancelled';
  final theme = Theme.of(context);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isCancel ? VN.cancelOrderTitle : VN.statusReasonTitle),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: VN.statusReasonLabel,
              hintText: VN.statusReasonHint,
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            autofocus: true,
            onChanged: (_) => setS(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              style: isCancel
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    )
                  : null,
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(
                isCancel ? VN.confirmCancelAction : VN.confirmStatusChange,
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

/// Computes the paid amount from a list of payment transactions.
///
/// Excludes invalidated transactions and `tien_rut` (cash withdrawn from the
/// order, not a payment received). Refunds reduce the paid total.
double computePaid(Iterable<PaymentTransaction> txns) {
  var paid = 0.0;
  for (final t in txns) {
    // Exclude invalidated transactions from payment totals (DG-196).
    if (t.invalidatedAt != null) continue;
    if (t.type == 'refund') {
      paid -= t.amount;
    } else if (t.type != 'tien_rut') {
      // Exclude tien_rut: it's cash withdrawn from order, not a payment received
      paid += t.amount;
    }
  }
  return paid;
}

/// Transaction type → badge color (matches the card/detail sheet chips).
Color txnColor(String type) {
  switch (type) {
    case 'deposit':
      return Colors.blue;
    case 'payment':
      return Colors.green;
    case 'full_payment':
      return Colors.teal;
    case 'refund':
      return Colors.orange;
    case 'tien_rut':
      return Colors.amber;
    default:
      return Colors.grey;
  }
}