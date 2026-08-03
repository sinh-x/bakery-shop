import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Status card for the active (open) cash drawer (FR4 / AC6).
///
/// Renders the opening balance, auto-linked cash sales, owner in/out,
/// cash expenses, and the real-time expected balance. The expected balance
/// is the backend-computed value (`opening + cashSales + ownerIn - ownerOut
/// - cashExpenses + tienRutIn - tienRutOut`) — the client does not recompute it
/// (avoids drift).
class CashDrawerStatusCard extends StatelessWidget {
  const CashDrawerStatusCard({super.key, required this.drawer});

  final CashDrawer drawer;

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
              value: drawer.openingBalance,
            ),
            _BalanceRow(
              label: VN.cashDrawerCashSales,
              value: drawer.cashSales,
            ),
            // DG-341 Phase 4.4 FR6/AC6: tien rut rows between cashSales and
            // ownerIn. Tien rut in is cash held for safekeeping (positive
            // contribution to expected balance); tien rut out is cash
            // returned at delivery (negative contribution).
            _BalanceRow(
              label: VN.cashDrawerTienRutIn,
              value: drawer.tienRutIn,
            ),
            _BalanceRow(
              label: VN.cashDrawerTienRutOut,
              value: -drawer.tienRutOut,
            ),
            _BalanceRow(
              label: VN.cashDrawerOwnerIn,
              value: drawer.ownerIn,
            ),
            _BalanceRow(
              label: VN.cashDrawerOwnerOut,
              value: -drawer.ownerOut,
            ),
            _BalanceRow(
              label: VN.cashDrawerCashExpenses,
              value: -drawer.cashExpenses,
            ),
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
            // row below the expected balance. The journal balance may
            // differ from the computed expected balance between a mutation
            // and the next read; surfacing both supports reconciliation.
            if (drawer.accountingBalance1101 > 0) ...[
              const SizedBox(height: 4),
              _BalanceRow(
                label: VN.cashDrawerReferenceBalance,
                value: drawer.accountingBalance1101,
              ),
            ],
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