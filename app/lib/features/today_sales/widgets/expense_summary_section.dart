import 'package:flutter/material.dart';

import '../../../data/models/expense_summary.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import 'expense_summary_body.dart';
import 'expense_summary_empty_state.dart';

/// Expense-summary section for the Today Sales screen
/// (DG-386 Phase 8 / FR4 / AC4).
///
/// Renders the total expenses plus the full parent/child category tree
/// returned by `GET /api/reports/expense-summary` (Phase 3). Each parent
/// category shows its inclusive total and one line per subcategory. The
/// complete subcategory tree from `expense_categories` is rendered even
/// when a subcategory had zero expenses in the period — the backend
/// `childrenOf` mapping supplies the canonical child names, and missing
/// subcategories are filled in with a zero amount so the tree is always
/// complete (AC4 — "full category/subcategory tree").
///
/// An `Chưa phân loại` (uncategorized) line is appended when expenses
/// could not be attributed to any category.
///
/// The widget is a pure presentational [StatelessWidget] that receives an
/// already-fetched [ExpenseSummary]; the owning tab body owns the
/// [expenseSummaryProvider] lifecycle. Loading/error states are handled
/// by the caller so this widget only renders the data or empty state.
///
/// Coding standards (NFR2): the section widget is ≤300 lines and delegates
/// row rendering to extracted widgets under `widgets/` (see
/// [ExpenseSummaryBody], [ExpenseCategoryGroup],
/// [ExpenseSubcategoryLine], [ExpenseUncategorizedLine],
/// [ExpenseSummaryEmptyState]). All user-facing text uses
/// [SharedLabels] (NFR4 — no inline VN strings).
class ExpenseSummarySection extends StatelessWidget {
  const ExpenseSummarySection({
    super.key,
    required this.summary,
  });

  /// Expense-summary report to render. When `null` the caller should
  /// render a loading indicator instead; when the report has no expenses
  /// this widget renders the empty state
  /// ([SharedLabels.todaySalesExpenseEmpty]).
  final ExpenseSummary? summary;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesExpenseSection),
        const SizedBox(height: 8),
        if (data == null || _isEmpty(data))
          const ExpenseSummaryEmptyState()
        else
          ExpenseSummaryBody(summary: data),
      ],
    );
  }

  bool _isEmpty(ExpenseSummary data) {
    return data.totalExpenses == 0 &&
        data.categories.isEmpty &&
        data.uncategorized == 0;
  }
}