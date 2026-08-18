import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/models/product_breakdown.dart';
import '../../../shared/labels/shared.dart';

/// A single product-breakdown row. Renders name, quantity, revenue (VND),
/// and percentage share. The Others row uses [isOthers] to italicize the
/// name and apply [othersColor] for visual distinction.
///
/// Extracted from `product_breakdown_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductBreakdownRowWidget extends StatelessWidget {
  const ProductBreakdownRowWidget({
    super.key,
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