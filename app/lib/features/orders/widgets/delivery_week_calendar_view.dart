import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'delivery_week_calendar_components.dart';

/// Google Calendar-style week time grid (DG-306 Phase 2 — FR3, FR4, FR5,
/// AC1–AC3). Renders 7 day columns (Mon–Sun) × 16 hour rows (6:00–21:00),
/// horizontally scrollable for small screens. Unscheduled orders (no
/// `dueTime`) collapse into a sticky "Chưa có giờ" row at the top of each
/// day column. Week navigation via prev/next arrows + "Hôm nay" button.
///
/// Sub-widgets live in [delivery_week_calendar_components.dart] to keep this
/// widget under the 200-line Flutter coding-standards limit (NFR2).
class DeliveryWeekCalendarView extends ConsumerStatefulWidget {
  const DeliveryWeekCalendarView({
    super.key,
    required this.orders,
    required this.onRefresh,
    this.initialWeekStart,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;

  /// Optional initial week-start (a Monday) to focus on first build
  /// (FR3/AC3). When null, defaults to the week containing today.
  final DateTime? initialWeekStart;

  @override
  ConsumerState<DeliveryWeekCalendarView> createState() =>
      _DeliveryWeekCalendarViewState();
}

class _DeliveryWeekCalendarViewState
    extends ConsumerState<DeliveryWeekCalendarView> {
  late DateTime _weekStart =
      widget.initialWeekStart ?? startOfWeek(DateTime.now());

  void _shift(int weeks) => setState(() {
        _weekStart = _weekStart.add(Duration(days: 7 * weeks));
      });

  void _goToday() => setState(() {
        _weekStart = startOfWeek(DateTime.now());
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = daysOfWeek(_weekStart);
    final grouped = groupDeliveryOrdersByDayAndSlot(widget.orders);
    final today = DateTime.now();
    final todayKey = _formatDayKey(today);

    final timeLineOffset = currentTimeGridOffset();
    final showTimeLine =
        timeLineOffset != null && isTodayInWeek(days);

    return Column(
      children: [
        WeekCalendarNav(
          weekStart: _weekStart,
          weekEnd: days.last,
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
          onToday: _goToday,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WeekHourLabelColumn(theme: theme),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: _gridWidth(context),
                        child: Stack(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...days.map((d) {
                                  final dayKey = _formatDayKey(d);
                                  return Expanded(
                                    child: WeekDayColumn(
                                      date: d,
                                      dayKey: dayKey,
                                      isToday: dayKey == todayKey,
                                      ordersBySlot:
                                          _ordersForDay(grouped, dayKey),
                                      theme: theme,
                                    ),
                                  );
                                }),
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Per-day slot map for [WeekDayColumn] (keyed by slot label, including the
  /// unscheduled marker [OrdersLabels.deliveryCalendarNoSlot]).
  Map<String, List<Order>> _ordersForDay(
    Map<DaySlotKey, List<Order>> grouped,
    String dayKey,
  ) {
    final result = <String, List<Order>>{};
    grouped.forEach((key, orders) {
      if (key.day == dayKey) result[key.slot] = orders;
    });
    return result;
  }

  String _formatDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  /// Wide enough to fit 7 columns at >=130px each on small screens, otherwise
  /// uses the remaining screen width (after the pinned time column) so the
  /// day columns fill the visible scroll area (FR4/NFR1).
  double _gridWidth(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final available = screen - WeekHourLabelColumn.width;
    const minCol = 130.0;
    final computed = available / 7;
    return computed < minCol ? minCol * 7 : available;
  }
}