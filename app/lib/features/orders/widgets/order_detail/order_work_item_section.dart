// EXEMPT: 200-line threshold exceeded because the section renders per-status
// work item groups with inline filtering and navigation wiring that share
// the section's scroll controller and state context.
// Reviewed 2026-07-30.
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND, showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/api/api_client.dart';
import '../../../../data/models/order.dart';
import '../../../../data/models/work_item.dart';
import '../../../../providers/order_providers.dart';
import '../../../../data/providers/products_provider.dart';
import '../enum_attribute_display.dart';
import 'order_detail_helpers.dart';
import 'order_work_item_card.dart';
import 'order_work_item_print_dialog.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Expandable section listing the order's work items (regular + extras),
/// with per-item status transition and internal-print prompts.
class OrderWorkItemSection extends ConsumerStatefulWidget {
  const OrderWorkItemSection({
    super.key,
    required this.orderRef,
    required this.order,
  });

  final String orderRef;
  final Order order;

  @override
  ConsumerState<OrderWorkItemSection> createState() =>
      _OrderWorkItemSectionState();
}

class _OrderWorkItemSectionState extends ConsumerState<OrderWorkItemSection> {
  bool _expanded = true;
  bool _transitioning = false;

  Future<void> _onTransitionWorkItem(
    WorkItem item,
    String targetStatus,
  ) async {
    if (_transitioning) return;
    String reason = '';
    if (isBackward(item.status, targetStatus, workItemStatusRank)) {
      final r = await showReasonDialog(context, targetStatus);
      if (r == null || !mounted) return;
      reason = r;
    }

    setState(() => _transitioning = true);
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .transitionStatus(item.id, targetStatus, reason: reason);
      // Refresh order detail to pick up server-synced order status
      ref.read(orderDetailProvider(widget.orderRef).notifier).refresh();
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.workItemStatusChanged);
      }

      // Prompt to print internal receipt if confirming and not yet printed
      if (targetStatus == 'confirmed' &&
          widget.order.workTicketPrintedAt == null &&
          mounted) {
        await _showInternalPrintPrompt(int.tryParse(item.id));
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _showInternalPrintPrompt(int? itemId) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          OrderInternalPrintDialog(orderRef: widget.orderRef, itemId: itemId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
    final products = ref.watch(productsProvider).asData?.value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    OrdersLabels.workItemsSection,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          itemsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                SharedLabels.apiError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    OrdersLabels.noWorkItems,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                );
              }
              final regularItems = items.where((i) => !i.isExtra).toList();
              final extraItems = items.where((i) => i.isExtra).toList();
              final allPhotos =
                  ref.watch(orderPhotosProvider(widget.orderRef)).value ?? [];
              final baseUrl = ref.watch(apiBaseUrlProvider);
              return Column(
                children: [
                  const SizedBox(height: 4),
                  ...regularItems.map(
                    (item) => OrderWorkItemCard(
                      item: item,
                      enumAttributes: enumAttributesFor(
                        item.productId,
                        products,
                      ),
                      photos: allPhotos.where((p) {
                        final wId = p.workItemId;
                        return wId != null && wId == int.tryParse(item.id);
                      }).toList(),
                      baseUrl: baseUrl,
                      onTransition: _transitioning
                          ? null
                          : (t) => _onTransitionWorkItem(item, t),
                      onTap: () => context.push(
                        '/orders/${widget.orderRef}/items/${item.id}',
                      ),
                    ),
                  ),
                  if (extraItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        OrdersLabels.extras,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: extraItems.map((item) {
                        final label = item.isGift
                            ? '${item.productName} (Tặng)'
                            : '${item.productName} (${formatVND(item.unitPrice)})';
                        return Chip(
                          avatar: Icon(
                            item.isGift ? Icons.card_giftcard : Icons.sell,
                            size: 14,
                            color: item.isGift
                                ? Colors.green
                                : theme.colorScheme.outline,
                          ),
                          label: Text(
                            item.quantity > 1
                                ? '$label ×${item.quantity}'
                                : label,
                            style: theme.textTheme.bodySmall,
                          ),
                          backgroundColor: item.isGift
                              ? Colors.green.withValues(alpha: 0.1)
                              : theme.colorScheme.surfaceContainerHighest,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}