import 'package:flutter/material.dart';

import '../../../../data/models/payment_transaction.dart';
import 'order_payment_history.dart';

/// Transactions tab content: payment history list with transaction-detail
/// tap. The [OrderPaymentHistory] widget is reused as-is; `txns` and the
/// `onTransactionTap` callback are forwarded from the parent
/// [OrderDetailScreen] so the detail sheet uses the same launcher as before
/// the tab split (NFR1: no extra provider work on tab switch).
class OrderDetailTransactionsTab extends StatelessWidget {
  const OrderDetailTransactionsTab({
    super.key,
    required this.txns,
    required this.onTransactionTap,
  });

  final List<PaymentTransaction> txns;
  final void Function(PaymentTransaction txn) onTransactionTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        OrderPaymentHistory(txns: txns, onTransactionTap: onTransactionTap),
      ],
    );
  }
}