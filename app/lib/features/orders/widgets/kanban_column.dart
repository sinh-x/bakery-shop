import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/order.dart';
import '../../../data/providers/order/order_detail_notifier.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils.dart' show statusMap;
import 'kanban_helpers.dart';
import 'drag_feedback_card.dart';
import 'order_card.dart';

class KanbanColumn extends ConsumerWidget {
  const KanbanColumn({
    super.key,
    required this.status,
    required this.orders,
  });

  final String status;
  final List<Order> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = BakeryTheme.statusColors[status] ?? Colors.grey;
    final statusLabel = status == 'awaiting_payment'
        ? 'Xác nhận thanh toán'
        : status == 'to_deliver'
        ? 'Giao hàng'
        : (statusMap[status] ?? status);
    final targetIndex = kanbanStatuses.indexOf(status);

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(30),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border.all(color: statusColor.withAlpha(100)),
            ),
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(50),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Order cards list with DragTarget
          Expanded(
            child: DragTarget<Order>(
              onWillAcceptWithDetails: (details) {
                // Don't accept drops on virtual columns
                if (status == 'awaiting_payment' || status == 'to_deliver') {
                  return false;
                }
                // Only accept forward transitions
                final sourceIndex = kanbanStatuses.indexOf(
                  details.data.status,
                );
                return targetIndex > sourceIndex;
              },
              onAcceptWithDetails: (details) async {
                final order = details.data;
                final targetStatusLabel = statusMap[status] ?? status;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Chuyển trạng thái'),
                    content: Text(
                      'Chuyển đơn hàng "${order.customerName}" sang trạng thái "$targetStatusLabel"?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Hủy'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Xác nhận'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await ref
                      .read(orderDetailProvider(order.orderRef).notifier)
                      .transitionTo(status);
                }
              },
              builder: (context, candidateData, rejectedData) {
                // Highlight column when a valid drag is hovering over it
                final isHovering = candidateData.isNotEmpty;
                return Container(
                  decoration: BoxDecoration(
                    color: isHovering
                        ? statusColor.withAlpha(15)
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                    border: Border.all(
                      color: isHovering
                          ? statusColor.withAlpha(150)
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: isHovering ? 2 : 1,
                    ),
                  ),
                  child: orders.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Không có đơn',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: orders.length,
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            return LongPressDraggable<Order>(
                              data: order,
                              onDragStarted: HapticFeedback.mediumImpact,
                              feedback: Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 260,
                                  child: DragFeedbackCard(order: order),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.4,
                                child: OrderCard(order: order),
                              ),
                              child: OrderCard(
                                order: order,
                                onTap: () =>
                                    context.push('/orders/${order.orderRef}'),
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}