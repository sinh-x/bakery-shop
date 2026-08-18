import 'package:flutter/material.dart';

import '../../../data/models/cashflow_summary.dart';
import '../../../shared/labels/shared.dart';
import 'cashflow_supplier_category_group.dart';
import 'cashflow_total_line.dart';
import 'cashflow_uncategorized_line.dart';

/// Body of the cashflow summary: inflow / outflow / net total lines plus a
/// card with the supplier-outflow category breakdown.
///
/// Extracted from `cashflow_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashflowSummaryBody extends StatelessWidget {
  const CashflowSummaryBody({super.key, required this.summary});

  final CashflowSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CashflowTotalLine(
            label: SharedLabels.todaySalesCashflowInflow,
            amount: summary.operatingInflow,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CashflowTotalLine(
            label: SharedLabels.todaySalesCashflowOutflow,
            amount: summary.operatingOutflow,
          ),
        ),
        CashflowTotalLine(
          label: SharedLabels.todaySalesCashflowNet,
          amount: summary.netOperatingCashFlow,
          emphasize: true,
        ),
        const SizedBox(height: 8),
        if (summary.supplierCategories.isNotEmpty ||
            summary.uncategorizedSupplier > 0)
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  for (final category in summary.supplierCategories)
                    CashflowSupplierCategoryGroup(
                      category: category,
                      childNames: summary.childrenOf[category.name] ??
                          const [],
                    ),
                  if (summary.uncategorizedSupplier > 0)
                    CashflowUncategorizedLine(
                        amount: summary.uncategorizedSupplier),
                ],
              ),
            ),
          ),
      ],
    );
  }
}