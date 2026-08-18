import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

/// A single subcategory line, indented under its parent supplier category in
/// the cashflow-summary section.
///
/// Extracted from `cashflow_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashflowSubcategoryLine extends StatelessWidget {
  const CashflowSubcategoryLine({
    super.key,
    required this.name,
    required this.amount,
  });

  final String name;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name,
              style: valueStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(formatVND(amount), style: valueStyle),
        ],
      ),
    );
  }
}