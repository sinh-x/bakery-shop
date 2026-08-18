import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Header row labeling the four columns of the product-breakdown table:
/// product, quantity, revenue, share.
///
/// Extracted from `product_breakdown_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductBreakdownHeader extends StatelessWidget {
  const ProductBreakdownHeader({super.key});

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