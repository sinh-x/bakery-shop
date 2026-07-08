import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order_draft.dart';
import '../../../providers/order/order_create_state_provider.dart';
import 'expandable_item_card.dart';
import 'section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Renders the selected regular items and extras as `ExpandableItemCard`s.
///
/// Reuses `ExpandableItemCard` as-is (per DG-214 guardrails) and forwards
/// edit/remove callbacks to the `OrderCreateStateNotifier`.
class SelectedItemsList extends ConsumerWidget {
  const SelectedItemsList({
    super.key,
    required this.items,
    required this.regularItems,
    required this.extraItems,
  });

  final List<DraftOrderItem> items;
  final List<DraftOrderItem> regularItems;
  final List<DraftOrderItem> extraItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverList(
      delegate: SliverChildListDelegate.fixed(
        [
          const SectionHeader(OrdersLabels.selectedProducts),
          ...regularItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ExpandableItemCard(
                item: item,
                onRemove: () {
                  ref
                      .read(orderCreateStateProvider.notifier)
                      .updateItems([...items.where((i) => i != item)]);
                },
                onQtyChanged: (qty) {
                  item.quantity = qty;
                  ref
                      .read(orderCreateStateProvider.notifier)
                      .updateItems([...items]);
                },
                onStateChanged: () {
                  ref
                      .read(orderCreateStateProvider.notifier)
                      .updateItems([...items]);
                },
              ),
            ),
          ),
          if (extraItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            const SectionHeader(VN.extras),
            ...extraItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ExpandableItemCard(
                  item: item,
                  onRemove: () {
                    ref
                        .read(orderCreateStateProvider.notifier)
                        .updateItems([...items.where((i) => i != item)]);
                  },
                  onQtyChanged: (qty) {
                    item.quantity = qty;
                    ref
                        .read(orderCreateStateProvider.notifier)
                        .updateItems([...items]);
                  },
                  onStateChanged: () {
                    ref
                        .read(orderCreateStateProvider.notifier)
                        .updateItems([...items]);
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}