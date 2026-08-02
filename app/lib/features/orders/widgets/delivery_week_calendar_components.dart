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
          const SizedBox(height: WeekDayColumn.headerHeight),
          const SizedBox(height: WeekDayColumn.unscheduledRowHeight),
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
          if (showBadge) _SlotCountBadge(count: list.length, theme: theme),
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
                    ? _CompactOrderChips(orders: list)
                    : ListView(
                        children: list
                            .map((o) => _MiniOrderCard(order: o))
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

/// Count badge shown at the top of a calendar time-slot row when the slot
/// has 3+ orders (DG-329 Phase 4 / FR5 / AC4). Renders as a small pill with
/// the order count, e.g. "3 đơn".
class _SlotCountBadge extends StatelessWidget {
  const _SlotCountBadge({required this.count, required this.theme});
  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        OrdersLabels.deliverySlotCountBadge(count),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Compact `Wrap`-based layout for order chips in a calendar time-slot row
/// (DG-329 Phase 4 / FR5 / NFR2 / AC4). Renders up to
/// [OrdersLabels.compactOrderChipsPerRow] chips per row, each with a minimum
/// readable width of [OrdersLabels.compactOrderChipMinWidth] pixels. When the
/// available width cannot fit 4 chips, `Wrap` automatically flows extra
/// chips onto subsequent rows. Overflow beyond the row height is clipped.
class _CompactOrderChips extends StatelessWidget {
  const _CompactOrderChips({required this.orders});
  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: orders
            .map((o) => _MiniOrderCard(order: o, compact: true))
            .toList(growable: false),
      ),
    );
  }
}

class _MiniOrderCard extends StatelessWidget {
  const _MiniOrderCard({required this.order, this.compact = false});
  final Order order;

  /// Compact layout variant (DG-329 Phase 4 / FR5 / NFR2): when true, the
  /// card renders with a minimum readable width of
  /// [OrdersLabels.compactOrderChipMinWidth] pixels and is intended for use
  /// inside a `Wrap` (max 4 per row on screens ≥ 480px). When false (the
  /// default), the card fills the available width inside a `ListView`.
  final bool compact;

  /// Resolves the assigned staff display name for the mini-card (DG-329
  /// Phase 2 / FR3 / AC2). The backend already JOINs the real staff name
  /// (including deactivated staff whose `staff` row still exists), so the
  /// common case returns [Order.assignedStaffName] directly. When the name
  /// is empty (staff record deleted), falls back to "NV #`<id>`" using the
  /// id — never the misleading "NV #`<id>` (đã ngưng)" combo.
  String _assignedStaffDisplay(Order o) {
    if (o.assignedStaffName.isNotEmpty) return o.assignedStaffName;
    final id = o.assignedStaffId;
    if (id != null && id.isNotEmpty) return OrdersLabels.assignStaffMissing(id);
    return OrdersLabels.deliveryUnassigned;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final slot = deriveTimeSlot(order.dueTime);
    final card = Material(
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
                    if (order.isAssigned)
                      Text(
                        '${OrdersLabels.deliveryStaffLabel}: ${_assignedStaffDisplay(order)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Text(
                        OrdersLabels.deliveryUnassigned,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: card,
      );
    }
    // Compact variant: enforce minimum readable width (NFR2) so the chip is
    // legible inside the `Wrap` layout. The `SizedBox` provides the lower
    // bound; `Wrap` governs the upper bound by flowing chips to the next
    // row when the available width is exhausted.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: OrdersLabels.compactOrderChipMinWidth,
      ),
      child: card,
    );
  }
}

/// Horizontal line marking the current time position within the time grid.
/// Only renders when [visible] is true (current time is within the grid
/// range and the displayed day/week contains today).
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
double? currentTimeGridOffset() {
  final now = DateTime.now();
  final hour = now.hour;
  final minute = now.minute;
  if (hour < 6 || hour >= 21) return null;
  final slotIndex = hour - 6;
  final fraction = minute / 60.0;
  return WeekDayColumn.headerHeight +
      WeekDayColumn.unscheduledRowHeight +
      (slotIndex + fraction) * WeekDayColumn.hourRowHeight;
}

/// Whether today falls within the given list of week [days].
bool isTodayInWeek(List<DateTime> days) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return days.any((d) =>
      d.year == today.year &&
      d.month == today.month &&
      d.day == today.day);
}

/// Whether [date] is today.
bool isTodayDate(DateTime date) {
  final now = DateTime.now();
  return date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
}
