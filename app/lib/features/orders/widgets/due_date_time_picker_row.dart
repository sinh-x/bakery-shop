import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';

class DueDateTimePickerRow extends StatelessWidget {
  const DueDateTimePickerRow({
    super.key,
    this.dueDate,
    this.dueTime,
    this.onDueDateChanged,
    this.onDueTimeChanged,
  });

  final DateTime? dueDate;
  final TimeOfDay? dueTime;
  final ValueChanged<DateTime>? onDueDateChanged;
  final ValueChanged<TimeOfDay>? onDueTimeChanged;

  @override
  Widget build(BuildContext context) {
    final dateStr = dueDate != null
        ? '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
        : OrdersLabels.notSelected;
    final timeStr = dueTime != null
        ? '${dueTime!.hour.toString().padLeft(2, '0')}:${dueTime!.minute.toString().padLeft(2, '0')}'
        : OrdersLabels.notSelected;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: dueDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                onDueDateChanged?.call(picked);
              }
            },
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(dateStr),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final initialTime =
                  dueTime ?? const TimeOfDay(hour: 9, minute: 0);
              final picked = await showTimePicker(
                context: context,
                initialTime: initialTime,
              );
              if (picked != null) {
                onDueTimeChanged?.call(picked);
              }
            },
            icon: const Icon(Icons.access_time, size: 16),
            label: Text(timeStr),
          ),
        ),
      ],
    );
  }
}
