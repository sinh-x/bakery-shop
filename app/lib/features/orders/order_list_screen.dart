// EXEMPT: 300-line threshold exceeded because DG-150 blocker: extracting filter/search/tile/empty/loading widgets now would require broad state-lift changes across persisted filter and refresh flows. Reviewed 2026-05-29.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/order.dart';
import '../../data/providers/cake_queue_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/order_helpers.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../providers/order/critical_alert_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'cake_queue_screen.dart';
import 'widgets/incomplete_banner.dart';
import 'widgets/order_card.dart';
import 'widgets/urgency_banner.dart';

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

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, AutoRefreshMixin {
  late final TabController _tabController;
  String _statusFilter = 'new';
  String _searchQuery = '';
  final bool _urgencyFilterEnabled = false;
  final _searchController = TextEditingController();

  // View mode: 'list' or 'kanban'
  String _viewMode = 'list';

  @override
  String screenRoutePath() => '/orders';

  @override
  void invalidateProviders() {
    ref.invalidate(orderListProvider);
    ref.invalidate(cakeQueueProvider);
    ref.invalidate(deliveryQueueProvider);
  }

  @override
  void onAutoRefreshTriggered() {
    super.onAutoRefreshTriggered();
    checkAndShowCriticalAlert(ref: ref, context: context, mounted: mounted);
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

  void _onAppBarMenuSelected(String value) {
    switch (value) {
      case 'orders_history':
        context.push('/orders/history');
        return;
      case 'manage_customers':
        context.push('/customers');
        return;
      case 'settings':
        context.push('/settings');
        return;
      default:
        assert(() {
          debugPrint('Unknown orders app bar menu action: $value');
          return true;
        }());
        return;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadViewMode();
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(orderListProvider.notifier).refresh();
  }

  List<Order> _applyStatusFilter(List<Order> orders) {
    switch (_statusFilter) {
      case 'ready':
        // Pickup-only ready orders (same as Kanban "Sẵn sàng" column)
        return orders
            .where(
              (o) =>
                  o.status == 'ready' &&
                  !isDeliveryType(o.deliveryType),
            )
            .toList();
      case 'to_deliver':
        // Ready orders needing delivery (same as Kanban "Giao hàng" column)
        return orders
            .where(
              (o) =>
                  o.status == 'ready' &&
                  isDeliveryType(o.deliveryType),
            )
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
              o.publicOrderCode.toLowerCase().contains(q) ||
              o.orderRef.toLowerCase().contains(q) ||
              o.customerName.toLowerCase().contains(q) ||
              o.customerPhone.contains(q),
        )
        .toList();
  }

  List<Order> _applyUrgencyFilter(List<Order> orders) {
    if (!_urgencyFilterEnabled) return orders;
    return orders
        .where((o) => o.urgency == urgencyCritical || o.urgency == urgencyUrgent)
        .toList();
  }

  List<Order> _applyFilters(List<Order> orders) {
    var filtered = _applySearchFilter(_applyStatusFilter(orders));
    filtered = _applyUrgencyFilter(filtered);
    return filtered;
  }

  /// Groups orders by due date, returning a mixed list of String headers and Order items.
  /// Orders without a due date are placed first under "Chưa có ngày".
  List<Object> _groupByDueDate(List<Order> orders) {
    final noDue = <Order>[];
    final byDate = <String, List<Order>>{};

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
      final parsed = parseApiDate(dateStr);
      result.add(parsed == null ? dateStr : formatDisplayDate(parsed));
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
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: () => ref.read(orderListProvider.notifier).refresh(),
          ),
          IconButton(
            icon: Icon(
              _viewMode == 'list' ? Icons.view_kanban : Icons.view_list,
            ),
            tooltip: _viewMode == 'list'
                ? VN.switchToKanbanView
                : VN.switchToListView,
            onPressed: _toggleViewMode,
          ),
          AppBarOverflowMenu(
            onSelected: _onAppBarMenuSelected,
            items: const [
              PopupMenuItem<String>(
                value: 'orders_history',
                child: Text(VN.openOrderHistory),
              ),
              PopupMenuItem<String>(
                value: 'manage_customers',
                child: Text(VN.openCustomerManagement),
              ),
            ],
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
              // Urgency attention banner
              Consumer(
                builder: (context, ref, _) {
                  final orders = ref.watch(orderListProvider).asData?.value ?? [];
                  final critical = orders
                      .where((o) => o.urgency == urgencyCritical)
                      .length;
                  final urgent = orders
                      .where((o) => o.urgency == urgencyUrgent)
                      .length;
                  return UrgencyBanner(
                    criticalCount: critical,
                    urgentCount: urgent,
                    onTap: () => context.push('/orders/critical'),
                  );
                },
              ),

              // Incomplete-order banner (DG-241 Phase 3 — FR-5)
              Consumer(
                builder: (context, ref, _) {
                  final orders = ref.watch(orderListProvider).asData?.value ?? [];
                  final count = orders
                      .where((o) => o.completeness == completenessIncomplete)
                      .length;
                  return IncompleteBanner(
                    count: count,
                    onTap: () => context.push('/orders/incomplete'),
                  );
                },
              ),

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
                      horizontal: 12,
                      vertical: 4,
                    ),
                    children: _statusFilters.map((s) {
                      final color = BakeryTheme.statusColors[s] ?? Colors.grey;
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
                          onSelected: (_) => setState(() => _statusFilter = s),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // Order list / Kanban view
              Expanded(
                child: _viewMode == 'kanban'
                    ? _KanbanBoard(
                        filteredOrders: ordersAsync.maybeWhen(
                          data: _applySearchFilter,
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
                          final filtered = _applyFilters(orders);
                          if (filtered.isEmpty) {
                            return Center(
                              child: Text(
                                _urgencyFilterEnabled
                                    ? OrdersLabels.urgencyFilterEmpty
                                    : _searchQuery.isNotEmpty
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
                                return OrderCard(
                                  order: order,
                                  onTap: () =>
                                      context.push('/orders/${order.orderRef}'),
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

/// Active Kanban columns in order workflow
/// 'to_deliver' is a virtual status for ready orders with bus/door delivery
/// 'awaiting_payment' is a virtual status for delivered+unpaid orders
const _kanbanStatuses = [
  'new',
  'confirmed',
  'in_progress',
  'ready',
  'to_deliver',
  'awaiting_payment',
];

/// Groups active orders into Kanban columns.
///
/// Handles virtual columns:
/// - 'ready' = status=ready AND is pickup (not bus/door)
/// - 'to_deliver' = status=ready AND deliveryType is bus or door
/// - 'awaiting_payment' = status=delivered AND not paid
///
/// Terminal statuses (completed, cancelled) are not included in any column.
Map<String, List<Order>> groupOrdersByKanbanStatus(List<Order> orders) {
  final result = <String, List<Order>>{};
  for (final status in _kanbanStatuses) {
    if (status == 'to_deliver') {
      // Ready orders that need delivery (bus/door-to-door)
      result[status] = orders
          .where(
            (o) =>
                o.status == 'ready' &&
                isDeliveryType(o.deliveryType),
          )
          .toList();
    } else if (status == 'ready') {
      // Ready orders excluding delivery ones (pickup only)
      result[status] = orders
          .where(
            (o) =>
                o.status == 'ready' &&
                !isDeliveryType(o.deliveryType),
          )
          .toList();
    } else if (status == 'awaiting_payment') {
      result[status] = orders
          .where((o) => o.status == 'delivered' && !o.isPaid)
          .toList();
    } else {
      result[status] = orders.where((o) => o.status == status).toList();
    }
  }
  return result;
}

class _KanbanBoard extends ConsumerWidget {
  const _KanbanBoard({required this.filteredOrders});

  final List<Order> filteredOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersByStatus = groupOrdersByKanbanStatus(filteredOrders);

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: _kanbanStatuses.length,
      itemBuilder: (context, index) {
        final status = _kanbanStatuses[index];
        final orders = ordersByStatus[status] ?? [];
        return _KanbanColumn(status: status, orders: orders);
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
    final statusColor = BakeryTheme.statusColors[status] ?? Colors.grey;
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
                final sourceIndex = _kanbanStatuses.indexOf(
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
                                  child: _DragFeedbackCard(order: order),
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

/// Simplified card shown as floating feedback during drag.
class _DragFeedbackCard extends StatelessWidget {
  const _DragFeedbackCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;

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
