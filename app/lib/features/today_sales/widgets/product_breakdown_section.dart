import 'package:flutter/material.dart';

import '../../../data/models/product_breakdown.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import 'product_breakdown_empty_state.dart';
import 'product_breakdown_table.dart';

/// Product-breakdown section for the Today Sales screen
/// (DG-386 Phase 7 / FR3 / AC3).
///
/// Renders the per-product revenue attribution breakdown returned by
/// `GET /api/reports/product-breakdown` (Phase 2): the top 10 products plus
/// a single `Khác` (Others) row, sorted by revenue descending. Each row
/// shows product name, quantity sold, revenue (VND), and revenue share
/// (percentage of `totalRevenue`).
///
/// The widget is a pure presentational [StatelessWidget] that receives an
/// already-fetched [ProductBreakdown]; the owning tab body owns the
/// [productBreakdownProvider] lifecycle. Loading/error states are handled
/// by the caller so this widget only renders the data or empty state.
///
/// Coding standards (NFR2): the section widget is ≤300 lines and delegates
/// row rendering to extracted widgets under `widgets/` (see
/// [ProductBreakdownTable], [ProductBreakdownHeader],
/// [ProductBreakdownRowWidget], [ProductBreakdownEmptyState]). All
/// user-facing text uses [SharedLabels] (NFR4 — no inline VN strings).
class ProductBreakdownSection extends StatelessWidget {
  const ProductBreakdownSection({
    super.key,
    required this.breakdown,
  });

  /// Product-breakdown report to render. When `null` the caller should
  /// render a loading indicator instead; when the report has no products
  /// this widget renders the empty state ([SharedLabels.todaySalesProductBreakdownEmpty]).
  final ProductBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final data = breakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesProductBreakdownSection),
        const SizedBox(height: 8),
        if (data == null || _isEmpty(data))
          const ProductBreakdownEmptyState()
        else
          ProductBreakdownTable(breakdown: data),
      ],
    );
  }

  bool _isEmpty(ProductBreakdown data) {
    final hasProducts = data.products.isNotEmpty ||
        data.others.quantity > 0 ||
        data.others.revenue > 0;
    return !hasProducts;
  }
}