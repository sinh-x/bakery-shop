import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/models/cashflow_summary.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';

/// Cashflow-summary section for the Today Sales screen
/// (DG-386 Phase 9 / FR5 / AC5).
///
/// Renders the operating-activities cash-flow summary returned by
/// `GET /api/reports/cashflow-summary` (Phase 4): total operating inflow
/// (cash from customers), total operating outflow (cash paid to suppliers
/// and employees, including shipping releases), and the net operating cash
/// flow. The supplier-outflow side is broken down by expense category with
/// one subcategory line per child, mirroring the [ExpenseSummarySection]
/// tree. The complete subcategory tree from the backend `childrenOf`
/// mapping is rendered even when a subcategory had zero expenses in the
/// period — missing subcategories are filled in with a zero amount so the
/// tree is always complete (AC5 consistency with the expense section /
/// AC4). An `Chưa phân loại` (uncategorized) line is appended when supplier
/// outflow could not be attributed to any category.
///
/// Unlike the drawer-dependent [CashflowBreakdownSection] (DG-374), this
/// widget consumes the [CashflowSummary] model + `cashflowSummaryProvider`
/// from Phase 5, which is computed from journal entries on the bakery's
/// cash accounts — no active cash drawer is required (F2 / AC5).
///
/// The widget is a pure presentational [StatelessWidget] that receives an
/// already-fetched [CashflowSummary]; the owning tab body owns the
/// [cashflowSummaryProvider] lifecycle. Loading/error states are handled
/// by the caller so this widget only renders the data or empty state.
///
/// Coding standards (NFR2): the section widget is ≤300 lines and delegates
/// row rendering to private [_CashflowSupplierCategoryGroup],
/// [_CashflowSubcategoryLine], and [_CashflowTotalLine] widgets. All
/// user-facing text uses [SharedLabels] (NFR4 — no inline VN strings).
class CashflowSummarySection extends StatelessWidget {
  const CashflowSummarySection({
    super.key,
    required this.summary,
  });

  /// Cashflow-summary report to render. When `null` the caller should
  /// render a loading indicator instead; when the report has no operating
  /// activity this widget renders the empty state
  /// ([SharedLabels.todaySalesCashflowEmpty]).
  final CashflowSummary? summary;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesCashflowSection),
        const SizedBox(height: 8),
        if (data == null || _isEmpty(data))
          const _EmptyState()
        else
          _CashflowSummaryBody(summary: data),
      ],
    );
  }

  bool _isEmpty(CashflowSummary data) {
    return data.operatingInflow == 0 &&
        data.operatingOutflow == 0 &&
        data.netOperatingCashFlow == 0;
  }
}

/// Body of the cashflow summary: inflow / outflow / net total lines plus a
/// card with the supplier-outflow category breakdown.
class _CashflowSummaryBody extends StatelessWidget {
  const _CashflowSummaryBody({required this.summary});

  final CashflowSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _CashflowTotalLine(
            label: SharedLabels.todaySalesCashflowInflow,
            amount: summary.operatingInflow,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _CashflowTotalLine(
            label: SharedLabels.todaySalesCashflowOutflow,
            amount: summary.operatingOutflow,
          ),
        ),
        _CashflowTotalLine(
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
                    _CashflowSupplierCategoryGroup(
                      category: category,
                      childNames: summary.childrenOf[category.name] ??
                          const [],
                    ),
                  if (summary.uncategorizedSupplier > 0)
                    _UncategorizedLine(amount: summary.uncategorizedSupplier),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A labeled amount line used for the inflow / outflow / net totals.
class _CashflowTotalLine extends StatelessWidget {
  const _CashflowTotalLine({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = emphasize
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.titleMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: labelStyle, maxLines: 1),
        ),
        Text(formatVND(amount), style: valueStyle),
      ],
    );
  }
}

/// A parent supplier category with its inclusive total and one line per
/// subcategory. The complete subcategory tree from the backend
/// `childrenOf` mapping is rendered even when a subcategory had zero
/// expenses in the period — missing subcategories are filled in with a
/// zero amount so the tree is always complete (AC5 consistency with the
/// expense section / AC4).
class _CashflowSupplierCategoryGroup extends StatelessWidget {
  const _CashflowSupplierCategoryGroup({
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
            _CashflowSubcategoryLine(
              name: name,
              amount: amountByName[name] ?? 0,
            ),
        ],
      ),
    );
  }
}

/// A single subcategory line, indented under its parent supplier category.
class _CashflowSubcategoryLine extends StatelessWidget {
  const _CashflowSubcategoryLine({
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

/// The `Chưa phân loại` (uncategorized) trailing line, shown only when
/// the backend reports a positive uncategorized supplier total.
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
          Text(SharedLabels.todaySalesCashflowUncategorized, style: style),
          Text(formatVND(amount), style: style),
        ],
      ),
    );
  }
}

/// Empty-state placeholder shown when the period has no operating
/// cashflow (e.g. no orders or payments in the selected week/month).
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
                  SharedLabels.todaySalesCashflowEmpty,
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