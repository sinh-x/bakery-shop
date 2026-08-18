import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/api/receipt_service.dart';
import '../../data/models/work_item.dart';
import '../../providers/order_providers.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/cake_detail_body.dart';
import 'widgets/internal_print_dialog.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
const _workItemStatusRank = {
  'pending': 0,
  'confirmed': 1,
  'working': 2,
  'ready': 3,
  'delivered': 4,
  'cancelled': 5,
};

bool _isBackwardItem(String current, String target) =>
    (_workItemStatusRank[target] ?? 0) < (_workItemStatusRank[current] ?? 0);

Future<String?> _showItemReasonDialog(
  BuildContext context,
  String targetStatus,
) async {
  final ctrl = TextEditingController();
  final isCancel = targetStatus == 'cancelled';
  final theme = Theme.of(context);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(isCancel ? OrdersLabels.cancelOrderTitle : OrdersLabels.statusReasonTitle),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: OrdersLabels.statusReasonLabel,
              hintText: OrdersLabels.statusReasonHint,
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            autofocus: true,
            onChanged: (_) => setS(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(SharedLabels.cancel),
            ),
            FilledButton(
              style: isCancel
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    )
                  : null,
              onPressed: ctrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(
                isCancel ? OrdersLabels.confirmCancelAction : OrdersLabels.confirmStatusChange,
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    ctrl.dispose();
  }
}

class CakeDetailScreen extends ConsumerStatefulWidget {
  const CakeDetailScreen({
    super.key,
    required this.orderRef,
    required this.workItemId,
  });

  final String orderRef;
  final String workItemId;

  @override
  ConsumerState<CakeDetailScreen> createState() => _CakeDetailScreenState();
}

class _CakeDetailScreenState extends ConsumerState<CakeDetailScreen> {
  bool _transitioning = false;
  bool _saving = false;

  Future<void> _onTransition(WorkItem item, String targetStatus) async {
    if (_transitioning) return;
    String reason = '';
    if (_isBackwardItem(item.status, targetStatus) ||
        targetStatus == 'cancelled') {
      final r = await _showItemReasonDialog(context, targetStatus);
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
      if (targetStatus == 'confirmed' && mounted) {
        final order = ref.read(orderDetailProvider(widget.orderRef)).value;
        if (order != null && order.workTicketPrintedAt == null) {
          await _showInternalPrintPrompt(int.tryParse(item.id));
        }
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
          InternalPrintDialog(orderRef: widget.orderRef, itemId: itemId),
    );
  }

  Future<void> _onSave(
    WorkItem item, {
    required String notes,
    required bool isBirthday,
    int? age,
    required double unitPrice,
    Map<String, dynamic>? attributes,
  }) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(orderWorkItemsProvider(widget.orderRef).notifier)
          .edit(
            item.id,
            notes: notes,
            isBirthday: isBirthday,
            age: age,
            unitPrice: unitPrice,
            attributes: attributes,
          );
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.orderEditSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
        rethrow;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(orderWorkItemsProvider(widget.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(OrdersLabels.cakeDetail),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: OrdersLabels.viewOrder,
            onPressed: () => context.push('/orders/${widget.orderRef}'),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: SharedLabels.printReceipt,
            onPressed: () => context.push(
              '/orders/${widget.orderRef}/receipt?type=${ReceiptType.workTicket.value}&item_id=${widget.workItemId}',
            ),
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(SharedLabels.apiError),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref
                    .read(orderWorkItemsProvider(widget.orderRef).notifier)
                    .refresh(),
                child: const Text(SharedLabels.retry),
              ),
            ],
          ),
        ),
        data: (items) {
          final item = items
              .where((i) => i.id == widget.workItemId)
              .firstOrNull;
          if (item == null) {
            return Center(
              child: Text(
                'Không tìm thấy sản phẩm',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          return CakeDetailBody(
            item: item,
            orderRef: widget.orderRef,
            baseUrl: baseUrl,
            transitioning: _transitioning,
            saving: _saving,
            onTransition: (t) => _onTransition(item, t),
            onSave: (notes, isBirthday, age, unitPrice, {attributes}) =>
                _onSave(
              item,
              notes: notes,
              isBirthday: isBirthday,
              age: age,
              unitPrice: unitPrice,
              attributes: attributes,
            ),
          );
        },
      ),
    );
  }
}