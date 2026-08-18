import 'package:flutter/material.dart';

import '../../../data/models/expense_summary.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

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
/// row rendering to private [_ExpenseCategoryGroup] and
/// [_ExpenseSubcategoryLine] widgets. All user-facing text uses
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
          const _EmptyState()
        else
          _ExpenseSummaryBody(summary: data),
      ],
    );
  }

  bool _isEmpty(ExpenseSummary data) {
    return data.totalExpenses == 0 &&
        data.categories.isEmpty &&
        data.uncategorized == 0;
  }
}

/// Body of the expense summary: total line + card with category groups.
class _ExpenseSummaryBody extends StatelessWidget {
  const _ExpenseSummaryBody({required this.summary});

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
                  _ExpenseCategoryGroup(
                    category: category,
                    childNames: summary.childrenOf[category.name] ??
                        const [],
                  ),
                if (summary.uncategorized > 0)
                  _UncategorizedLine(amount: summary.uncategorized),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A parent category with its inclusive total and one line per
/// subcategory. Subcategories present in the backend `childrenOf` mapping
/// but absent from [ExpenseCategoryBreakdown.subcategories] are filled in
/// with a zero amount so the full tree is always rendered (AC4).
class _ExpenseCategoryGroup extends StatelessWidget {
  const _ExpenseCategoryGroup({
    required this.category,
    required this.childNames,
  });

  final ExpenseCategoryBreakdown category;
  final List<String> childNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Build a name→amount lookup for the subcategories the backend
    // actually reported amounts for, then walk the canonical child-name
    // list from `childrenOf` so zero-amount subcategories still appear.
    final amountByName = <String, double>{
      for (final sub in category.subcategories) sub.name: sub.amount,
    };
    final renderedChildNames = childNames.isNotEmpty
        ? childNames
        : category.subcategories.map((s) => s.name).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatVND(category.amount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          for (final name in renderedChildNames)
            _ExpenseSubcategoryLine(
              name: name,
              amount: amountByName[name] ?? 0,
            ),
        ],
      ),
    );
  }
}

/// A single subcategory line, indented under its parent.
class _ExpenseSubcategoryLine extends StatelessWidget {
  const _ExpenseSubcategoryLine({
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
          Text(
            formatVND(amount),
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}

/// The `Chưa phân loại` (uncategorized) trailing line, shown only when
/// the backend reports a positive uncategorized total.
class _UncategorizedLine extends StatelessWidget {
  const _UncategorizedLine({required this.amount});

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

/// Empty-state placeholder shown when the period has no expenses
/// (e.g. no orders in the selected week/month).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

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