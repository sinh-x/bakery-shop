import 'package:flutter/material.dart';

/// A label/value row used inside the payment summary container.
class OrderPaymentRow extends StatelessWidget {
  const OrderPaymentRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: valueStyle ?? theme.textTheme.bodySmall),
      ],
    );
  }
}