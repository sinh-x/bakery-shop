import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Empty-state placeholder shown when the period has no expenses
/// (e.g. no orders in the selected week/month) in the expense-summary
/// section.
///
/// Extracted from `expense_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ExpenseSummaryEmptyState extends StatelessWidget {
  const ExpenseSummaryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                color: theme.colorScheme.outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  SharedLabels.todaySalesExpenseEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}