import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';
import 'section_header.dart';

class OrderPaymentSection extends StatelessWidget {
  const OrderPaymentSection({
    super.key,
    required this.amountPaid,
    required this.totalPrice,
    this.mode = OrderPaymentSectionMode.readOnly,
    this.onAddPayment,
    this.paymentMethod,
  });

  final double amountPaid;
  final double totalPrice;
  final OrderPaymentSectionMode mode;
  final VoidCallback? onAddPayment;
  final String? paymentMethod;

  double get _remaining => totalPrice - amountPaid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paymentColor = amountPaid >= totalPrice
        ? Colors.green
        : amountPaid > 0
            ? Colors.orange
            : theme.colorScheme.error;
    final paymentLabel = amountPaid >= totalPrice
        ? VN.paid
        : amountPaid > 0
            ? VN.partialPaid
            : VN.unpaid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(VN.payment),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: paymentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                paymentLabel,
                style: TextStyle(
                  color: paymentColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            if (paymentMethod != null) ...[
              const SizedBox(width: 8),
              Icon(
                paymentMethod == 'transfer' ? Icons.qr_code : Icons.money,
                size: 16,
                color: Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                paymentMethod == 'transfer' ? VN.methodTransfer : VN.methodCash,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _buildAmountRow(VN.amountPaidLabel, formatVND(amountPaid), theme),
        const SizedBox(height: 4),
        _buildAmountRow(
          VN.remainingLabel,
          formatVND(_remaining),
          theme,
          color: _remaining > 0 ? theme.colorScheme.error : Colors.green,
        ),
        if (mode == OrderPaymentSectionMode.editable && onAddPayment != null && _remaining > 0) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAddPayment,
            icon: const Icon(Icons.add, size: 18),
            label: const Text(VN.payment),
          ),
        ],
      ],
    );
  }

  Widget _buildAmountRow(String label, String value, ThemeData theme, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

enum OrderPaymentSectionMode { editable, readOnly }
