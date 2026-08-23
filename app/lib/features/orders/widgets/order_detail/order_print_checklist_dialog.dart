import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/receipt_service.dart';
import '../../../../providers/order_providers.dart';
import '../../../../shared/providers/logged_by_provider.dart';
import '../../providers/order_print_dialog_notifiers.dart';
import '../../providers/order_draft_contexts.dart';
import '../../../../shared/models/form_draft_context.dart';
import '../../../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../../../../providers/form_draft_session_notifier.dart';

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
  late final FormDraftContext _draftContext = OrderDraftContexts.printChecklist(
    widget.orderRef,
  );

  Future<void> _printSelected() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final provider = orderPrintChecklistProvider(_draftContext);
    final s = container.read(provider);
    if (!s.printInternal && !s.printCustomer) return;
    final expectedDraft = container.read(
      formDraftSessionProvider,
    )[_draftContext];
    final printNotifier = container.read(provider.notifier);
    final receiptService = container.read(receiptServiceProvider);
    final printedBy = container.read(loggedByProvider);
    final items =
        container.read(orderWorkItemsProvider(widget.orderRef)).value ?? [];
    printNotifier.startPrinting();

    try {
      // Print internal receipt — one per main work item (via server USB printer)
      if (s.printInternal) {
        final mainItemIds = items
            .where((i) => !i.isExtra && !i.isGift)
            .map((i) => int.tryParse(i.id))
            .whereType<int>()
            .toList();

        for (final itemId in mainItemIds) {
          printNotifier.setStatusText(SharedLabels.printingInternalReceipt);
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
        printNotifier.setStatusText(SharedLabels.printingCustomerReceipt);
        await receiptService.printReceipt(
          orderRef: widget.orderRef,
          type: ReceiptType.customer,
          printedBy: printedBy,
        );
      }

      if (expectedDraft != null) {
        container
            .read(formDraftSessionProvider.notifier)
            .clearDraftIfUnchanged(_draftContext, expectedDraft);
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
      printNotifier.finishPrinting();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(orderWorkItemsProvider(widget.orderRef)).value ?? [];
    final hasMainItems = items.any((i) => !i.isExtra && !i.isGift);
    final provider = orderPrintChecklistProvider(_draftContext);
    final state = ref.watch(provider);

    // If no main items, auto-disable internal receipt (deferred to a
    // post-frame callback so state is not mutated during build).
    if (!hasMainItems && state.printInternal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(provider.notifier)
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
                        .read(provider.notifier)
                        .setPrintInternal(v ?? false),
                    title: const Text(SharedLabels.printWorkTicket),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                CheckboxListTile(
                  value: state.printCustomer,
                  onChanged: (v) =>
                      ref.read(provider.notifier).setPrintCustomer(v ?? false),
                  title: const Text(SharedLabels.printCustomerReceipt),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
      actions: [
        DiscardFormDraftAction(
          isDirty: state.isDirty,
          onDiscard: () {
            ref.read(provider.notifier).clearDraft();
            Navigator.pop(context);
          },
        ),
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
