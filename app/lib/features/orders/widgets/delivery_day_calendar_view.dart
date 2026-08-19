import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../providers/delivery_calendar_notifiers.dart';
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

  /// Optional initial focus date (FR2/AC2). When null (the default from
  /// `DeliveryContent`), the view defaults to today — per FR4/AC3 the day
  /// calendar always anchors to today so the current-time line is visible
  /// on open, even when no orders exist today. Callers may pass an explicit
  /// date to focus a different day (e.g. for deep links); `DeliveryContent`
  /// does not pass this so the today default always applies.
  final DateTime? initialDate;

  @override
  ConsumerState<DeliveryDayCalendarView> createState() =>
      _DeliveryDayCalendarViewState();
}

class _DeliveryDayCalendarViewState
    extends ConsumerState<DeliveryDayCalendarView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Defer the seed to avoid modifying a provider during the build phase.
    Future.microtask(() {
      if (mounted) {
        ref
            .read(deliveryDayCalendarProvider.notifier)
            .seedInitialDate(widget.initialDate);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _goToday() =>
      ref.read(deliveryDayCalendarProvider.notifier).goToday();

  void _shift(int days) =>
      ref.read(deliveryDayCalendarProvider.notifier).shift(days);

  void _scrollToCurrentTime() {
    final offset = currentTimeGridOffset();
    if (offset != null) {
      final viewport = MediaQuery.of(context).size.height;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = (offset - viewport * 0.3).clamp(0.0, maxScroll);
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calendarState = ref.watch(deliveryDayCalendarProvider);
    final date = calendarState.date;
    final grouped = groupDeliveryOrdersByDayAndSlot(widget.orders);
    final dayKey = _formatDayKey(date);
    final today = DateTime.now();
    final todayKey = _formatDayKey(today);
    final ordersBySlot = <String, List<Order>>{};
    grouped.forEach((key, orders) {
      if (key.day == dayKey) ordersBySlot[key.slot] = orders;
    });

    final timeLineOffset = currentTimeGridOffset();
    final showTimeLine =
        timeLineOffset != null && isTodayDate(date);

    if (showTimeLine && !calendarState.didInitialScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Mark the initial scroll as done inside the post-frame callback so
        // the provider is not modified during the build phase.
        ref.read(deliveryDayCalendarProvider.notifier).markInitialScrollDone();
        if (_scrollController.hasClients) {
          _scrollToCurrentTime();
        }
      });
    }

    return Column(
      children: [
        _DayCalendarNav(
          date: date,
          onPrev: () => _shift(-1),
          onNext: () => _shift(1),
          onToday: _goToday,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Stack(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WeekHourLabelColumn(theme: theme),
                      Expanded(
                        child: WeekDayColumn(
                          date: date,
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
