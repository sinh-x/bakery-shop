import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/receipt_service.dart';
import '../../../data/services/printer_service.dart';
import '../../../shared/providers/logged_by_provider.dart';
import '../../../providers/order_providers.dart';
import '../../../providers/printer_provider.dart';
import '../providers/google_maps_modal_notifier.dart';
import '../providers/order_draft_contexts.dart';
import '../../../shared/models/form_draft_context.dart';
import '../../../shared/widgets/printer_picker_dialog.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Dialog shown after confirming a work item, prompting the staff to print
/// the internal receipt (work ticket) for that item.
///
/// Extracted from `cake_detail_screen.dart` (DG-294 NFR1) to keep
/// `CakeDetailScreen` under 500 lines.
class InternalPrintDialog extends ConsumerStatefulWidget {
  const InternalPrintDialog({super.key, required this.orderRef, this.itemId});

  final String orderRef;
  final int? itemId;

  @override
  ConsumerState<InternalPrintDialog> createState() =>
      _InternalPrintDialogState();
}

class _InternalPrintDialogState extends ConsumerState<InternalPrintDialog> {
  late final FormDraftContext _operationContext =
      OrderDraftContexts.printWorkItem(widget.orderRef, widget.itemId);

  Future<void> _printInternal() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final printNotifier = container.read(
      internalPrintProvider(_operationContext).notifier,
    );
    final receiptService = container.read(receiptServiceProvider);
    final printedBy = container.read(loggedByProvider);
    final orderDetail = container.read(
      orderDetailProvider(widget.orderRef).notifier,
    );
    final printerService = container.read(printerServiceProvider);
    final printer = container.read(printerProvider.notifier);
    printNotifier.startPrinting(
      statusText: SharedLabels.fetchingInternalReceipt,
    );

    try {
      if (kIsWeb) {
        await receiptService.printReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.workTicket,
          itemId: widget.itemId,
          printedBy: printedBy,
        );
        orderDetail.refresh();
        if (mounted) {
          showTopSnackBar(context, SharedLabels.internalReceiptPrinted);
          Navigator.pop(context);
        }
        return;
      }

      await printerService.init();

      final internalBytes = await receiptService.fetchReceipt(
        orderRef: widget.orderRef,
        type: ReceiptType.workTicket,
        itemId: widget.itemId,
      );

      printNotifier.setStatusText(SharedLabels.printingInternalReceipt);

      PrinterPickerResult result = PrinterPickerResult.cancelled;
      if (printerService.lastPrinterMac != null) {
        try {
          await printerService.connect(printerService.lastPrinterMac!);
          final success = await printer.printImage(internalBytes);
          if (success) {
            result = PrinterPickerResult.success;
          }
        } catch (_) {
          // Fall through to picker
        }
      }

      if (result != PrinterPickerResult.success && mounted) {
        result = await showPrinterPickerDialog(
          context: context,
          imageBytes: internalBytes,
          printerService: printerService,
        );
      }

      if (result == PrinterPickerResult.success) {
        orderDetail.refresh();
        if (mounted) {
          showTopSnackBar(context, SharedLabels.internalReceiptPrinted);
          Navigator.pop(context);
        }
        return;
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
    final state = ref.watch(internalPrintProvider(_operationContext));
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
