import 'package:flutter/material.dart';

import 'package:bakery_app/shared/utils.dart' show formatVND;
import '../../../data/models/cash_drawer.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'cash_drawer_breakdown_card.dart';
import 'cash_drawer_breakdown_snapshot.dart';
import 'cash_drawer_detail_row.dart';
import 'cash_drawer_discrepancy_chip.dart';
import 'cash_drawer_snapshot_unavailable.dart';

/// Expansion card rendered for each closed/open drawer in
/// [CashDrawerHistoryList]. Shows the open/close date, opening balance,
/// expected balance, counted amount, discrepancy, and (for closed drawers)
/// the persisted breakdown snapshot.
///
/// DG-343 Phase 3 FR4/AC2: when [onTapClosedDrawer] is provided and the
/// drawer is closed, the whole card is wrapped in an [InkWell] that fires
/// the callback on tap. Open drawers are never tappable here.
///
/// Extracted from `cash_drawer_history_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerHistoryCard extends StatelessWidget {
  const CashDrawerHistoryCard({
    super.key,
    required this.drawer,
    this.onTapClosedDrawer,
  });

  final CashDrawer drawer;

  /// DG-343 Phase 3 FR4/AC2: when non-null and [drawer] is closed, the whole
  /// card is wrapped in an [InkWell] that fires this callback on tap.
  final void Function(CashDrawer drawer)? onTapClosedDrawer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // DG-343 Phase 3 FR4/AC2: closed drawers are tappable when a callback is
    // provided. Open drawers are never tappable here (the active drawer's
    // transactions are reached via the "Chi tiết giao dịch" tab).
    final canTap = drawer.isClosed && onTapClosedDrawer != null;
    final card = Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(
          formatDisplayDate(drawer.openedAt),
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Row(
          children: [
            Text(
              '${CashDrawerLabels.cashDrawerExpectedBalance}: ${formatVND(drawer.expectedBalance.toDouble())}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            CashDrawerDiscrepancyChip(discrepancy: drawer.discrepancy),
          ],
        ),
        trailing: Text(
          drawer.isClosed
              ? CashDrawerLabels.cashDrawerStatusClosed
              : CashDrawerLabels.cashDrawerStatusOpen,
          style: theme.textTheme.labelSmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CashDrawerDetailRow(
                  label: CashDrawerLabels.cashDrawerOpeningBalance,
                  value: drawer.openingBalance,
                ),
                if (drawer.closingBalance != null)
                  CashDrawerDetailRow(
                    label: CashDrawerLabels.cashDrawerClosingBalance,
                    value: drawer.closingBalance ?? 0,
                  ),
                const Divider(height: 16),
                CashDrawerDetailRow(
                  label: CashDrawerLabels.cashDrawerExpectedBalance,
                  value: drawer.expectedBalance,
                  emphasize: true,
                ),
                CashDrawerDetailRow(
                  label: CashDrawerLabels.cashDrawerCountedAmount,
                  value: drawer.countedAmount ?? 0,
                ),
                CashDrawerDetailRow(
                  label: CashDrawerLabels.cashDrawerDiscrepancy,
                  value: drawer.discrepancy ?? 0,
                  emphasize: true,
                ),
                // DG-363 Phase 4 / FR7: render the persisted breakdown
                // snapshot for closed drawers. The snapshot is embedded in
                // the /history response (Phase 2) and is the source of truth
                // for closed drawers — no new network request to
                // /transactions (NFR1). Drawers with no snapshot (closed
                // before the v097 migration and not backfilled) render an
                // "N/A" placeholder. Open drawers do not render a breakdown
                // here (the active drawer's breakdown lives in the status
                // tab).
                if (drawer.isClosed) ...[
                  const Divider(height: 16),
                  if (drawer.breakdownSnapshot.isEmpty)
                    const CashDrawerSnapshotUnavailable()
                  else
                    CashDrawerBreakdownCard(
                      breakdown:
                          breakdownFromSnapshot(drawer.breakdownSnapshot),
                    ),
                ],
                // DG-343 Phase 3 FR4/AC2: explicit "view transactions"
                // affordance for closed drawers. The [ExpansionTile]
                // header consumes taps to toggle expand/collapse, so this
                // button is the guaranteed tappable entry point to the
                // transaction detail view. It only renders when a callback
                // is provided and the drawer is closed.
                if (canTap) ...[
                  const Divider(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => onTapClosedDrawer!(drawer),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text(CashDrawerLabels.cashDrawerTransactionsTab),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (!canTap) return card;
    // DG-343 Phase 3 FR4/AC2: also wrap the card in an InkWell so tapping
    // the expanded body (outside the header) navigates. The header tap is
    // captured by the ExpansionTile toggle, so the explicit TextButton above
    // is the primary affordance.
    return InkWell(
      onTap: () => onTapClosedDrawer!(drawer),
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }
}