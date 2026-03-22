import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/order.dart';
import '../../data/providers/cake_queue_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'cake_queue_screen.dart';

// Group filter definitions for order list
const _groupFilters = [
  (id: 'all', label: 'Tất cả'),
  (id: 'working', label: 'Đang làm'),
  (id: 'ready', label: 'Sẵn sàng'),
  (id: 'done', label: 'Xong'),
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

class _OrderListScreenState extends ConsumerState<OrderListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _groupFilter = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Auto-refresh: detect when user navigates back to this screen
  GoRouter? _goRouter;
  bool _wasNavigatedAway = false;

  void _addRouterListener() {
    _goRouter?.routerDelegate.addListener(_handleRouteChange);
  }

  void _removeRouterListener() {
    _goRouter?.routerDelegate.removeListener(_handleRouteChange);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (_goRouter != router) {
      _removeRouterListener();
      _goRouter = router;
      _addRouterListener();
    }
  }

  @override
  void dispose() {
    _removeRouterListener();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleRouteChange() {
    if (!mounted) return;
    final path = _goRouter!.state.uri.path;
    if (path == '/orders' && _wasNavigatedAway) {
      _wasNavigatedAway = false;
      ref.invalidate(orderListProvider);
      ref.invalidate(cakeQueueProvider);
      ref.invalidate(deliveryQueueProvider);
    } else if (path != '/orders') {
      _wasNavigatedAway = true;
    }
  }

  Future<void> _onRefresh() async {
    await ref.read(orderListProvider.notifier).refresh();
  }

  List<Order> _applyGroupFilter(List<Order> orders) {
    switch (_groupFilter) {
      case 'working':
        return orders
            .where((o) =>
                o.status == 'new' ||
                o.status == 'confirmed' ||
                o.status == 'in_progress')
            .toList();
      case 'ready':
        return orders.where((o) => o.status == 'ready').toList();
      case 'done':
        return orders
            .where((o) =>
                o.status == 'delivered' ||
                o.status == 'completed' ||
                o.status == 'cancelled')
            .toList();
      default:
        return orders;
    }
  }

  List<Order> _applyFilters(List<Order> orders) {
    final grouped = _applyGroupFilter(orders);
    if (_searchQuery.isEmpty) return grouped;
    final q = _searchQuery.toLowerCase();
    return grouped
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
    final isOrdersTab = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.tabOrders),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: VN.orderListTab),
            Tab(text: VN.cakeQueue),
            Tab(text: VN.deliveryTab),
          ],
        ),
      ),
      floatingActionButton: isOrdersTab
          ? FloatingActionButton(
              onPressed: () => context.push('/orders/new'),
              tooltip: VN.createOrder,
              child: const Icon(Icons.add),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 0: Order list ──────────────────────────────────────
          Column(
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

              // Group status filter chips
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  children: _groupFilters
                      .map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(g.label),
                            selected: _groupFilter == g.id,
                            onSelected: (_) =>
                                setState(() => _groupFilter = g.id),
                          ),
                        ),
                      )
                      .toList(),
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
                    final filtered = _applyFilters(orders);
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isNotEmpty || _groupFilter != 'all'
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
                        itemBuilder: (context, index) => _OrderCard(
                          order: filtered[index],
                          onTap: () => context
                              .push('/orders/${filtered[index].orderRef}'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // ── Tab 1: Cake queue ──────────────────────────────────────
          const CakeQueueContent(),

          // ── Tab 2: Delivery ────────────────────────────────────────
          const DeliveryContent(),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, this.onTap});

  final Order order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
    final photoCount = photosAsync.maybeWhen(
      data: (photos) => photos.length,
      orElse: () => 0,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: order ref + photo badge + status chip
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
                if (photoCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_outlined,
                          size: 11,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$photoCount ảnh',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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

            // Customer name + source badge
            Row(
              children: [
                Text(
                  order.customerName,
                  style: theme.textTheme.bodyMedium,
                ),
                if (order.source.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.source,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
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
      ),
    );
  }

  String _formatDue(String? dueDate, String? dueTime) {
    if (dueDate == null) return '';
    return dueTime != null ? '$dueDate $dueTime' : dueDate;
  }
}
