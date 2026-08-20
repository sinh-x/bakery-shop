import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import 'kanban_column.dart';
import 'kanban_helpers.dart';

class KanbanBoard extends ConsumerWidget {
  const KanbanBoard({super.key, required this.filteredOrders});

  final List<Order> filteredOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersByStatus = groupOrdersByKanbanStatus(filteredOrders);

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: kanbanStatuses.length,
      itemBuilder: (context, index) {
        final status = kanbanStatuses[index];
        final orders = ordersByStatus[status] ?? [];
        return KanbanColumn(status: status, orders: orders);
      },
    );
  }
}