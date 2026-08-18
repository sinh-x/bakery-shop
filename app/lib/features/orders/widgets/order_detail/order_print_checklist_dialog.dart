import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/receipt_service.dart';
import '../../../../providers/order_providers.dart';
import '../../../../shared/providers/logged_by_provider.dart';
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
  bool _printInternal = true;
  bool _printCustomer = true;
  bool _printing = false;
  String _statusText = '';

  Future<void> _printSelected() async {
    if (!_printInternal && !_printCustomer) return;

    setState(() => _printing = true);

    try {
      final receiptService = ref.read(receiptServiceProvider);
      final printedBy = ref.read(loggedByProvider);

      // Print internal receipt — one per main work item (via server USB printer)
      if (_printInternal) {
        final items =
            ref.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
        final mainItemIds = items
            .where((i) => !i.isExtra && !i.isGift)
            .map((i) => int.tryParse(i.id))
            .whereType<int>()
            .toList();

        for (final itemId in mainItemIds) {
          setState(() => _statusText = SharedLabels.printingInternalReceipt);
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
      if (_printCustomer) {
        setState(() => _statusText = SharedLabels.printingCustomerReceipt);
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
        setState(() => _printing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(orderWorkItemsProvider(widget.orderRef)).value ?? [];
    final hasMainItems = items.any((i) => !i.isExtra && !i.isGift);

    // If no main items, auto-disable internal receipt
    if (!hasMainItems && _printInternal) {
      _printInternal = false;
    }

    final hasSelection = _printInternal || _printCustomer;

    return AlertDialog(
      title: const Text(SharedLabels.printChecklistTitle),
      content: _printing
          ? SizedBox(
              height: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _statusText,
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
                    value: _printInternal,
                    onChanged: (v) =>
                        setState(() => _printInternal = v ?? false),
                    title: const Text(SharedLabels.printWorkTicket),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                CheckboxListTile(
                  value: _printCustomer,
                  onChanged: (v) => setState(() => _printCustomer = v ?? false),
                  title: const Text(SharedLabels.printCustomerReceipt),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.pop(context),
          child: const Text(SharedLabels.printSkip),
        ),
        if (!_printing)
          FilledButton(
            onPressed: hasSelection ? _printSelected : null,
            child: const Text(SharedLabels.print),
          ),
      ],
    );
  }
}