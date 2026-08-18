import 'package:bakery_app/features/expenses/widgets/debt_row.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

/// Card grouping all debts owed to a single creditor, used by the
/// outstanding debts list screen (DG-212 Phase 4 — FR5).
///
/// Shows the creditor name, the per-creditor total owed and debt count,
/// followed by one [DebtRow] per debt entry. Invokes [onOpenSettlement]
/// with the relevant ``event_id`` when a row's settle action is tapped.
class CreditorGroupCard extends StatelessWidget {
  const CreditorGroupCard({
    super.key,
    required this.creditor,
    required this.onOpenSettlement,
  });

  final Map<String, dynamic> creditor;
  final void Function(int eventId) onOpenSettlement;

  @override
  Widget build(BuildContext context) {
    final name = '${creditor['creditor'] ?? ''}';
    final debts = (creditor['debts'] as List?) ?? const <dynamic>[];
    final totalOwed = (creditor['total_owed'] as num?)?.toDouble() ?? 0.0;
    final count = (creditor['count'] as num?)?.toInt() ?? debts.length;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleMedium),
            Text(
              '${ExpensesLabels.debtListCreditorTotal}: ${formatVND(totalOwed)} • ${ExpensesLabels.debtListDebtCount}: $count',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final debt in debts)
              DebtRow(debt: debt as Map<String, dynamic>, onTap: onOpenSettlement),
          ],
        ),
      ),
    );
  }
}