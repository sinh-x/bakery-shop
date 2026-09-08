import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/order_inventory_audit.dart';
import '../../../../data/providers/order/order_inventory_audit_provider.dart';
import '../../../../shared/labels/stock.dart';
import 'order_inventory_audit_entry_tile.dart';

class OrderInventoryReviewTab extends ConsumerWidget {
  const OrderInventoryReviewTab({super.key, required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audit = ref.watch(orderInventoryAuditProvider(orderRef));
    final notifier = ref.read(orderInventoryAuditProvider(orderRef).notifier);

    return audit.when(
      loading: _inventoryAuditLoading,
      error: (_, _) => _inventoryAuditError(notifier.retry),
      data: (value) {
        if (!value.initialized) return _inventoryAuditLoading();
        if (value.items.isEmpty) {
          return _inventoryAuditEmpty(notifier.refresh);
        }
        final groups = _groupByOperation(value.items);
        return RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView(
            key: const Key('order-inventory-audit-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              if (value.isRefreshing) const LinearProgressIndicator(),
              if (value.laterRequestFailed)
                _retainedAuditError(context, notifier.retryRetainedFailure),
              for (final group in groups) _OperationGroup(entries: group),
              if (value.hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    key: const Key('inventory-audit-load-more'),
                    onPressed: value.isLoadingMore ? null : notifier.loadMore,
                    icon: value.isLoadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more),
                    label: Text(
                      value.isLoadingMore
                          ? StockLabels.inventoryAuditLoadingMore
                          : StockLabels.inventoryAuditLoadMore,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

List<List<OrderInventoryAuditEntry>> _groupByOperation(
  List<OrderInventoryAuditEntry> entries,
) {
  final grouped = <String, List<OrderInventoryAuditEntry>>{};
  for (final entry in entries) {
    grouped.putIfAbsent(entry.operationId, () => []).add(entry);
  }
  return grouped.values.toList(growable: false);
}

class _OperationGroup extends StatelessWidget {
  const _OperationGroup({required this.entries});

  final List<OrderInventoryAuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('inventory-operation-${entries.first.operationId}'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                StockLabels.inventoryAuditOperationTitle(entries.length),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          for (final entry in entries)
            OrderInventoryAuditEntryTile(entry: entry),
        ],
      ),
    );
  }
}

Widget _inventoryAuditLoading() => const Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircularProgressIndicator(),
      SizedBox(height: 12),
      Text(StockLabels.inventoryAuditLoading),
    ],
  ),
);

Widget _inventoryAuditError(VoidCallback onRetry) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline),
      const SizedBox(height: 8),
      const Text(StockLabels.inventoryAuditError),
      TextButton(
        key: const Key('inventory-audit-retry'),
        onPressed: onRetry,
        child: const Text(StockLabels.inventoryAuditRetry),
      ),
    ],
  ),
);

Widget _inventoryAuditEmpty(VoidCallback onRefresh) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.inventory_2_outlined),
      const SizedBox(height: 8),
      const Text(StockLabels.inventoryAuditEmpty),
      TextButton(
        onPressed: onRefresh,
        child: const Text(StockLabels.inventoryAuditRefresh),
      ),
    ],
  ),
);

Widget _retainedAuditError(BuildContext context, VoidCallback onRetry) => Card(
  color: Theme.of(context).colorScheme.errorContainer,
  child: ListTile(
    leading: const Icon(Icons.warning_amber_outlined),
    title: const Text(StockLabels.inventoryAuditRetainedError),
    trailing: TextButton(
      onPressed: onRetry,
      child: const Text(StockLabels.inventoryAuditRetry),
    ),
  ),
);
