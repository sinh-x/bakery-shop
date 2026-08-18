import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND, paymentMethodLabel, txnTypeLabel;
import 'package:flutter/material.dart';

import '../../../../data/models/payment_transaction.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'order_detail_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// A single transaction row in the payment history list.
class OrderTransactionTile extends StatelessWidget {
  const OrderTransactionTile({
    super.key,
    required this.txn,
    this.onTap,
  });

  final PaymentTransaction txn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = txnColor(txn.type);
    final typeLabel = txnTypeLabel(txn.type);
    final methodLabel = paymentMethodLabel(txn.method);
    final isInvalidated = txn.invalidatedAt != null;

    String dateStr = '';
    if (txn.createdAt != null) {
      dateStr = formatDisplayShort(txn.createdAt);
    }

    final baseTextStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: txn.type == 'refund' ? Colors.orange : Colors.green,
    );
    final amountStyle = isInvalidated
        ? baseTextStyle?.copyWith(
            color: theme.colorScheme.outline,
            decoration: TextDecoration.lineThrough,
          )
        : baseTextStyle;
    final methodStyle = isInvalidated
        ? theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            decoration: TextDecoration.lineThrough,
          )
        : theme.textTheme.bodySmall;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isInvalidated
                    ? theme.colorScheme.outline.withAlpha(20)
                    : color.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isInvalidated
                      ? theme.colorScheme.outline.withAlpha(100)
                      : color.withAlpha(100),
                ),
              ),
              child: Text(
                isInvalidated ? OrdersLabels.txnInvalidatedBadge : typeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isInvalidated
                      ? theme.colorScheme.outline
                      : color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(methodLabel, style: methodStyle),
                  if (dateStr.isNotEmpty)
                    Text(
                      dateStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              txn.type == 'refund'
                  ? '-${formatVND(txn.amount)}'
                  : formatVND(txn.amount),
              style: amountStyle,
            ),
          ],
        ),
      ),
    );
  }
}