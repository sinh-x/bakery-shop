import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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

// Group filter definitions for order list
const _groupFilters = [
  (id: 'working', label: 'Cần làm'),
  (id: 'ready', label: 'Sẵn sàng'),
  (id: 'done', label: 'Xong'),
  (id: 'all', label: 'Tất cả'),
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
  String _groupFilter = 'working';
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

  List<Order> _applyGroupFilter(List<Order> orders) {
    switch (_groupFilter) {
      case 'working':
        return orders
            .where((o) =>
                o.status == 'new' ||
                o.status == 'confirmed' ||
                o.status == 'in_progress' ||
                o.status == 'ready')
            .toList();
      case 'ready':
        return orders
            .where(
                (o) => o.status == 'ready' || o.status == 'delivered')
            .toList();
      case 'done':
        return orders
            .where((o) =>
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

              // Order list / Kanban view
              Expanded(
                child: _viewMode == 'kanban'
                    ? _KanbanPlaceholder(filteredCount: ordersAsync.maybeWhen(
                          data: (orders) => _applyFilters(orders).length,
                          orElse: () => 0,
                        ))
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
                                _searchQuery.isNotEmpty ||
                                        _groupFilter != 'working'
                                    ? 'Không có đơn hàng phù hợp'
                                    : 'Không có đơn cần làm',
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
                  // Delivery type icon
                  Icon(
                    _deliveryIcon(),
                    size: 18,
                    color: theme.colorScheme.primary,
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
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDue(order.dueDate, order.dueTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: urgencyColor ?? theme.colorScheme.outline,
                        fontWeight:
                            urgencyColor != null ? FontWeight.w600 : null,
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

class _KanbanPlaceholder extends StatelessWidget {
  const _KanbanPlaceholder({required this.filteredCount});

  final int filteredCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.view_kanban,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'Khanban (đang xây dựng)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '$filteredCount đơn hàng',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
