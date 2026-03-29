import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api/api_client.dart';
import '../../data/models/cake_queue_item.dart';
import '../../data/models/order.dart';
import '../../data/providers/cake_queue_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/vietnamese_labels.dart';

/// Delivery content widget — embedded inside the Orders tab as the third sub-view.
/// Shows orders matching the Kanban "Giao hàng" logic: ready + bus/door delivery.
class DeliveryContent extends ConsumerStatefulWidget {
  const DeliveryContent({super.key});

  @override
  ConsumerState<DeliveryContent> createState() => _DeliveryContentState();
}

class _DeliveryContentState extends ConsumerState<DeliveryContent> {
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
        // Filter: ready orders with bus/door delivery (same as Kanban "Giao hàng")
        final deliveryOrders = orders
            .where((o) =>
                o.status == 'ready' &&
                (o.deliveryType == 'bus' || o.deliveryType == 'door'))
            .toList();

        if (deliveryOrders.isEmpty) {
          return Center(
            child: Text(
              VN.noDeliveryItems,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: deliveryOrders.length,
            itemBuilder: (ctx, index) {
              final order = deliveryOrders[index];
              return _DeliveryOrderCard(
                order: order,
                onTap: () => ctx.push('/orders/${order.orderRef}'),
              );
            },
          ),
        );
      },
    );
  }
}

/// Order card for the delivery tab — matches the order list card style.
class _DeliveryOrderCard extends ConsumerWidget {
  const _DeliveryOrderCard({required this.order, this.onTap});

  final Order order;
  final VoidCallback? onTap;

  Color? _urgencyBorderColor() {
    if (order.dueDate == null || order.dueDate!.isEmpty) return null;
    try {
      final due = DateTime.parse(order.dueDate!);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDateOnly = DateTime(due.year, due.month, due.day);
      if (dueDateOnly.isBefore(today)) return Colors.red;
      if (dueDateOnly.isAtSameMomentAs(today)) return Colors.amber;
    } catch (_) {}
    return null;
  }

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
      return due.isAfter(now) && due.difference(now).inMinutes <= 120;
    } catch (_) {}
    return false;
  }

  IconData _deliveryIcon() {
    switch (order.deliveryType) {
      case 'bus':
        return Icons.directions_bus;
      case 'door':
        return Icons.local_shipping;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = _orderStatusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final urgencyColor = _urgencyBorderColor();
    final dueSoon = _isDueWithin2Hours();
    final borderColor = urgencyColor ?? Colors.transparent;

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: delivery icon + order ref + photo + status
              Row(
                children: [
                  Icon(
                    _deliveryIcon(),
                    size: 20,
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
                  if (cakePhotoUrl != null) ...[
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
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image_outlined,
                              size: 20, color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: statusColor.withAlpha(120)),
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
              Text(order.customerName, style: theme.textTheme.bodyMedium),

              // Notes preview
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

              // Due date/time + price
              if (order.dueDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: dueSoon
                          ? Colors.red
                          : (urgencyColor ?? theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Colors.red.withAlpha(80)),
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
                          color:
                              urgencyColor ?? theme.colorScheme.outline,
                          fontWeight: urgencyColor != null
                              ? FontWeight.bold
                              : null,
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

const _orderStatusColors = {
  'new': Colors.blue,
  'confirmed': Colors.orange,
  'in_progress': Colors.purple,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'completed': Colors.grey,
  'cancelled': Colors.red,
};

const _statusColors = {
  'pending': Colors.grey,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
};

/// Cake queue content widget — embedded inside the Orders tab as a sub-view.
/// Shows work items across all orders, sorted by due date ascending.
class CakeQueueContent extends ConsumerStatefulWidget {
  const CakeQueueContent({super.key});

  @override
  ConsumerState<CakeQueueContent> createState() => _CakeQueueContentState();
}

class _CakeQueueContentState extends ConsumerState<CakeQueueContent> {
  bool _includeReady = false;

  Future<void> _onRefresh() async {
    await ref.read(cakeQueueProvider(_includeReady).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(cakeQueueProvider(_includeReady));
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: FilterChip(
            label: Text(VN.includeReadyFilter),
            selected: _includeReady,
            onSelected: (v) => setState(() => _includeReady = v),
          ),
        ),

        // List
        Expanded(
          child: queueAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
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
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    VN.noCakeQueueItems,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: items.length,
                  itemBuilder: (ctx, index) => _CakeQueueCard(
                    item: items[index],
                    onTap: () => ctx.push(
                      '/orders/${items[index].orderRef}/items/${items[index].id}',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CakeQueueCard extends ConsumerWidget {
  const _CakeQueueCard({required this.item, this.onTap});

  final CakeQueueItem item;
  final VoidCallback? onTap;

  /// Returns urgency border color: red for overdue, amber for same-day.
  Color? _urgencyBorderColor() {
    if (item.dueDate == null || item.dueDate!.isEmpty) return null;
    try {
      final due = DateTime.parse(item.dueDate!);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDateOnly = DateTime(due.year, due.month, due.day);
      if (dueDateOnly.isBefore(today)) return Colors.red;
      if (dueDateOnly.isAtSameMomentAs(today)) return Colors.amber;
    } catch (_) {}
    return null;
  }

  /// Returns true if due within the next 2 hours.
  bool _isDueWithin2Hours() {
    if (item.dueDate == null || item.dueDate!.isEmpty) return false;
    try {
      final now = DateTime.now();
      DateTime due;
      if (item.dueTime != null && item.dueTime!.isNotEmpty) {
        due = DateTime.parse('${item.dueDate!} ${item.dueTime!}');
      } else {
        due = DateTime.parse(item.dueDate!);
      }
      return due.isAfter(now) && due.difference(now).inMinutes <= 120;
    } catch (_) {}
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(item.status);
    final urgencyColor = _urgencyBorderColor();
    final dueSoon = _isDueWithin2Hours();
    final borderColor = urgencyColor ?? Colors.transparent;

    // Find photo for this specific cake item (workItemId match)
    final photosAsync = ref.watch(orderPhotosProvider(item.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final itemIdInt = int.tryParse(item.id);
    final itemPhoto = photosAsync.maybeWhen(
      data: (photos) {
        try {
          return photos.firstWhere((p) => p.workItemId == itemIdInt);
        } catch (_) {
          return null;
        }
      },
      orElse: () => null,
    );
    final photoUrl = itemPhoto != null
        ? '$baseUrl/api/photos/${itemPhoto.photoHash}.jpg'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: product name + birthday + photo + status chip
              Row(
                children: [
                  if (item.isBirthday) ...[
                    const Text('🎂', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      item.quantity > 1
                          ? '${item.productName} ×${item.quantity}'
                          : item.productName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (photoUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: photoUrl,
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
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image_outlined,
                              size: 20, color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: statusColor.withAlpha(120)),
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

              // Customer + order ref
              Row(
                children: [
                  Text(
                    item.customerName,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.orderRef,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),

              // Notes preview (1 line, italic)
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              // Due date/time + price
              if (item.dueDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: dueSoon
                          ? Colors.red
                          : (urgencyColor ?? theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: Colors.red.withAlpha(80)),
                        ),
                        child: Text(
                          _formatDue(item.dueDate, item.dueTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Text(
                        _formatDue(item.dueDate, item.dueTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              urgencyColor ?? theme.colorScheme.outline,
                          fontWeight: urgencyColor != null
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      formatVND(item.unitPrice * item.quantity),
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
                  formatVND(item.unitPrice * item.quantity),
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
    try {
      final d = DateFormat('yyyy-MM-dd').parse(dueDate);
      final dateStr = DateFormat('dd/MM/yyyy').format(d);
      return dueTime != null ? '$dateStr $dueTime' : dateStr;
    } catch (_) {
      return dueTime != null ? '$dueDate $dueTime' : dueDate;
    }
  }
}
