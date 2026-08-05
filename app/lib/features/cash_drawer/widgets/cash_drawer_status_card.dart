import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer.dart';
import '../../../data/models/cash_drawer_transaction.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'cash_drawer_breakdown_card.dart';

/// Status card for the active (open) cash drawer (FR4 / AC6, updated by
/// DG-347 Phase 5 and DG-354 Phase 4).
///
/// Renders the opening balance and the backend-computed expected balance.
/// DG-347 Phase 5 removed the per-accumulator rows (cash sales, owner
/// in/out, cash expenses, tien rut in/out); the expected balance is now
/// the single source of truth from the journal-derived backend value.
/// DG-354 Phase 4 FR7: the opening balance row displays the physical
/// cash count (`countedOpeningBalance`) rather than the accounting
/// `openingBalance`, matching AC6.
class CashDrawerStatusCard extends StatelessWidget {
  const CashDrawerStatusCard({
    super.key,
    required this.drawer,
    this.transactions = const [],
  });

  final CashDrawer drawer;

  /// Transactions for this drawer, used to render the categorized
  /// in/out breakdown (DG-359 Phase 2 / FR6). Defaults to empty so the
  /// card renders an all-zero breakdown (FR5) when no transaction data
  /// is available yet.
  final List<CashDrawerTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.point_of_sale,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${VN.cashDrawerStatusOpen} • ${formatDisplayDate(drawer.openedAt)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusChip(isOpen: drawer.isOpen),
              ],
            ),
            const Divider(height: 24),
            _BalanceRow(
              label: VN.cashDrawerOpeningBalance,
              // DG-354 Phase 4 FR7/AC6: display the physical cash count
              // (countedOpeningBalance) as the opening balance, falling
              // back to the accounting openingBalance for older backends.
              value: drawer.displayedOpeningBalance,
            ),
            // DG-359 Phase 2 FR6: categorized in/out breakdown, fixed
            // position right below the opening balance row.
            const SizedBox(height: 8),
            CashDrawerBreakdownCard(transactions: transactions),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  VN.cashDrawerExpectedBalance,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatVND(drawer.expectedBalance.toDouble()),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            // Phase 4.1 F7: show the 1101 journal balance as an additional
            // row below the expected balance. The journal balance may differ
            // from the computed expected balance between a mutation and the
            // next read; surfacing both supports reconciliation.
            // DG-360 Phase 2 FR3/AC6: render this row at any value (negative,
            // zero, or positive) — the old `> 0` guard hid over-drawn 1101
            // balances. `_BalanceRow` already colors negative values via
            // `colorScheme.error` (NFR1).
            const SizedBox(height: 4),
            _BalanceRow(
              label: VN.cashDrawerReferenceBalance,
              value: drawer.accountingBalance1101,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOpen});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? Colors.green.shade700 : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOpen ? VN.cashDrawerStatusOpen : VN.cashDrawerStatusClosed,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            formatVND(value.toDouble()),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isNegative
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
          ),
        ],
      ),
    );
  }
}