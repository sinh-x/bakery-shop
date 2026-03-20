import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/cake_queue_item.dart';
import '../../data/providers/cake_queue_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

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

class _CakeQueueCard extends StatelessWidget {
  const _CakeQueueCard({required this.item, this.onTap});

  final CakeQueueItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColors[item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(item.status);

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
              // Top row: status chip + product name
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: statusColor.withAlpha(100)),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.productName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item.isBirthday)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text('🎂', style: TextStyle(fontSize: 14)),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              // Customer + order ref
              Text(
                '${item.customerName} · ${item.orderRef}',
                style: theme.textTheme.bodySmall,
              ),

              // Due date/time
              if (item.dueDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 13,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDue(item.dueDate, item.dueTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
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
