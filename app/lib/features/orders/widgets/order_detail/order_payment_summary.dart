import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../section_header.dart';
import 'order_payment_row.dart';

/// Payment summary container with total, paid, remaining, and a status
/// badge. Also renders the totals divider and the add-payment button.
class OrderPaymentSummary extends StatelessWidget {
  const OrderPaymentSummary({
    super.key,
    required this.order,
    required this.amountPaid,
    required this.remaining,
    required this.paymentColor,
    required this.paymentLabel,
    required this.onAddPayment,
  });

  final Order order;
  final double amountPaid;
  final double remaining;
  final Color paymentColor;
  final String paymentLabel;
  final VoidCallback onAddPayment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(VN.total, style: theme.textTheme.titleSmall),
            Text(
              formatVND(order.totalPrice),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (order.shippingFee > 0) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${VN.shippingFee}:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                formatVND(order.shippingFee),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const SectionHeader(VN.payment),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: paymentColor.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: paymentColor.withAlpha(80)),
          ),
          child: Column(
            children: [
              if (order.shippingFee > 0) ...[
                OrderPaymentRow(
                  label: VN.shippingFee,
                  value: formatVND(order.shippingFee),
                  valueStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              OrderPaymentRow(
                label: VN.total,
                value: formatVND(order.totalPrice),
                valueStyle: theme.textTheme.bodyMedium,
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
                  color: remaining > 0 ? paymentColor : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: paymentColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    paymentLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: paymentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddPayment,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(VN.addPayment),
        ),
      ],
    );
  }
}