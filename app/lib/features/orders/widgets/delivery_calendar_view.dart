import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../shared/utils/delivery_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'delivery_order_card.dart';

/// Delivery tab calendar day-view (DG-303 Phase 5 — FR5, AC6).
///
/// Renders delivery orders grouped by 1-hour `deliveryTimeSlot` rows
/// (7:00 … 20:00), with a per-slot count badge. Orders without an assigned
/// slot collapse into a trailing "Chưa có khung giờ" row. Each order renders as a
/// [DeliveryOrderCard]. Designed to scale to ~50 orders/day (NFR3) by leaning
/// on a single [ListView] over a flat items list.
class DeliveryCalendarView extends ConsumerWidget {
  const DeliveryCalendarView({
    super.key,
    required this.orders,
    required this.onRefresh,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final grouped = groupDeliveryOrdersByTimeSlot(orders);

    if (grouped.isEmpty) {
      return Center(
        child: Text(
          OrdersLabels.deliveryCalendarEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    // Flatten into header/order items for a single ListView (NFR3-friendly).
    final items = <Object>[];
    var total = 0;
    grouped.forEach((slot, slotOrders) {
      items.add(_SlotHeader(slot, slotOrders.length));
      items.addAll(slotOrders);
      total += slotOrders.length;
    });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          if (total > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    OrdersLabels.deliveryCalendarSlotTotal(total),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                if (item is _SlotHeader) {
                  return _buildSlotHeader(context, item);
                }
                final order = item as Order;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DeliveryOrderCard(
                    order: order,
                    onTap: () => context.push('/orders/${order.orderRef}'),
                  ),
                );
              },
              childCount: items.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  Widget _buildSlotHeader(BuildContext context, _SlotHeader header) {
    final theme = Theme.of(context);
    final isNoSlot = header.slot == OrdersLabels.deliveryCalendarNoSlot;
    final color = isNoSlot
        ? theme.colorScheme.outline
        : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(
            isNoSlot ? Icons.help_outline : Icons.schedule,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isNoSlot
                  ? header.slot
                  : '${OrdersLabels.deliveryCalendarSlotLabel} ${header.slot}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              OrdersLabels.deliveryCalendarSlotCount(header.count),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotHeader {
  const _SlotHeader(this.slot, this.count);

  final String slot;
  final int count;
}