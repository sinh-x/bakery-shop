import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final formattedTimestamp = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(event.timestamp.toLocal());
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
              '${data.category} • ${data.paymentMethod} • ${data.paymentSource}',
            ),
            Text(
              '${VN.expenseLoggedByLabel}: ${event.loggedBy.isNotEmpty ? event.loggedBy : '—'} • ${VN.expensePaidByNameLabel}: ${data.paidByName.isNotEmpty ? data.paidByName : '—'}',
            ),
            Text(formattedTimestamp),
            if (data.reimbursed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  label: const Text(VN.reimbursedYes),
                  backgroundColor: Colors.green.shade100,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              )
            else if (data.paymentSource == VN.paymentSourceStaffAdvance)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  label: const Text(VN.reimbursedNo),
                  backgroundColor: Colors.orange.shade100,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (data.vendor.isNotEmpty)
              Text('${VN.expenseVendorLabel}: ${data.vendor}'),
            if (data.note.isNotEmpty)
              Text('${VN.expenseNoteLabel}: ${data.note}'),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(onPressed: onEdit, child: const Text(VN.editEvent)),
                TextButton(
                  onPressed: onDelete,
                  child: const Text(VN.deleteEvent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
