import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'delivery_day_calendar_view.dart';
import 'delivery_order_card.dart';
import 'delivery_week_calendar_view.dart';

class DeliveryContent extends ConsumerStatefulWidget {
  const DeliveryContent({super.key});

  @override
  ConsumerState<DeliveryContent> createState() => _DeliveryContentState();
}

class _DeliveryContentState extends ConsumerState<DeliveryContent> {
  bool _showToday = true;

  /// View mode for the delivery tab: 'day' (default), 'week', or 'list'.
  /// Defaults to 'day' per FR1/AC1 so the day calendar is shown on open.
  String _viewMode = 'day';

  Future<void> _onRefresh() async {
    await ref.read(orderListProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(VN.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _onRefresh,
              child: const Text(VN.retry),
            ),
          ],
        ),
      ),
      data: (orders) {
        final isCalendar = _viewMode != 'list';
        // The week/day grid has its own "Hôm nay" navigation (FR5/AC2/AC3),
        // so it always receives all non-terminal delivery orders regardless
        // of the Today/All filter. The Today/All filter only applies to the
        // list view.
        final calendarOrders =
            filterDeliveryOrders(orders, todayOnly: false);
        final listOrders =
            filterDeliveryOrders(orders, todayOnly: _showToday);
        // Auto-focus the calendars on the next upcoming non-terminal
        // delivery order (FR2/FR3/AC2/AC3); fall back to today when none
        // (AC4). Computed once per rebuild from the non-terminal set.
        final nextDue = findNextDueDate(calendarOrders) ?? DateTime.now();
        final nextDueWeekStart = startOfWeek(nextDue);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  if (!isCalendar) ...[
                    FilterChip(
                      label: const Text(OrdersLabels.deliveryFilterToday),
                      selected: _showToday,
                      onSelected: (v) => setState(() => _showToday = v),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text(OrdersLabels.deliveryFilterAll),
                      selected: !_showToday,
                      onSelected: (v) => setState(() => _showToday = !v),
                    ),
                  ],
                  const Spacer(),
                  _ViewModeToggle(
                    viewMode: _viewMode,
                    onChanged: (mode) =>
                        setState(() => _viewMode = mode),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildView(calendarOrders, listOrders, nextDue, nextDueWeekStart),
            ),
          ],
        );
      },
    );
  }

  Widget _buildView(
    List<Order> calendarOrders,
    List<Order> listOrders,
    DateTime nextDue,
    DateTime nextDueWeekStart,
  ) {
    switch (_viewMode) {
      case 'week':
        return DeliveryWeekCalendarView(
          orders: calendarOrders,
          onRefresh: _onRefresh,
          initialWeekStart: nextDueWeekStart,
        );
      case 'day':
        return DeliveryDayCalendarView(
          orders: calendarOrders,
          onRefresh: _onRefresh,
          initialDate: nextDue,
        );
      default:
        if (listOrders.isEmpty) {
          return Center(
            child: Text(
              _showToday
                  ? OrdersLabels.deliveryEmptyToday
                  : OrdersLabels.deliveryEmptyAll,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          );
        }
        return _buildGroupedList(listOrders);
    }
  }

  Widget _buildGroupedList(List<Order> orders) {
    final grouped = groupDeliveryOrdersByStatus(orders);
    final items = <Object>[];
    for (final entry in grouped.entries) {
      if (entry.value.isNotEmpty) {
        items.add(entry.key);
        items.addAll(entry.value);
      }
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: items.length,
        itemBuilder: (ctx, index) {
          final item = items[index];
          if (item is String) {
            final statusColor =
                BakeryTheme.statusColors[item] ?? Colors.grey;
            final statusLabel = statusMap[item] ?? item;
            final sectionOrders = grouped[item]!;
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${sectionOrders.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final order = item as Order;
          return DeliveryOrderCard(
            order: order,
            onTap: () => ctx.push('/orders/${order.orderRef}'),
          );
        },
      ),
    );
  }
}

/// Cycle button that toggles between list → week → day → list views.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.viewMode, required this.onChanged});

  final String viewMode;
  final ValueChanged<String> onChanged;

  IconData _icon() {
    switch (viewMode) {
      case 'list':
        return Icons.calendar_month_outlined;
      case 'week':
        return Icons.view_day_outlined;
      case 'day':
        return Icons.view_list;
      default:
        return Icons.calendar_month_outlined;
    }
  }

  String _tooltip() {
    switch (viewMode) {
      case 'list':
        return OrdersLabels.deliverySwitchToWeek;
      case 'week':
        return OrdersLabels.deliverySwitchToDay;
      case 'day':
        return OrdersLabels.deliverySwitchToList;
      default:
        return OrdersLabels.deliverySwitchToWeek;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_icon()),
      tooltip: _tooltip(),
      onPressed: () {
        switch (viewMode) {
          case 'list':
            onChanged('week');
          case 'week':
            onChanged('day');
          case 'day':
            onChanged('list');
        }
      },
    );
  }
}
