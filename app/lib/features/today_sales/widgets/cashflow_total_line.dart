import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

/// A labeled amount line used for the inflow / outflow / net totals in the
/// cashflow-summary section.
///
/// Extracted from `cashflow_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashflowTotalLine extends StatelessWidget {
  const CashflowTotalLine({
    super.key,
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = emphasize
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.titleMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: labelStyle, maxLines: 1),
        ),
        Text(formatVND(amount), style: valueStyle),
      ],
    );
  }
}