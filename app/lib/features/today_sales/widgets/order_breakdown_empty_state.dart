import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Empty-state placeholder shown when the period has no order-breakdown
/// cells (e.g. no orders in the selected week/month). Mirrors the
/// product-breakdown empty-state styling.
class OrderBreakdownEmptyState extends StatelessWidget {
  const OrderBreakdownEmptyState({super.key});

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
                  SharedLabels.todaySalesOrderBreakdownEmpty,
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