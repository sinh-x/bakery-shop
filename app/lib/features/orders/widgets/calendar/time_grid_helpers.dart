import 'package:flutter/material.dart';

import 'week_day_layout_constants.dart';

/// Horizontal line marking the current time position within the time grid.
/// Only renders when [visible] is true (current time is within the grid
/// range and the displayed day/week contains today).
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2). This is an
/// implementation-detail widget of the day/week calendar views and is not
/// intended for reuse outside the calendar grids.
class CurrentTimeLine extends StatelessWidget {
  const CurrentTimeLine({
    super.key,
    required this.visible,
    required this.topOffset,
  });

  final bool visible;
  final double topOffset;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(height: 2, color: color),
          ),
        ],
      ),
    );
  }
}

/// Calculates the Y offset of the current time within the grid, or null if
/// the current time falls outside the 6:00–21:00 range.
///
/// Grid layout: header (44px) + unscheduled row (72px) + hour rows (64px
/// each, 16 slots from 6:00 to 21:00).
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2).
double? currentTimeGridOffset() {
  final now = DateTime.now();
  final hour = now.hour;
  final minute = now.minute;
  if (hour < 6 || hour >= 21) return null;
  final slotIndex = hour - 6;
  final fraction = minute / 60.0;
  return WeekDayLayoutConstants.headerHeight +
      WeekDayLayoutConstants.unscheduledRowHeight +
      (slotIndex + fraction) * WeekDayLayoutConstants.hourRowHeight;
}

/// Whether today falls within the given list of week [days].
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2).
bool isTodayInWeek(List<DateTime> days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return days.any((d) =>
      d.year == today.year &&
      d.month == today.month &&
      d.day == today.day);
}

/// Whether [date] is today.
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2).
bool isTodayDate(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}