import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'delivery_order_card.dart';
import 'delivery_week_calendar_view.dart';

class DeliveryContent extends ConsumerStatefulWidget {
  const DeliveryContent({super.key});

  @override
  ConsumerState<DeliveryContent> createState() => _DeliveryContentState();
}

class _DeliveryContentState extends ConsumerState<DeliveryContent> {
  bool _showToday = true;

  /// View mode for the delivery tab: 'list' (default) or 'calendar' (FR5).
  String _viewMode = 'list';

  Future<void> _onRefresh() async {
    await ref.read(orderListProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);
    final theme = Theme.of(context);

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
        final isCalendar = _viewMode == 'calendar';
        // The week grid spans a full week with its own "Hôm nay" navigation
        // (FR5/AC2/AC3), so it always receives all non-terminal delivery
        // orders regardless of the Today/All filter. The Today/All filter
        // only applies to the list view.
        final calendarOrders =
            filterDeliveryOrders(orders, todayOnly: false);
        final listOrders =
            filterDeliveryOrders(orders, todayOnly: _showToday);

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
                    onChanged: (mode) => setState(() => _viewMode = mode),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isCalendar
                  ? DeliveryWeekCalendarView(
                      orders: calendarOrders,
                      onRefresh: _onRefresh,
                    )
                  : listOrders.isEmpty
                      ? Center(
                          child: Text(
                            _showToday
                                ? OrdersLabels.deliveryEmptyToday
                                : OrdersLabels.deliveryEmptyAll,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : _buildGroupedList(listOrders),
            ),
          ],
        );
      },
    );
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

/// Segmented list/calendar toggle for the delivery tab (FR5).
/// Mirrors the order list/kanban toggle pattern from [OrderListScreen].
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.viewMode, required this.onChanged});

  final String viewMode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCalendar = viewMode == 'calendar';
    return IconButton(
      icon: Icon(isCalendar ? Icons.view_list : Icons.calendar_month_outlined),
      tooltip: isCalendar
          ? OrdersLabels.deliverySwitchToList
          : OrdersLabels.deliverySwitchToCalendar,
      onPressed: () => onChanged(isCalendar ? 'list' : 'calendar'),
    );
  }
}
