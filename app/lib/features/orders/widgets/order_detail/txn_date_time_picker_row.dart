import 'package:flutter/material.dart';

import '../../../../shared/labels/orders.dart';

/// Date + time picker row for payment transaction create/edit sheets
/// (DG-415 Phase 3 / FR1, FR2, FR7).
///
/// Renders two [OutlinedButton.icon] cells side-by-side: the left opens a
/// [showDatePicker] limited to `2020-01-01 .. today` (FR7 — only past→today
/// dates are selectable), the right opens a [showTimePicker]. The picked
/// values are reported back via [onDateChanged]/[onTimeChanged].
///
/// Unlike [DueDateTimePickerRow] (which is forward-looking for due dates),
/// this widget is backward-looking: `lastDate` is today so staff cannot
/// post-date a payment transaction.
class TxnDateTimePickerRow extends StatelessWidget {
  const TxnDateTimePickerRow({
    super.key,
    required this.dateTime,
    required this.onDateChanged,
    required this.onTimeChanged,
  });

  /// Current picked timestamp (drives both the date and time cell labels).
  final DateTime dateTime;

  /// Called when the user picks a new date. The time component is preserved
  /// by the caller (the notifier merges date+time).
  final ValueChanged<DateTime> onDateChanged;

  /// Called when the user picks a new time. The date component is preserved
  /// by the caller.
  final ValueChanged<TimeOfDay> onTimeChanged;

  static final DateTime _firstDate = DateTime(2020);

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeOfDay = TimeOfDay.fromDateTime(dateTime);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                OrdersLabels.txnDateLabel,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final today = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dateTime.isAfter(today) ? today : dateTime,
                    firstDate: _firstDate,
                    lastDate: today,
                  );
                  if (picked != null) {
                    onDateChanged(picked);
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _formatDate(dateTime),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                OrdersLabels.txnTimeLabel,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: timeOfDay,
                  );
                  if (picked != null) {
                    onTimeChanged(picked);
                  }
                },
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(_formatTime(timeOfDay)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}