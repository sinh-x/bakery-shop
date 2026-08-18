import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/features/expenses/widgets/debt_status_chip.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:flutter/material.dart';

/// Single outstanding debt row used inside [CreditorGroupCard] on the
/// outstanding debts list screen (DG-212 Phase 4 — FR5).
///
/// Shows the debt summary, amount, settled amount, remaining amount and
/// optional timestamp on the left, and a [DebtStatusChip] plus a settle
/// button on the right. The settle button is enabled only when there is a
/// remaining balance and a valid ``event_id``.
class DebtRow extends StatelessWidget {
  const DebtRow({
    super.key,
    required this.debt,
    required this.onTap,
  });

  final Map<String, dynamic> debt;
  final void Function(int eventId) onTap;

  @override
  Widget build(BuildContext context) {
    final eventId = (debt['event_id'] as num?)?.toInt() ?? 0;
    final amount = (debt['amount_vnd'] as num?)?.toDouble() ?? 0.0;
    final settled = (debt['settled_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = (debt['remaining'] as num?)?.toDouble() ?? 0.0;
    final status = parseDebtStatus('${debt['status'] ?? ''}');
    final timestamp = debt['timestamp'] as String?;
    final summary = '${debt['summary'] ?? ''}';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.isNotEmpty) Text(summary, style: theme.textTheme.bodyMedium),
                Text('${ExpensesLabels.debtListItemAmount}: ${formatVND(amount)}'),
                Text('${ExpensesLabels.debtListItemSettled}: ${formatVND(settled)}'),
                Text('${ExpensesLabels.debtListItemRemaining}: ${formatVND(remaining)}'),
                if (timestamp != null)
                  Text(formatDisplay(parseApiDateTime(timestamp))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DebtStatusChip(status: status),
              const SizedBox(height: 4),
              if (remaining > 0)
                FilledButton.tonal(
                  onPressed: eventId > 0 ? () => onTap(eventId) : null,
                  child: const Text(ExpensesLabels.debtListOpenSettlement),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Parses a backend debt status string into an [ExpenseDebtStatus].
///
/// Recognizes ``paid``, ``partial`` and ``unpaid``; any other value
/// (including the empty string) maps to [ExpenseDebtStatus.none].
ExpenseDebtStatus parseDebtStatus(String value) {
  switch (value) {
    case 'paid':
      return ExpenseDebtStatus.paid;
    case 'partial':
      return ExpenseDebtStatus.partial;
    case 'unpaid':
      return ExpenseDebtStatus.unpaid;
    default:
      return ExpenseDebtStatus.none;
  }
}