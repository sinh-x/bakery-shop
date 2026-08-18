import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// The `Chưa phân loại` (uncategorized) trailing line, shown only when
/// the backend reports a positive uncategorized total in the
/// expense-summary section.
///
/// Extracted from `expense_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ExpenseUncategorizedLine extends StatelessWidget {
  const ExpenseUncategorizedLine({super.key, required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(SharedLabels.todaySalesExpenseUncategorized, style: style),
          Text(formatVND(amount), style: style),
        ],
      ),
    );
  }
}