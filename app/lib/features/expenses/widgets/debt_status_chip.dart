import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';

/// Shared debt status chip used by the outstanding debts list (DG-212 Phase 4)
/// and the expense history card (DG-212 Phase 3).
///
/// Renders [SizedBox.shrink] when [status] is [ExpenseDebtStatus.none] so the
/// chip can be placed unconditionally for both debt and non-debt rows.
class DebtStatusChip extends StatelessWidget {
  const DebtStatusChip({super.key, required this.status});

  final ExpenseDebtStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ExpenseDebtStatus.paid => (VN.debtStatusPaid, Colors.green.shade100),
      ExpenseDebtStatus.partial => (VN.debtStatusPartial, Colors.amber.shade100),
      ExpenseDebtStatus.unpaid => (VN.debtStatusUnpaid, Colors.orange.shade100),
      ExpenseDebtStatus.none => ('', null),
    };
    if (status == ExpenseDebtStatus.none) return const SizedBox.shrink();
    return Chip(
      label: Text(label),
      backgroundColor: color,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}