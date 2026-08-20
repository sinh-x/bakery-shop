import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/models/cashflow_summary.dart';
import 'cashflow_subcategory_line.dart';

/// A parent supplier category with its inclusive total and one line per
/// subcategory in the cashflow-summary section. The complete subcategory
/// tree from the backend `childrenOf` mapping is rendered even when a
/// subcategory had zero expenses in the period — missing subcategories are
/// filled in with a zero amount so the tree is always complete (AC5
/// consistency with the expense section / AC4).
///
/// Extracted from `cashflow_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashflowSupplierCategoryGroup extends StatelessWidget {
  const CashflowSupplierCategoryGroup({
    super.key,
    required this.category,
    required this.childNames,
  });

  final CashflowSupplierCategory category;
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
            CashflowSubcategoryLine(
              name: name,
              amount: amountByName[name] ?? 0,
            ),
        ],
      ),
    );
  }
}