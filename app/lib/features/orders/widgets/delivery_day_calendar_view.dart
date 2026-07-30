import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'delivery_week_calendar_components.dart';

/// Single-day time grid view (DG-306 Phase 2 extension). Renders one day
/// column (the selected [date]) × 16 hour rows (6:00–21:00) with an
/// unscheduled row at the top and a current-time indicator line.
class DeliveryDayCalendarView extends ConsumerStatefulWidget {
  const DeliveryDayCalendarView({
    super.key,
    required this.orders,
    required this.onRefresh,
    this.initialDate,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;

  /// Optional initial focus date (FR2/AC2). When null or today, the view
  /// defaults to today — matching the pre-existing behavior.
  final DateTime? initialDate;

  @override
  ConsumerState<DeliveryDayCalendarView> createState() =>
      _DeliveryDayCalendarViewState();
}

class _DeliveryDayCalendarViewState
    extends ConsumerState<DeliveryDayCalendarView> {
  late DateTime _date = widget.initialDate ?? DateTime.now();

  void _shift(int days) => setState(() {
        _date = _date.add(Duration(days: days));
      });

  void _goToday() => setState(() {
        _date = DateTime.now();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = groupDeliveryOrdersByDayAndSlot(widget.orders);
    final dayKey = _formatDayKey(_date);
    final today = DateTime.now();
    final todayKey = _formatDayKey(today);
    final ordersBySlot = <String, List<Order>>{};
    grouped.forEach((key, orders) {
      if (key.day == dayKey) ordersBySlot[key.slot] = orders;
    });

    final timeLineOffset = currentTimeGridOffset();
    final showTimeLine =
        timeLineOffset != null && isTodayDate(_date);

    return Column(
      children: [
        _DayCalendarNav(
          date: _date,
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
          onToday: _goToday,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: SingleChildScrollView(
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WeekHourLabelColumn(theme: theme),
                      Expanded(
                        child: WeekDayColumn(
                          date: _date,
                          dayKey: dayKey,
                          isToday: dayKey == todayKey,
                          ordersBySlot: ordersBySlot,
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                  CurrentTimeLine(
                    visible: showTimeLine,
                    topOffset: timeLineOffset ?? 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

class _DayCalendarNav extends StatelessWidget {
  const _DayCalendarNav({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime date;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = isTodayDate(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: OrdersLabels.deliveryDayPrevTooltip,
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                OrdersLabels.deliveryDayLabel(date),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isToday ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: OrdersLabels.deliveryDayNextTooltip,
            onPressed: onNext,
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: isToday ? null : onToday,
            child: const Text(OrdersLabels.deliveryDayToday),
          ),
        ],
      ),
    );
  }
}
