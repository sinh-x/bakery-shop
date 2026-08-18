import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/expense_summary.dart';
import '../../../shared/labels/shared.dart';
import 'expense_summary_section.dart';

/// Expense-summary section for the day tab.
///
/// Extracted from `day_tab_body.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DayExpenseSection extends StatelessWidget {
  const DayExpenseSection({super.key, required this.asyncValue});

  final AsyncValue<ExpenseSummary> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (summary) => ExpenseSummarySection(summary: summary),
      loading: () => const ExpenseSummarySection(summary: null),
      error: (_, _) => Center(
        child: Text(
          SharedLabels.errorLoading,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}