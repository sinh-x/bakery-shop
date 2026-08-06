import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'cash_drawer_breakdown_card.dart';
import 'cash_drawer_breakdown_snapshot.dart';

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
/// ([VN.cashDrawerBreakdownSnapshotNa]) instead of the card. Open drawers
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
            VN.cashDrawerHistory,
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
      itemBuilder: (context, index) => _HistoryCard(
        drawer: items[index],
        onTapClosedDrawer: onTapClosedDrawer,
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.drawer, this.onTapClosedDrawer});

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
              '${VN.cashDrawerExpectedBalance}: ${formatVND(drawer.expectedBalance.toDouble())}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            _DiscrepancyChip(discrepancy: drawer.discrepancy),
          ],
        ),
        trailing: Text(
          drawer.isClosed
              ? VN.cashDrawerStatusClosed
              : VN.cashDrawerStatusOpen,
          style: theme.textTheme.labelSmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  label: VN.cashDrawerOpeningBalance,
                  value: drawer.openingBalance,
                ),
                if (drawer.closingBalance != null)
                  _DetailRow(
                    label: VN.cashDrawerClosingBalance,
                    value: drawer.closingBalance ?? 0,
                  ),
                const Divider(height: 16),
                _DetailRow(
                  label: VN.cashDrawerExpectedBalance,
                  value: drawer.expectedBalance,
                  emphasize: true,
                ),
                _DetailRow(
                  label: VN.cashDrawerCountedAmount,
                  value: drawer.countedAmount ?? 0,
                ),
                _DetailRow(
                  label: VN.cashDrawerDiscrepancy,
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
                    const _SnapshotUnavailable()
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
                      label: const Text(VN.cashDrawerTransactionsTab),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            formatVND(value.toDouble()),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: emphasize ? FontWeight.bold : null,
              color: value < 0 ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscrepancyChip extends StatelessWidget {
  const _DiscrepancyChip({required this.discrepancy});

  final int? discrepancy;

  @override
  Widget build(BuildContext context) {
    if (discrepancy == null) return const SizedBox.shrink();
    final value = discrepancy!;
    final label = value == 0
        ? VN.cashDrawerExact
        : value > 0
            ? VN.cashDrawerSurplus
            : VN.cashDrawerShortage;
    final color = value == 0
        ? Colors.grey.shade700
        : value > 0
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label (${formatVND(value.toDouble())})',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// DG-363 Phase 4 / FR7: placeholder rendered in place of the breakdown
/// card for closed drawers that have no persisted snapshot (closed before
/// the v097 migration and not backfilled). Shows the
/// [VN.cashDrawerBreakdownSnapshotNa] label so the user understands the
/// breakdown is unavailable rather than empty.
class _SnapshotUnavailable extends StatelessWidget {
  const _SnapshotUnavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            VN.cashDrawerBreakdownTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            VN.cashDrawerBreakdownSnapshotNa,
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