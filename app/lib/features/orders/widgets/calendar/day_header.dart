import 'package:flutter/material.dart';

import '../../../../shared/labels/orders.dart';
import 'week_day_layout_constants.dart';

/// Day header for a calendar day column: weekday name + date label,
/// highlighted when [isToday].
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2). This is an
/// implementation-detail widget of the day/week calendar grids and is not
/// intended for reuse outside the calendar.
class DayHeader extends StatelessWidget {
  const DayHeader({
    super.key,
    required this.date,
    required this.isToday,
    required this.theme,
  });

  final DateTime date;
  final bool isToday;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final header = OrdersLabels.deliveryWeekdayHeaders[date.weekday - 1];
    final accent =
        isToday ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Container(
      height: WeekDayLayoutConstants.headerHeight,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: isToday ? theme.colorScheme.primary.withAlpha(25) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(header, style: theme.textTheme.labelMedium?.copyWith(color: accent)),
          Text('${date.day}/${date.month}',
              style: theme.textTheme.labelSmall?.copyWith(color: accent)),
        ],
      ),
    );
  }
}