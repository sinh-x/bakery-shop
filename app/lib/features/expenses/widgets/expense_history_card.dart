import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/widgets/debt_status_chip.dart';
import 'package:bakery_app/features/expenses/widgets/expense_history_photo_strip.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:flutter/material.dart';

class ExpenseHistoryCard extends StatelessWidget {
  const ExpenseHistoryCard({
    super.key,
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  final BakeryEvent event;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final data = ExpenseEventMapper.fromEvent(event);
    final formattedTimestamp = formatDisplay(event.timestamp);
    if (data == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatVND(data.amountVnd.toDouble()),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              data.isDebt
                  ? '${data.category} • ${data.paymentMethod} • ${ExpensesLabels.expenseCreditorLabel}: ${data.creditorName}'
                  : '${data.category} • ${data.paymentMethod} • ${data.paymentSource}',
            ),
            Text(
              '${ExpensesLabels.expenseLoggedByLabel}: ${event.loggedBy.isNotEmpty ? event.displayLoggedBy : '—'} • ${ExpensesLabels.expensePaidByNameLabel}: ${data.paidByName.isNotEmpty ? data.paidByName : '—'}',
            ),
            Text(formattedTimestamp),
            if (data.isDebt)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: DebtStatusChip(status: data.debtStatus),
              ),
            if (data.reimbursed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  label: const Text(ExpensesLabels.reimbursedYes),
                  backgroundColor: Colors.green.shade100,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              )
            else if (!data.isDebt &&
                data.paymentSource == ExpensesLabels.paymentSourceStaffAdvance)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  label: const Text(ExpensesLabels.reimbursedNo),
                  backgroundColor: Colors.orange.shade100,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (data.vendor.isNotEmpty)
              Text('${ExpensesLabels.expenseVendorLabel}: ${data.vendor}'),
            if (data.note.isNotEmpty)
              Text('${ExpensesLabels.expenseNoteLabel}: ${data.note}'),
            const SizedBox(height: 8),
            ExpenseHistoryPhotoStrip(eventId: event.id),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: onEdit, child: const Text(EventsLabels.editEvent)),
                TextButton(
                  onPressed: onDelete,
                  child: const Text(EventsLabels.deleteEvent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}
