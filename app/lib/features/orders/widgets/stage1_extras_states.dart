import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';

/// Loading skeleton shown while the `phu_kien` catalog products are being
/// fetched for the Stage 1 extras section (DG-214 Phase 6, NFR-2).
///
/// Renders a row of shimmer-like placeholder chips so the layout does not jump
/// when the real chips arrive.
class Stage1ExtrasLoading extends StatelessWidget {
  const Stage1ExtrasLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            OrdersLabels.stage1ExtrasLoading,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state shown when the `phu_kien` catalog products could not be loaded
/// (DG-214 Phase 6, NFR-1). Provides a retry affordance.
class Stage1ExtrasError extends StatelessWidget {
  const Stage1ExtrasError({
    super.key,
    required this.onRetry,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              OrdersLabels.stage1ExtrasLoadError,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }
}