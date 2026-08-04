import 'package:flutter/material.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/orders.dart';
import 'calendar/compact_mini_order_card.dart';
import 'calendar/compact_order_chips.dart';
import 'calendar/day_header.dart';
import 'calendar/slot_count_badge.dart';
import 'calendar/week_day_layout_constants.dart';

export 'calendar/time_grid_helpers.dart'
    show CurrentTimeLine, currentTimeGridOffset, isTodayInWeek, isTodayDate;

/// Sub-widgets extracted from [DeliveryWeekCalendarView] to keep the main
/// view widget under the 200-line Flutter coding-standards limit (NFR2).
/// These are implementation detail widgets and not intended for reuse
/// outside the week calendar view (DG-306 Phase 2).
///
/// CQ-1 (DG-329 Phase 5.6-c1 review remediation): the compact calendar
/// widgets `SlotCountBadge`, `CompactOrderChips`, and `CompactMiniOrderCard`
/// were extracted to `calendar/` subdirectory files to bring this file
/// under the 200-line widget threshold. `CurrentTimeLine` and the
/// `currentTimeGridOffset` / `isTodayInWeek` / `isTodayDate` helpers were
/// likewise moved to `calendar/time_grid_helpers.dart`; this file re-exports
/// them so existing importers are unaffected.

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
/// Pinned outside the horizontal scroll area (FR4/AC5) so it remains visible
/// during horizontal scroll.
class WeekHourLabelColumn extends StatelessWidget {
  const WeekHourLabelColumn({super.key, required this.theme});
  final ThemeData theme;

  /// Fixed width of the pinned time label column.
  static const double width = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          const SizedBox(height: WeekDayLayoutConstants.headerHeight),
          const SizedBox(height: WeekDayLayoutConstants.unscheduledRowHeight),
          ...OrdersLabels.deliveryTimeSlots.map((slot) => SizedBox(
                height: WeekDayLayoutConstants.hourRowHeight,
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
          DayHeader(date: date, isToday: isToday, theme: theme),
          _UnscheduledRow(
            orders: unscheduled ?? const [],
            theme: theme,
          ),
          ...OrdersLabels.deliveryTimeSlots.map((slot) => _HourRow(
                orders: ordersBySlot[slot],
                height: WeekDayLayoutConstants.hourRowHeight,
                theme: theme,
              )),
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
      height: WeekDayLayoutConstants.unscheduledRowHeight,
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
                        .map((o) => CompactMiniOrderCard(order: o))
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
    if (orders == null || orders!.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
      );
    }
    final list = orders!;
    final showBadge = list.length >= 3;
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBadge) SlotCountBadge(count: list.length, theme: theme),
          if (showBadge) const SizedBox(height: 2),
          Expanded(
            // Use LayoutBuilder to read the actual available width to the
            // row (NFR2). The compact Wrap layout is used when the row is
            // wide enough to fit at least one compact chip at its minimum
            // readable width; otherwise the slot falls back to a scrollable
            // single-column list ("very narrow screens" per the plan). This
            // is more robust than MediaQuery.sizeOf, which reports the full
            // screen/view size rather than the row's actual constrained
            // width (the day columns may be horizontally scrolled and
            // narrower than the screen). In the week calendar each day
            // column is always >= 130px (the grid's min column width), so
            // the compact layout always applies there; in the day calendar
            // the single column fills the remaining screen width, so the
            // scrollable fallback kicks in on very narrow screens.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useCompact =
                    constraints.maxWidth >= OrdersLabels.compactOrderChipMinWidth;
                return useCompact
                    ? CompactOrderChips(orders: list)
                    : ListView(
                        children: list
                            .map((o) => CompactMiniOrderCard(order: o))
                            .toList(growable: false),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
}