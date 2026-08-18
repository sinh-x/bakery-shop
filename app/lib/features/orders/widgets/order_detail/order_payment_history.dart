import 'package:flutter/material.dart';

import '../../../../data/models/payment_transaction.dart';
import '../section_header.dart';
import 'order_transaction_tile.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// Payment history section listing all transactions or an empty-state message.
class OrderPaymentHistory extends StatelessWidget {
  const OrderPaymentHistory({
    super.key,
    required this.txns,
    required this.onTransactionTap,
  });

  final List<PaymentTransaction> txns;
  final void Function(PaymentTransaction txn) onTransactionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(OrdersLabels.paymentHistory),
        if (txns.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              OrdersLabels.noPaymentHistory,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          ...txns.map(
            (t) => OrderTransactionTile(
              txn: t,
              onTap: () => onTransactionTap(t),
            ),
          ),
      ],
    );
  }
}