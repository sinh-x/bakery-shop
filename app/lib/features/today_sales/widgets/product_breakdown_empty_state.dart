import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Empty-state placeholder shown when the period has no product revenue
/// (e.g. no orders in the selected week/month) in the product-breakdown
/// section.
///
/// Extracted from `product_breakdown_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductBreakdownEmptyState extends StatelessWidget {
  const ProductBreakdownEmptyState({super.key});

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