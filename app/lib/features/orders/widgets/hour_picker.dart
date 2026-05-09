import 'package:flutter/material.dart';

import '../../../shared/widgets/vietnamese_labels.dart';

// ── Hour picker dialog (F5) ───────────────────────────────────────────────────

class HourPickerDialog extends StatelessWidget {
  const HourPickerDialog({super.key, required this.initialHour});
  final int initialHour;

  @override
  Widget build(BuildContext context) {
    final controller = ScrollController(
      initialScrollOffset: (initialHour * 48.0).clamp(0.0, 22 * 48.0),
    );
    return AlertDialog(
      title: const Text(VN.dueTime),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 120,
        height: 240,
        child: ListView.builder(
          controller: controller,
          itemCount: 24,
          itemBuilder: (ctx, hour) => ListTile(
            title: Text('$hour:00'), // ignore: prefer_const_constructors
            selected: hour == initialHour,
            onTap: () => Navigator.pop(context, hour),
          ),
        ),
      ),
    );
  }
}

// ── Preset time slot chips (F5) ───────────────────────────────────────────────

class HourPresetChips extends StatelessWidget {
  const HourPresetChips({
    super.key,
    required this.selectedTime,
    required this.onSelected,
  });

  final TimeOfDay? selectedTime;
  final void Function(TimeOfDay) onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          // ignore: prefer_const_constructors
          label: Text('${VN.timeSlotMorning} 8:00'),
          selected: selectedTime != null &&
              selectedTime!.hour == 8 &&
              selectedTime!.minute == 0,
          onSelected: (_) => onSelected(const TimeOfDay(hour: 8, minute: 0)),
        ),
        ChoiceChip(
          // ignore: prefer_const_constructors
          label: Text('${VN.timeSlotAfternoon} 14:00'),
          selected: selectedTime != null &&
              selectedTime!.hour == 14 &&
              selectedTime!.minute == 0,
          onSelected: (_) => onSelected(const TimeOfDay(hour: 14, minute: 0)),
        ),
        ChoiceChip(
          // ignore: prefer_const_constructors
          label: Text('${VN.timeSlotEvening} 18:00'),
          selected: selectedTime != null &&
              selectedTime!.hour == 18 &&
              selectedTime!.minute == 0,
          onSelected: (_) => onSelected(const TimeOfDay(hour: 18, minute: 0)),
        ),
      ],
    );
  }
}
