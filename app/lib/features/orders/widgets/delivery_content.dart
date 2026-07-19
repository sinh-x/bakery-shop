import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'delivery_order_card.dart';

class DeliveryContent extends ConsumerStatefulWidget {
  const DeliveryContent({super.key});

  @override
  ConsumerState<DeliveryContent> createState() => _DeliveryContentState();
}

class _DeliveryContentState extends ConsumerState<DeliveryContent> {
  bool _showToday = true;

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
        final deliveryOrders = filterDeliveryOrders(orders, todayOnly: _showToday);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
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
              ),
            ),
            Expanded(
              child: deliveryOrders.isEmpty
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
                  : _buildGroupedList(deliveryOrders),
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
