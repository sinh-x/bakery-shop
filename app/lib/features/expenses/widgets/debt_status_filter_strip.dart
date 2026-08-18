import 'package:bakery_app/features/expenses/widgets/expense_filter_card.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:flutter/material.dart';

/// Horizontal strip of debt status filter chips used by the outstanding
/// debts list screen (DG-212 Phase 4 — FR7).
///
/// Renders a leading label followed by one [FilterChip] per
/// [ExpenseDebtStatusFilter] value. Invokes [onChanged] when a chip is
/// selected.
class DebtStatusFilterStrip extends StatelessWidget {
  const DebtStatusFilterStrip({
    super.key,
    required this.status,
    required this.onChanged,
  });

  final ExpenseDebtStatusFilter status;
  final ValueChanged<ExpenseDebtStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 9),
            child: Text(
              ExpensesLabels.debtListFilterStatusLabel,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final value in ExpenseDebtStatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(expenseDebtStatusFilterLabel(value)),
                selected: status == value,
                onSelected: (_) => onChanged(value),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}