import 'package:flutter/material.dart';

import '../../../data/models/cashflow_summary.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import 'cashflow_summary_body.dart';
import 'cashflow_summary_empty_state.dart';

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
/// row rendering to extracted widgets under `widgets/` (see
/// [CashflowSummaryBody], [CashflowTotalLine],
/// [CashflowSupplierCategoryGroup], [CashflowSubcategoryLine],
/// [CashflowUncategorizedLine], [CashflowSummaryEmptyState]). All
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
          const CashflowSummaryEmptyState()
        else
          CashflowSummaryBody(summary: data),
      ],
    );
  }

  bool _isEmpty(CashflowSummary data) {
    return data.operatingInflow == 0 &&
        data.operatingOutflow == 0 &&
        data.netOperatingCashFlow == 0;
  }
}