import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/delivery_helpers.dart';

/// Sub-widgets extracted from [DeliveryWeekCalendarView] to keep the main
/// view widget under the 200-line Flutter coding-standards limit (NFR2).
/// These are implementation detail widgets and not intended for reuse
/// outside the week calendar view (DG-306 Phase 2).

/// Week navigation bar: prev/next arrows, week range label, "Hôm nay" button.
class WeekCalendarNav extends StatelessWidget {
  const WeekCalendarNav({
    super.key,
    required this.weekStart,
    required this.weekEnd,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: OrdersLabels.deliveryWeekPrevTooltip,
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                OrdersLabels.deliveryWeekRangeLabel(weekStart, weekEnd),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: OrdersLabels.deliveryWeekNextTooltip,
            onPressed: onNext,
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onToday,
            child: const Text(OrdersLabels.deliveryWeekToday),
          ),
        ],
      ),
    );
  }
}

/// Fixed-width leftmost column with hour-row labels ("6:00" … "21:00").
class WeekHourLabelColumn extends StatelessWidget {
  const WeekHourLabelColumn({super.key, required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          const SizedBox(height: WeekDayColumn.headerHeight),
          ...OrdersLabels.deliveryTimeSlots.map((slot) => SizedBox(
                height: WeekDayColumn.hourRowHeight,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, right: 6),
                    child: Text(
                      slot,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

/// One day column in the week grid: header + unscheduled row + hour rows.
class WeekDayColumn extends StatelessWidget {
  const WeekDayColumn({
    super.key,
    required this.date,
    required this.dayKey,
    required this.isToday,
    required this.ordersBySlot,
    required this.theme,
  });

  final DateTime date;
  final String dayKey;
  final bool isToday;
  final Map<String, List<Order>> ordersBySlot;
  final ThemeData theme;

  static const double headerHeight = 44.0;
  static const double hourRowHeight = 64.0;
  static const double unscheduledRowHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final unscheduled = ordersBySlot[OrdersLabels.deliveryCalendarNoSlot];
    // Always render the unscheduled row (even when empty) so hour rows stay
    // vertically aligned across all 7 day columns.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
        color: isToday ? theme.colorScheme.primary.withAlpha(15) : null,
      ),
      child: Column(
        children: [
          _DayHeader(date: date, isToday: isToday, theme: theme),
          _UnscheduledRow(
            orders: unscheduled ?? const [],
            theme: theme,
          ),
          ...OrdersLabels.deliveryTimeSlots.map((slot) => _HourRow(
                orders: ordersBySlot[slot],
                height: hourRowHeight,
                theme: theme,
              )),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.isToday, required this.theme});
  final DateTime date;
  final bool isToday;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final header = OrdersLabels.deliveryWeekdayHeaders[date.weekday - 1];
    final accent = isToday ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Container(
      height: WeekDayColumn.headerHeight,
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

class _UnscheduledRow extends StatelessWidget {
  const _UnscheduledRow({required this.orders, required this.theme});
  final List<Order> orders;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasOrders = orders.isNotEmpty;
    return Container(
      height: WeekDayColumn.unscheduledRowHeight,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      decoration: BoxDecoration(
        color: hasOrders
            ? theme.colorScheme.surfaceContainerHighest.withAlpha(80)
            : null,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: hasOrders
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  OrdersLabels.deliveryWeekUnscheduled,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: ListView(
                    children: orders
                        .map((o) => _MiniOrderCard(order: o))
                        .toList(growable: false),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.orders,
    required this.height,
    required this.theme,
  });
  final List<Order>? orders;
  final double height;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: orders == null || orders!.isEmpty
          ? const SizedBox.shrink()
          : ListView(
              children: orders!
                  .map((o) => _MiniOrderCard(order: o))
                  .toList(growable: false),
            ),
    );
  }
}

class _MiniOrderCard extends StatelessWidget {
  const _MiniOrderCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final slot = deriveTimeSlot(order.dueTime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: statusColor.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/orders/${order.orderRef}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        order.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (slot != null)
                        Text(
                          slot,
                          maxLines: 1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}