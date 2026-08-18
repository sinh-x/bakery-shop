import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/cash_drawer.dart';

/// DG-363 Phase 4 / FR7: placeholder rendered in place of the breakdown
/// card for closed drawers that have no persisted snapshot (closed before
/// the v097 migration and not backfilled). Shows the
/// [CashDrawerLabels.cashDrawerBreakdownSnapshotNa] label so the user
/// understands the breakdown is unavailable rather than empty.
///
/// Extracted from `cash_drawer_history_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerSnapshotUnavailable extends StatelessWidget {
  const CashDrawerSnapshotUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            CashDrawerLabels.cashDrawerBreakdownTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            CashDrawerLabels.cashDrawerBreakdownSnapshotNa,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}