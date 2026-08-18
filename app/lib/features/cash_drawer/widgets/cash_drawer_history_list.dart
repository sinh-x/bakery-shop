import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'cash_drawer_history_card.dart';

/// Scrollable daily drawer history list (FR10 / AC10, updated by DG-347
/// Phase 5 and DG-363 Phase 4).
///
/// Each entry shows the open/close date, opening balance, expected
/// balance, counted amount, and discrepancy with a
/// surplus/shortage/exact chip. DG-347 Phase 5 removed the per-accumulator
/// rows (cash sales, owner in/out, cash expenses); the expected balance is
/// now the single source of truth from the journal-derived backend value.
/// When present, the [CashDrawer.closingBalance] is shown for closed
/// drawers.
///
/// DG-363 Phase 4 / FR7: closed drawers render a [CashDrawerBreakdownCard]
/// built from the persisted [CashDrawer.breakdownSnapshot] (embedded in the
/// `/history` response, Phase 2). The snapshot is the source of truth for
/// closed drawers — the card renders without a new network request to
/// /transactions (NFR1). Drawers with no snapshot (closed before the v097
/// migration and not backfilled) render an "N/A" placeholder
/// ([CashDrawerLabels.cashDrawerBreakdownSnapshotNa]) instead of the card. Open drawers
/// in history do not render a breakdown.
///
/// DG-343 Phase 3 FR4/AC2: when [onTapClosedDrawer] is provided, tapping a
/// closed drawer's card navigates to its transaction detail view. Open
/// drawer rows are not tappable (the transaction tab covers the active
/// drawer).
class CashDrawerHistoryList extends StatelessWidget {
  const CashDrawerHistoryList({
    super.key,
    required this.items,
    this.onTapClosedDrawer,
  });

  final List<CashDrawer> items;

  /// DG-343 Phase 3 FR4/AC2: callback invoked when the user taps a closed
  /// drawer row. When `null`, rows are not tappable (preserves the original
  /// behaviour used by tests that don't pass a callback).
  final void Function(CashDrawer drawer)? onTapClosedDrawer;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            CashDrawerLabels.cashDrawerHistory,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) => CashDrawerHistoryCard(
        drawer: items[index],
        onTapClosedDrawer: onTapClosedDrawer,
      ),
    );
  }
}