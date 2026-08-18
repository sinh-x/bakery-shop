import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Empty-state placeholder shown when there are no orders due today.
///
/// Extracted from `today_order_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class TodayOrderListEmpty extends StatelessWidget {
  const TodayOrderListEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          SharedLabels.todaySalesEmptyOrders,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}