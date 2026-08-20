import 'package:flutter/material.dart';

import '../../../data/models/product_breakdown.dart';
import 'product_breakdown_header.dart';
import 'product_breakdown_row.dart';

/// Table-like layout for the product breakdown rows.
///
/// Renders a header row ([ProductBreakdownHeader]) followed by one
/// [ProductBreakdownRowWidget] per top product and a final Others row
/// visually separated by a divider. Uses a [Column] of [Row]s rather than a
/// [DataTable] to keep the layout compact on phones and match the existing
/// section-card styling of the Today Sales screen.
///
/// Extracted from `product_breakdown_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductBreakdownTable extends StatelessWidget {
  const ProductBreakdownTable({super.key, required this.breakdown});

  final ProductBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            const ProductBreakdownHeader(),
            const Divider(height: 16),
            for (final product in breakdown.products)
              ProductBreakdownRowWidget(row: product),
            if (breakdown.others.quantity > 0 ||
                breakdown.others.revenue > 0) ...[
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 4),
                child: Divider(height: 1),
              ),
              ProductBreakdownRowWidget(
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