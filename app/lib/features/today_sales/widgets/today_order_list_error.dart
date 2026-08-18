import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Error-state placeholder with a retry affordance, shown when the orders
/// fetch fails and no cached orders are available.
///
/// Extracted from `today_order_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class TodayOrderListError extends StatelessWidget {
  const TodayOrderListError({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SharedLabels.errorLoading),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text(SharedLabels.retry),
            ),
          ],
        ),
      ),
    );
  }
}