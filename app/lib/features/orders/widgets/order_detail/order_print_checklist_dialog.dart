import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/receipt_service.dart';
import '../../../../providers/order_providers.dart';
import '../../../../shared/providers/logged_by_provider.dart';
import '../../providers/order_print_dialog_notifiers.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Print checklist dialog shown after the new → confirmed transition
/// (Flow A). Lets staff pick which receipts to print immediately.
class OrderPrintChecklistDialog extends ConsumerStatefulWidget {
  const OrderPrintChecklistDialog({super.key, required this.orderRef});

  final String orderRef;

  @override
  ConsumerState<OrderPrintChecklistDialog> createState() =>
      _OrderPrintChecklistDialogState();
}

class _OrderPrintChecklistDialogState
    extends ConsumerState<OrderPrintChecklistDialog> {
  Future<void> _printSelected() async {
    final s = ref.read(orderPrintChecklistProvider);
    if (!s.printInternal && !s.printCustomer) return;

    ref.read(orderPrintChecklistProvider.notifier).startPrinting();

    try {
      final receiptService = ref.read(receiptServiceProvider);
      final printedBy = ref.read(loggedByProvider);

      // Print internal receipt — one per main work item (via server USB printer)
      if (s.printInternal) {
        final items =
            ref.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
        final mainItemIds = items
            .where((i) => !i.isExtra && !i.isGift)
            .map((i) => int.tryParse(i.id))
            .whereType<int>()
            .toList();

        for (final itemId in mainItemIds) {
          ref
              .read(orderPrintChecklistProvider.notifier)
              .setStatusText(SharedLabels.printingInternalReceipt);
          await receiptService.printReceipt(
            orderRef: widget.orderRef,
            type: ReceiptType.workTicket,
            itemId: itemId,
            printedBy: printedBy,
          );
        }

        if (mainItemIds.isNotEmpty) {
          if (mounted) {
            showTopSnackBar(context, SharedLabels.internalReceiptPrinted);
          }
        }
      }

      // Print customer receipt (via server USB printer)
      if (s.printCustomer) {
        ref
            .read(orderPrintChecklistProvider.notifier)
            .setStatusText(SharedLabels.printingCustomerReceipt);
        await receiptService.printReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.customer,
          printedBy: printedBy,
        );
      }

      if (mounted) {
        showTopSnackBar(context, SharedLabels.printSuccess);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) {
        ref.read(orderPrintChecklistProvider.notifier).finishPrinting();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(orderWorkItemsProvider(widget.orderRef)).value ?? [];
    final hasMainItems = items.any((i) => !i.isExtra && !i.isGift);
    final state = ref.watch(orderPrintChecklistProvider);

    // If no main items, auto-disable internal receipt (deferred to a
    // post-frame callback so state is not mutated during build).
    if (!hasMainItems && state.printInternal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(orderPrintChecklistProvider.notifier)
            .autoDisableInternalIfNoMainItems(hasMainItems);
      });
    }

    final hasSelection = state.printInternal || state.printCustomer;

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
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMainItems)
                  CheckboxListTile(
                    value: state.printInternal,
                    onChanged: (v) => ref
                        .read(orderPrintChecklistProvider.notifier)
                        .setPrintInternal(v ?? false),
                    title: const Text(SharedLabels.printWorkTicket),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                CheckboxListTile(
                  value: state.printCustomer,
                  onChanged: (v) => ref
                      .read(orderPrintChecklistProvider.notifier)
                      .setPrintCustomer(v ?? false),
                  title: const Text(SharedLabels.printCustomerReceipt),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: state.printing ? null : () => Navigator.pop(context),
          child: const Text(SharedLabels.printSkip),
        ),
        if (!state.printing)
          FilledButton(
            onPressed: hasSelection ? _printSelected : null,
            child: const Text(SharedLabels.print),
          ),
      ],
    );
  }
}