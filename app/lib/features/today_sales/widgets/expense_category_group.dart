import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/models/expense_summary.dart';
import 'expense_subcategory_line.dart';

/// A parent category with its inclusive total and one line per
/// subcategory in the expense-summary section. Subcategories present in
/// the backend `childrenOf` mapping but absent from
/// [ExpenseCategoryBreakdown.subcategories] are filled in with a zero
/// amount so the full tree is always rendered (AC4).
///
/// Extracted from `expense_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ExpenseCategoryGroup extends StatelessWidget {
  const ExpenseCategoryGroup({
    super.key,
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
            ExpenseSubcategoryLine(
              name: name,
              amount: amountByName[name] ?? 0,
            ),
        ],
      ),
    );
  }
}