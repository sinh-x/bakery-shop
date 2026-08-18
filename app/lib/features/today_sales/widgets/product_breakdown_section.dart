import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/models/product_breakdown.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';

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
/// row rendering to the private [_ProductBreakdownRow] widget. All
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
          const _EmptyState()
        else
          _ProductBreakdownTable(breakdown: data),
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

/// Table-like layout for the product breakdown rows.
///
/// Renders a header row ([_ProductBreakdownHeader]) followed by one
/// [_ProductBreakdownRow] per top product and a final Others row visually
/// separated by a divider. Uses a [Column] of [Row]s rather than a
/// [DataTable] to keep the layout compact on phones and match the existing
/// section-card styling of the Today Sales screen.
class _ProductBreakdownTable extends StatelessWidget {
  const _ProductBreakdownTable({required this.breakdown});

  final ProductBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            const _ProductBreakdownHeader(),
            const Divider(height: 16),
            for (final product in breakdown.products)
              _ProductBreakdownRow(row: product),
            if (breakdown.others.quantity > 0 ||
                breakdown.others.revenue > 0) ...[
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 4),
                child: Divider(height: 1),
              ),
              _ProductBreakdownRow(
                row: breakdown.others,
                isOthers: true,
                othersColor: theme.colorScheme.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Header row labeling the four columns: product, quantity, revenue, share.
class _ProductBreakdownHeader extends StatelessWidget {
  const _ProductBreakdownHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            SharedLabels.todaySalesProductBreakdownColumnProduct,
            style: style,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            SharedLabels.todaySalesProductBreakdownColumnQuantity,
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            SharedLabels.todaySalesProductBreakdownColumnRevenue,
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            SharedLabels.todaySalesProductBreakdownColumnShare,
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// A single product-breakdown row. Renders name, quantity, revenue (VND),
/// and percentage share. The Others row uses [isOthers] to italicize the
/// name and apply [othersColor] for visual distinction.
class _ProductBreakdownRow extends StatelessWidget {
  const _ProductBreakdownRow({
    required this.row,
    this.isOthers = false,
    this.othersColor,
  });

  final ProductBreakdownRow row;
  final bool isOthers;
  final Color? othersColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: isOthers ? FontWeight.w600 : FontWeight.w500,
      fontStyle: isOthers ? FontStyle.italic : FontStyle.normal,
      color: isOthers ? (othersColor ?? theme.colorScheme.outline) : null,
    );
    final valueStyle = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              isOthers ? SharedLabels.todaySalesProductBreakdownOthers : row.name,
              style: nameStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${row.quantity}',
              style: valueStyle,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              formatVND(row.revenue),
              style: valueStyle,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _formatPercent(row.percentage),
              style: valueStyle?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Formats the revenue share as a percentage string with one decimal
  /// place (e.g. `42.5%`). Zero renders as `0%` to avoid trailing zeros.
  String _formatPercent(double value) {
    if (value == 0) return '0%';
    final rounded = (value * 10).roundToDouble() / 10;
    final text = rounded.toStringAsFixed(rounded % 1 == 0 ? 0 : 1);
    return '$text%';
  }
}

/// Empty-state placeholder shown when the period has no product revenue
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
                  SharedLabels.todaySalesProductBreakdownEmpty,
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