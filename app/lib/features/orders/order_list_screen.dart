import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';

// Status display order for filter chips
const _filterStatuses = [
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'delivered',
  'completed',
  'cancelled',
];

const _statusColors = {
  'new': Colors.blue,
  'confirmed': Colors.orange,
  'in_progress': Colors.purple,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'completed': Colors.grey,
  'cancelled': Colors.red,
};

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  String? _selectedStatus;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onStatusSelected(String? status) async {
    setState(() => _selectedStatus = status);
    await ref.read(orderListProvider.notifier).filterByStatus(status);
  }

  Future<void> _onRefresh() async {
    await ref.read(orderListProvider.notifier).refresh();
  }

  List<Order> _applySearch(List<Order> orders) {
    if (_searchQuery.isEmpty) return orders;
    final q = _searchQuery.toLowerCase();
    return orders
        .where(
          (o) =>
              o.orderRef.toLowerCase().contains(q) ||
              o.customerName.toLowerCase().contains(q) ||
              o.customerPhone.contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(VN.tabOrders)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/orders/new'),
        tooltip: VN.createOrder,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: VN.searchOrders,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // Status filter chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text(VN.filterAll),
                    selected: _selectedStatus == null,
                    onSelected: (_) => _onStatusSelected(null),
                  ),
                ),
                ..._filterStatuses.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(statusMap[s] ?? s),
                      selected: _selectedStatus == s,
                      selectedColor:
                          (_statusColors[s] ?? Colors.grey).withAlpha(50),
                      onSelected: (_) => _onStatusSelected(
                        _selectedStatus == s ? null : s,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Order list
          Expanded(
            child: ordersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(VN.apiError),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _onRefresh,
                      child: const Text(VN.retry),
                    ),
                  ],
                ),
              ),
              data: (orders) {
                final filtered = _applySearch(orders);
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isNotEmpty || _selectedStatus != null
                          ? 'Không có đơn hàng phù hợp'
                          : 'Chưa có đơn hàng',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _OrderCard(order: filtered[index]),
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: order ref + status chip
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderRef,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withAlpha(120)),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Customer name
            Text(
              order.customerName,
              style: theme.textTheme.bodyMedium,
            ),

            // Due date (if present)
            if (order.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDue(order.dueDate, order.dueTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatVND(order.totalPrice),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                formatVND(order.totalPrice),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDue(String? dueDate, String? dueTime) {
    if (dueDate == null) return '';
    return dueTime != null ? '$dueDate $dueTime' : dueDate;
  }
}
