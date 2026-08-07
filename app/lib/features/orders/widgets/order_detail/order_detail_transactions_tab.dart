import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../../data/models/payment_transaction.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'order_payment_history.dart';
import 'order_payment_row.dart';

/// Transactions tab content: payment summary at the top (total, paid,
/// remaining), an "add transaction" button that opens
/// [OrderRecordPaymentSheet], then the existing [OrderPaymentHistory] list.
///
/// The summary reuses the [OrderPaymentRow] pattern from
/// [OrderPaymentSummary] (NFR1: no extra network fetch on tab switch — the
/// `order`, `amountPaid`, and `remaining` values are forwarded from the
/// parent [OrderDetailScreen] which already watches
/// `orderPaymentTransactionsProvider`).
class OrderDetailTransactionsTab extends StatelessWidget {
  const OrderDetailTransactionsTab({
    super.key,
    required this.order,
    required this.amountPaid,
    required this.remaining,
    required this.txns,
    required this.onAddPayment,
    required this.onTransactionTap,
  });

  final Order order;
  final double amountPaid;
  final double remaining;
  final List<PaymentTransaction> txns;
  final VoidCallback onAddPayment;
  final void Function(PaymentTransaction txn) onTransactionTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _TransactionsSummary(
          order: order,
          amountPaid: amountPaid,
          remaining: remaining,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddPayment,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(VN.orderDetailAddTransaction),
        ),
        const SizedBox(height: 16),
        OrderPaymentHistory(txns: txns, onTransactionTap: onTransactionTap),
      ],
    );
  }
}

/// Compact payment summary card for the transactions tab. Renders the three
/// key amounts (total, paid, remaining) using the shared [OrderPaymentRow]
/// widget so the layout matches [OrderPaymentSummary].
class _TransactionsSummary extends StatelessWidget {
  const _TransactionsSummary({
    required this.order,
    required this.amountPaid,
    required this.remaining,
  });

  final Order order;
  final double amountPaid;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingColor =
        remaining > 0 ? theme.colorScheme.error : Colors.green;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          OrderPaymentRow(
            label: VN.total,
            value: formatVND(order.totalPrice),
            valueStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          OrderPaymentRow(
            label: VN.amountPaidLabel,
            value: formatVND(amountPaid),
            valueStyle: theme.textTheme.bodyMedium?.copyWith(
              color: amountPaid > 0 ? Colors.green : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          OrderPaymentRow(
            label: VN.remainingLabel,
            value: formatVND(remaining),
            valueStyle: theme.textTheme.bodyMedium?.copyWith(
              color: remainingColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}