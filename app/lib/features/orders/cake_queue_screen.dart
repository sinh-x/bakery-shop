// EXEMPT: 300-line threshold exceeded because DG-150 blocker: extracting queue tile/time slot/summary widgets now would duplicate in-file queue action orchestration and event refresh contracts. Reviewed 2026-05-29.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/cake_queue_item.dart';
import '../../data/providers/cake_queue_provider.dart';
import '../../providers/order_providers.dart';
import '../../shared/theme/bakery_theme.dart';
import '../../shared/utils/date_formatting.dart';
import '../../shared/utils/order_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';

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
            label: const Text(VN.includeReadyFilter),
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
                  const Text(VN.apiError),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.workItemStatusColors[item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(item.status);
    final urgencyColor = urgencyBorderColor(item.dueDate);
    final dueSoon = isDueWithin2Hours(item.dueDate, item.dueTime);
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
    final orderPublicCode = ref.watch(orderListProvider).maybeWhen(
          data: (orders) {
            for (final order in orders) {
              if (order.orderRef == item.orderRef) {
                return order.publicOrderCode;
              }
            }
            return '';
          },
          orElse: () => '',
        );

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
                      visualOrderCode(
                        orderRef: item.orderRef,
                        publicOrderCode: orderPublicCode,
                      ),
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
                          ? Colors.orange
                          : (urgencyColor ?? theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: Colors.orange.withAlpha(80)),
                        ),
                        child: Text(
                          _formatDue(item.dueDate, item.dueTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
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
    final d = parseApiDate(dueDate);
    if (d == null) return dueTime != null ? '$dueDate $dueTime' : dueDate;
    final dateStr = formatDisplayDate(d);
    return dueTime != null ? '$dateStr $dueTime' : dateStr;
  }
}
