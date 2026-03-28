import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api/api_client.dart';
import '../../data/models/order.dart';
import '../../data/providers/cake_queue_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'cake_queue_screen.dart';

// Status filter chips for list view (mirrors Kanban column statuses + extras)
// List view filters mirror Kanban columns (one column at a time)
const _statusFilters = [
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'to_deliver',
  'awaiting_payment',
];

const _statusFilterLabels = {
  'to_deliver': 'Giao hàng',
  'awaiting_payment': 'Xác nhận thanh toán',
};

const _statusColors = {
  'new': Colors.blue,
  'confirmed': Colors.orange,
  'in_progress': Colors.purple,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'completed': Colors.grey,
  'cancelled': Colors.red,
  'to_deliver': Colors.deepOrange,
  'awaiting_payment': Colors.pink,
};

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _statusFilter = 'new';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // View mode: 'list' or 'kanban'
  String _viewMode = 'list';

  // Auto-refresh: detect when user navigates back to this screen
  GoRouter? _goRouter;
  bool _wasNavigatedAway = false;

  void _addRouterListener() {
    _goRouter?.routerDelegate.addListener(_handleRouteChange);
  }

  void _removeRouterListener() {
    _goRouter?.routerDelegate.removeListener(_handleRouteChange);
  }

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _viewMode = prefs.getString('order_view_mode') ?? 'list';
    });
  }

  Future<void> _toggleViewMode() async {
    final newMode = _viewMode == 'list' ? 'kanban' : 'list';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('order_view_mode', newMode);
    setState(() {
      _viewMode = newMode;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadViewMode();
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

  List<Order> _applyStatusFilter(List<Order> orders) {
    switch (_statusFilter) {
      case 'ready':
        // Pickup-only ready orders (same as Kanban "Sẵn sàng" column)
        return orders
            .where((o) =>
                o.status == 'ready' &&
                o.deliveryType != 'bus' &&
                o.deliveryType != 'door')
            .toList();
      case 'to_deliver':
        // Ready orders needing delivery (same as Kanban "Giao hàng" column)
        return orders
            .where((o) =>
                o.status == 'ready' &&
                (o.deliveryType == 'bus' || o.deliveryType == 'door'))
            .toList();
      case 'awaiting_payment':
        // Delivered but unpaid (same as Kanban "Xác nhận thanh toán" column)
        return orders
            .where((o) => o.status == 'delivered' && !o.isPaid)
            .toList();
      default:
        return orders.where((o) => o.status == _statusFilter).toList();
    }
  }

  List<Order> _applySearchFilter(List<Order> orders) {
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

  List<Order> _applyFilters(List<Order> orders) {
    final grouped = _applyStatusFilter(orders);
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

  /// Groups orders by due date, returning a mixed list of String headers and Order items.
  /// Orders without a due date are placed first under "Chưa có ngày".
  List<Object> _groupByDueDate(List<Order> orders) {
    final noDue = <Order>[];
    final byDate = <String, List<Order>>{};
    final dateFormat = DateFormat('dd/MM/yyyy');

    for (final o in orders) {
      if (o.dueDate == null || o.dueDate!.isEmpty) {
        noDue.add(o);
      } else {
        byDate.putIfAbsent(o.dueDate!, () => []).add(o);
      }
    }

    // Sort date keys chronologically
    final sortedDates = byDate.keys.toList()..sort();

    final result = <Object>[];

    // "Chưa có ngày" group at top
    if (noDue.isNotEmpty) {
      result.add('Chưa có ngày');
      result.addAll(noDue);
    }

    for (final dateStr in sortedDates) {
      // Format YYYY-MM-DD to dd/MM/yyyy for display
      try {
        final parsed = DateTime.parse(dateStr);
        result.add(dateFormat.format(parsed));
      } catch (_) {
        result.add(dateStr);
      }
      result.addAll(byDate[dateStr]!);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(orderListProvider);
    final isOrdersTab = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.tabOrders),
        actions: [
          IconButton(
            icon: Icon(
              _viewMode == 'list' ? Icons.view_kanban : Icons.view_list,
            ),
            tooltip: _viewMode == 'list' ? 'Kanban' : 'Danh sách',
            onPressed: _toggleViewMode,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: VN.settings,
            onPressed: () => context.push('/settings'),
          ),
        ],
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

              // Status filter chips (hidden in Kanban — columns already group by status)
              if (_viewMode == 'list')
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    children: _statusFilters
                        .map(
                          (s) {
                            final color = _statusColors[s] ?? Colors.grey;
                            final label = _statusFilterLabels[s] ?? statusMap[s] ?? s;
                            final selected = _statusFilter == s;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                label: Text(label),
                                selected: selected,
                                selectedColor: color.withAlpha(30),
                                onSelected: (_) =>
                                    setState(() => _statusFilter = s),
                              ),
                            );
                          },
                        )
                        .toList(),
                  ),
                ),

              // Order list / Kanban view
              Expanded(
                child: _viewMode == 'kanban'
                    ? _KanbanBoard(
                        filteredOrders: ordersAsync.maybeWhen(
                          data: (orders) => _applySearchFilter(orders),
                          orElse: () => <Order>[],
                        ),
                      )
                    : ordersAsync.when(
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
                                _searchQuery.isNotEmpty
                                    ? 'Không có đơn hàng phù hợp'
                                    : 'Không có đơn hàng',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            );
                          }
                          final grouped = _groupByDueDate(filtered);
                          return RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: grouped.length,
                              itemBuilder: (context, index) {
                                final item = grouped[index];
                                if (item is String) {
                                  return _DateHeader(label: item);
                                }
                                final order = item as Order;
                                return _OrderCard(
                                  order: order,
                                  onTap: () => context
                                      .push('/orders/${order.orderRef}'),
                                );
                              },
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

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, this.onTap});

  final Order order;
  final VoidCallback? onTap;

  /// Returns the urgency border color: red for overdue, amber for same-day, null otherwise.
  Color? _urgencyBorderColor() {
    if (order.dueDate == null || order.dueDate!.isEmpty) return null;
    try {
      final due = DateTime.parse(order.dueDate!);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDateOnly = DateTime(due.year, due.month, due.day);
      if (dueDateOnly.isBefore(today)) {
        return Colors.red;
      } else if (dueDateOnly.isAtSameMomentAs(today)) {
        return Colors.amber;
      }
    } catch (_) {}
    return null;
  }

  IconData _deliveryIcon() {
    switch (order.deliveryType) {
      case 'bus':
        return Icons.directions_bus;
      case 'door':
        return Icons.local_shipping;
      case 'pickup':
      default:
        return Icons.storefront;
    }
  }

  Color _deliveryIconColor(Color defaultColor) {
    switch (order.deliveryType) {
      case 'bus':
        return Colors.orange;
      case 'door':
        return Colors.deepOrange;
      default:
        return defaultColor;
    }
  }

  bool get _isDelivery =>
      order.deliveryType == 'bus' || order.deliveryType == 'door';

  /// Returns true if the order is due within the next 2 hours.
  bool _isDueWithin2Hours() {
    if (order.dueDate == null || order.dueDate!.isEmpty) return false;
    try {
      final now = DateTime.now();
      DateTime due;
      if (order.dueTime != null && order.dueTime!.isNotEmpty) {
        due = DateTime.parse('${order.dueDate!} ${order.dueTime!}');
      } else {
        due = DateTime.parse(order.dueDate!);
      }
      return due.isAfter(now) &&
          due.difference(now).inMinutes <= 120;
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoCount = photosAsync.maybeWhen(
      data: (photos) => photos.length,
      orElse: () => 0,
    );
    // Find the first cake photo (workItemId != null) for thumbnail
    final cakePhoto = photosAsync.maybeWhen(
      data: (photos) {
        try {
          return photos.firstWhere((p) => p.workItemId != null);
        } catch (_) {
          return null;
        }
      },
      orElse: () => null,
    );
    final cakePhotoUrl = cakePhoto != null
        ? '$baseUrl/api/photos/${cakePhoto.photoHash}.jpg'
        : null;
    final urgencyColor = _urgencyBorderColor();
    final dueSoon = _isDueWithin2Hours();

    // Build left border decoration
    final borderSides = <BorderSide>[];
    if (urgencyColor != null) {
      borderSides.add(BorderSide(color: urgencyColor, width: 4));
    }
    // Default grey border on left for structure (1px)
    if (borderSides.isEmpty) {
      borderSides.add(const BorderSide(color: Colors.transparent, width: 4));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: borderSides.first,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: order ref + delivery icon + photo badge + status chip
              Row(
                children: [
                  // Delivery type icon (colored for bus/door-to-door)
                  Icon(
                    _deliveryIcon(),
                    size: _isDelivery ? 20 : 18,
                    color: _deliveryIconColor(theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 6),
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
                  // Cake photo thumbnail (first photo with workItemId set)
                  if (cakePhotoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: cakePhotoUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  if (cakePhotoUrl != null) const SizedBox(width: 6),
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

              // Notes preview (1 line, ellipsis) — only if non-empty
              if (order.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  order.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              // Due date (if present)
              if (order.dueDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: dueSoon ? Colors.red : (urgencyColor ?? theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.withAlpha(80)),
                        ),
                        child: Text(
                          _formatDue(order.dueDate, order.dueTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Text(
                        _formatDue(order.dueDate, order.dueTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: urgencyColor ?? theme.colorScheme.outline,
                          fontWeight:
                              urgencyColor != null ? FontWeight.bold : null,
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

/// Active Kanban columns in order workflow
/// 'to_deliver' is a virtual status for ready orders with bus/door delivery
/// 'awaiting_payment' is a virtual status for delivered+unpaid orders
const _kanbanStatuses = ['new', 'confirmed', 'in_progress', 'ready', 'to_deliver', 'awaiting_payment'];

class _KanbanBoard extends ConsumerWidget {
  const _KanbanBoard({required this.filteredOrders});

  final List<Order> filteredOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group orders by status for active columns
    // 'awaiting_payment' is a virtual column: delivered orders that are not paid
    final ordersByStatus = <String, List<Order>>{};
    for (final status in _kanbanStatuses) {
      if (status == 'to_deliver') {
        // Ready orders that need delivery (bus/door-to-door)
        ordersByStatus[status] = filteredOrders
            .where((o) =>
                o.status == 'ready' &&
                (o.deliveryType == 'bus' || o.deliveryType == 'door'))
            .toList();
      } else if (status == 'ready') {
        // Ready orders excluding delivery ones (pickup only)
        ordersByStatus[status] = filteredOrders
            .where((o) =>
                o.status == 'ready' &&
                o.deliveryType != 'bus' &&
                o.deliveryType != 'door')
            .toList();
      } else if (status == 'awaiting_payment') {
        ordersByStatus[status] = filteredOrders
            .where((o) => o.status == 'delivered' && !o.isPaid)
            .toList();
      } else {
        ordersByStatus[status] =
            filteredOrders.where((o) => o.status == status).toList();
      }
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: _kanbanStatuses.length,
      itemBuilder: (context, index) {
        final status = _kanbanStatuses[index];
        final orders = ordersByStatus[status] ?? [];
        return _KanbanColumn(
          status: status,
          orders: orders,
        );
      },
    );
  }
}

class _KanbanColumn extends ConsumerWidget {
  const _KanbanColumn({required this.status, required this.orders});

  final String status;
  final List<Order> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _statusColors[status] ?? Colors.grey;
    final statusLabel = status == 'awaiting_payment'
        ? 'Xác nhận thanh toán'
        : status == 'to_deliver'
            ? 'Giao hàng'
            : (statusMap[status] ?? status);
    final targetIndex = _kanbanStatuses.indexOf(status);

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                if (status == 'awaiting_payment' || status == 'to_deliver') return false;
                // Only accept forward transitions
                final sourceIndex = _kanbanStatuses.indexOf(details.data.status);
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
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
                              onDragStarted: () =>
                                  HapticFeedback.mediumImpact(),
                              feedback: Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 260,
                                  child: _DragFeedbackCard(order: order),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.4,
                                child: _KanbanCard(order: order, onTap: null),
                              ),
                              child: _KanbanCard(
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

class _KanbanCard extends ConsumerWidget {
  const _KanbanCard({required this.order, this.onTap});

  final Order order;
  final VoidCallback? onTap;

  Color? _urgencyBorderColor() {
    if (order.dueDate == null || order.dueDate!.isEmpty) return null;
    try {
      final due = DateTime.parse(order.dueDate!);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDateOnly = DateTime(due.year, due.month, due.day);
      if (dueDateOnly.isBefore(today)) {
        return Colors.red;
      } else if (dueDateOnly.isAtSameMomentAs(today)) {
        return Colors.amber;
      }
    } catch (_) {}
    return null;
  }

  IconData _deliveryIcon() {
    switch (order.deliveryType) {
      case 'bus':
        return Icons.directions_bus;
      case 'door':
        return Icons.local_shipping;
      case 'pickup':
      default:
        return Icons.storefront;
    }
  }

  Color _deliveryIconColor(Color defaultColor) {
    switch (order.deliveryType) {
      case 'bus':
        return Colors.orange;
      case 'door':
        return Colors.deepOrange;
      default:
        return defaultColor;
    }
  }

  String _productSummary() {
    if (order.items.isEmpty) return '';
    final first = order.items.first;
    final name = first.productName;
    if (order.items.length == 1) return name;
    return '$name +${order.items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final urgencyColor = _urgencyBorderColor();

    // Find first cake photo
    final cakePhoto = photosAsync.maybeWhen(
      data: (photos) {
        try {
          return photos.firstWhere((p) => p.workItemId != null);
        } catch (_) {
          return null;
        }
      },
      orElse: () => null,
    );
    final cakePhotoUrl = cakePhoto != null
        ? '$baseUrl/api/photos/${cakePhoto.photoHash}.jpg'
        : null;

    // Build left border
    final borderColor = urgencyColor ?? Colors.transparent;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: customer name + delivery icon + photo thumbnail
              Row(
                children: [
                  Icon(
                    _deliveryIcon(),
                    size: 16,
                    color: _deliveryIconColor(theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (cakePhotoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: cakePhotoUrl,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 36,
                          height: 36,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child:
                                SizedBox(width: 12, height: 12, child:
                                CircularProgressIndicator(strokeWidth: 1.5)),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 36,
                          height: 36,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 6),

              // Product summary
              if (order.items.isNotEmpty)
                Text(
                  _productSummary(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 4),

              // Due date/time + price
              if (order.dueDate != null)
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: urgencyColor ?? theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.dueTime != null
                            ? '${order.dueDate} ${order.dueTime}'
                            : order.dueDate!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              urgencyColor ?? theme.colorScheme.outline,
                          fontWeight:
                              urgencyColor != null ? FontWeight.w600 : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatVND(order.totalPrice),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  formatVND(order.totalPrice),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simplified card shown as floating feedback during drag.
class _DragFeedbackCard extends StatelessWidget {
  const _DragFeedbackCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[order.status] ?? Colors.grey;

    return Card(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                  child: Text(
                    order.customerName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (order.items.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _productSummary(order),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (order.dueDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 12,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.dueTime != null
                          ? '${order.dueDate} ${order.dueTime}'
                          : order.dueDate!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _productSummary(Order order) {
    if (order.items.isEmpty) return '';
    final first = order.items.first;
    final name = first.productName;
    if (order.items.length == 1) return name;
    return '$name +${order.items.length - 1}';
  }
}
