import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/receipt_service.dart';
import '../../../../providers/order_providers.dart';
import '../../../../shared/providers/logged_by_provider.dart';
import '../../providers/order_print_dialog_notifiers.dart';
import '../../providers/order_draft_contexts.dart';
import '../../../../shared/models/form_draft_context.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Internal receipt print dialog shown when confirming a work item that has
/// not yet been printed. Offers to print the work ticket(s) immediately.
class OrderInternalPrintDialog extends ConsumerStatefulWidget {
  const OrderInternalPrintDialog({
    super.key,
    required this.orderRef,
    this.itemId,
  });

  final String orderRef;
  final int? itemId;

  @override
  ConsumerState<OrderInternalPrintDialog> createState() =>
      _OrderInternalPrintDialogState();
}

class _OrderInternalPrintDialogState
    extends ConsumerState<OrderInternalPrintDialog> {
  late final FormDraftContext _draftContext = OrderDraftContexts.printWorkItem(
    widget.orderRef,
    widget.itemId,
  );

  Future<void> _printInternal() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final provider = orderWorkItemPrintProvider(_draftContext);
    final printNotifier = container.read(provider.notifier);
    final receiptService = container.read(receiptServiceProvider);
    final printedBy = container.read(loggedByProvider);
    final workItems =
        container.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
    final orderDetail = container.read(
      orderDetailProvider(widget.orderRef).notifier,
    );
    printNotifier.startPrinting();

    try {
      // Determine which items to print
      List<int> itemIds;
      if (widget.itemId != null) {
        itemIds = [widget.itemId!];
      } else {
        // Print all main (non-extra, non-gift) items
        itemIds = workItems
            .where((i) => !i.isExtra && !i.isGift)
            .map((i) => int.tryParse(i.id))
            .whereType<int>()
            .toList();
      }

      if (itemIds.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      for (final id in itemIds) {
        printNotifier.setStatusText(SharedLabels.printingInternalReceipt);
        await receiptService.printReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.workTicket,
          itemId: id,
          printedBy: printedBy,
        );
      }

      orderDetail.refresh();
      if (mounted) {
        showTopSnackBar(context, SharedLabels.internalReceiptPrinted);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      printNotifier.finishPrinting();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderWorkItemPrintProvider(_draftContext));
    return AlertDialog(
      title: const Text(SharedLabels.printChecklistTitle),
      content: state.printing
          ? SizedBox(
              height: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    state.statusText,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : const Text(SharedLabels.printInternalPrompt),
      actions: [
        TextButton(
          onPressed: state.printing ? null : () => Navigator.pop(context),
          child: const Text(SharedLabels.printSkip),
        ),
        if (!state.printing)
          FilledButton(
            onPressed: _printInternal,
            child: const Text(SharedLabels.print),
          ),
      ],
    );
  }
}
