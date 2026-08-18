import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/models/expense_summary.dart';
import '../../../shared/labels/shared.dart';
import 'expense_category_group.dart';
import 'expense_uncategorized_line.dart';

/// Body of the expense summary: total line + card with category groups.
///
/// Extracted from `expense_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ExpenseSummaryBody extends StatelessWidget {
  const ExpenseSummaryBody({super.key, required this.summary});

  final ExpenseSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                SharedLabels.todaySalesExpenseTotal,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatVND(summary.totalExpenses),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                for (final category in summary.categories)
                  ExpenseCategoryGroup(
                    category: category,
                    childNames: summary.childrenOf[category.name] ??
                        const [],
                  ),
                if (summary.uncategorized > 0)
                  ExpenseUncategorizedLine(amount: summary.uncategorized),
              ],
            ),
          ),
        ),
      ],
    );
  }
}