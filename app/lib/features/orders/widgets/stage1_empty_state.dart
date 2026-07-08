import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';

/// Empty-state widget shown by Stage 1 when no products have been selected.
///
/// Displays a prompt and a (+) button. The (+) button is intentionally not
/// wired to the product picker here — that wiring is Phase 2 (DG-214).
class Stage1EmptyState extends StatelessWidget {
  const Stage1EmptyState({
    super.key,
    required this.onAddProduct,
  });

  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: theme.colorScheme.primary.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              OrdersLabels.stage1EmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              OrdersLabels.stage1EmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text(VN.addProduct),
            ),
          ],
        ),
      ),
    );
  }
}