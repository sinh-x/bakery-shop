import 'package:bakery_app/shared/utils.dart' show workItemStatusLabel;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/work_item.dart';
import '../../../../providers/order_providers.dart';
import '../section_header.dart';
import 'order_detail_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Summary overview widget for the General tab (Phase 3 — DG-334 / FR4 / AC4).
///
/// Renders a compact count of work items grouped by status, e.g.
/// "3 công việc: 2 đã giao, 1 đang làm". This is a *summary count* only — the
/// full work item list lives on the Work Items tab.
///
/// Watches `orderWorkItemsProvider(orderRef)` so it reuses the same
/// already-loaded data as the Work Items tab (NFR1: no network fetch on tab
/// switch).
class OrderWorkItemSummary extends ConsumerWidget {
  const OrderWorkItemSummary({super.key, required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(orderWorkItemsProvider(orderRef));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(OrdersLabels.workItemSummaryTitle),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: itemsAsync.when(
            loading: () => const SizedBox(
              height: 24,
              child: Center(child: LinearProgressIndicator()),
            ),
            error: (e, _) => Text(
              SharedLabels.apiError,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            data: (items) => _WorkItemSummaryBody(items: items),
          ),
        ),
      ],
    );
  }
}

class _WorkItemSummaryBody extends StatelessWidget {
  const _WorkItemSummaryBody({required this.items});

  final List<WorkItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text(
        OrdersLabels.workItemSummaryEmpty,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }

    // Aggregate counts per status in rank order (cancelled last).
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    final orderedStatuses = workItemStatusRank.keys.where(counts.containsKey);
    final parts = <String>[];
    for (final status in orderedStatuses) {
      final label = workItemStatusLabel(status);
      parts.add('${counts[status]} $label');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          OrdersLabels.workItemSummaryCount(items.length),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          parts.join(', '),
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}