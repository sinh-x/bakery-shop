import 'dart:async';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/payment_transaction.dart';
import '../../../../providers/order_providers.dart';
import '../../providers/order_edit_payment_notifier.dart';
import '../../providers/order_draft_contexts.dart';
import '../../providers/order_form_operation_notifier.dart';
import '../../../../shared/models/form_draft_context.dart';
import '../../../../shared/widgets/discard_form_draft_action.dart';
import '../../../../providers/form_draft_session_notifier.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/utils/vnd_units.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'txn_photo_section.dart';
import 'txn_date_time_picker_row.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Bottom sheet for editing an existing payment transaction.
class OrderEditPaymentSheet extends ConsumerStatefulWidget {
  const OrderEditPaymentSheet({
    super.key,
    required this.orderRef,
    required this.txn,
  });

  final String orderRef;
  final PaymentTransaction txn;

  @override
  ConsumerState<OrderEditPaymentSheet> createState() =>
      _OrderEditPaymentSheetState();
}

class _OrderEditPaymentSheetState extends ConsumerState<OrderEditPaymentSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late final FormDraftContext _draftContext;
  late final OrderEditPaymentNotifier _draftNotifier;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final txn = widget.txn;
    _draftContext = OrderDraftContexts.editPayment(widget.orderRef, txn.id);
    _draftNotifier = ref.read(orderEditPaymentProvider(_draftContext).notifier);
    // Defer the seed to avoid modifying a provider during the build phase
    // (initState is part of the build lifecycle). Seed includes the existing
    // `createdAt` (DG-415 Phase 3 / FR2) so the picker opens pre-filled.
    //
    // review-auto cycle 1 CQ-1: convert the stored UTC `createdAt` to
    // server-local wall-clock once at the seed boundary. From here on the
    // notifier/picker only deal with local DateTime fields, so editing the
    // date or time no longer double-shifts the stored timestamp (the
    // `timestampToJson` on save calls `.toUtc()` which exactly reverses this
    // single local conversion).
    Future.microtask(() {
      if (mounted) {
        final localCreatedAt = txn.createdAt == null
            ? null
            : ServerTimezone.toServerLocal(txn.createdAt!);
        _draftNotifier.seed(
          type: txn.type,
          method: txn.method,
          paymentSource: txn.paymentSource,
          createdAt: localCreatedAt,
          amount: vndThousandsTextFromAmount(txn.amount),
          notes: txn.notes,
        );
      }
    });
    // Convert back from actual amount to thousands for display
    final draft = ref.read(orderEditPaymentProvider(_draftContext));
    final hasDraft = ref
        .read(formDraftSessionProvider)
        .containsKey(_draftContext);
    _amountCtrl = TextEditingController(
      text: hasDraft ? draft.amount : vndThousandsTextFromAmount(txn.amount),
    )..addListener(_persistAmount);
    _notesCtrl = TextEditingController(text: hasDraft ? draft.notes : txn.notes)
      ..addListener(_persistNotes);
  }

  void _persistAmount() => _draftNotifier.setAmount(_amountCtrl.text);

  void _persistNotes() => _draftNotifier.setNotes(_notesCtrl.text);

  @override
  void dispose() {
    _amountCtrl.removeListener(_persistAmount);
    _notesCtrl.removeListener(_persistNotes);
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final draftProvider = orderEditPaymentProvider(_draftContext);
    final draft = container.read(draftProvider);
    final expectedDraft = container.read(
      formDraftSessionProvider,
    )[_draftContext];
    final operation = container.read(
      orderFormOperationProvider(_draftContext).notifier,
    );
    final generation = operation.start();
    final transactions = container.read(
      orderPaymentTransactionsProvider(widget.orderRef).notifier,
    );
    final notes = _notesCtrl.text.trim();
    final amount = vndFromThousands(double.parse(_amountCtrl.text.trim()));
    try {
      await transactions.edit(
        widget.txn.id,
        amount: amount,
        type: draft.type,
        method: draft.method,
        notes: notes,
        paymentSource: draft.paymentSource,
        createdAt: draft.createdAt,
      );
      if (expectedDraft != null) {
        container
            .read(formDraftSessionProvider.notifier)
            .clearDraftIfUnchanged(_draftContext, expectedDraft);
      }
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, OrdersLabels.paymentUpdated);
      }
    } catch (e) {
      operation.failIfCurrent(generation, e);
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      operation.finishIfCurrent(generation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(orderEditPaymentProvider(_draftContext));
    final operation = ref.watch(orderFormOperationProvider(_draftContext));

    const types = [
      ('deposit', OrdersLabels.txnTypeDeposit),
      ('payment', OrdersLabels.txnTypePayment),
      ('full_payment', OrdersLabels.txnTypeFullPayment),
      ('refund', OrdersLabels.txnTypeRefund),
    ];
    const methods = [
      ('cash', OrdersLabels.methodCash),
      ('transfer', OrdersLabels.methodTransfer),
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(OrdersLabels.editPayment, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(OrdersLabels.txnType, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: s.type == t.$1,
                      onSelected: (_) => ref
                          .read(
                            orderEditPaymentProvider(_draftContext).notifier,
                          )
                          .setType(t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(
              OrdersLabels.paymentMethod,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: s.method == m.$1,
                      onSelected: (_) => ref
                          .read(
                            orderEditPaymentProvider(_draftContext).notifier,
                          )
                          .setMethod(m.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: OrdersLabels.paymentAmountLabel,
                border: OutlineInputBorder(),
                suffixText: ',000đ',
                helperText: OrdersLabels.paymentThousandsHint,
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return SharedLabels.fieldRequired;
                }
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return SharedLabels.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: OrdersLabels.paymentNotes,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // DG-415 Phase 3 / FR2, FR7 — date+time picker pre-filled with the
            // existing `createdAt` and limited to past→today. The notifier
            // merges date+time so the edited timestamp persists as UTC Z on
            // save and re-syncs the journal entry `transaction_date` (AC4).
            //
            // CQ-1: `s.createdAt` is already a server-local DateTime (seeded
            // via `ServerTimezone.toServerLocal`), so the picker formats local
            // wall-clock fields directly. The fallback path also converts the
            // raw UTC `txn.createdAt` through `toServerLocal` so the picker
            // never reads raw UTC fields.
            TxnDateTimePickerRow(
              dateTime:
                  s.createdAt ??
                  (widget.txn.createdAt == null
                      ? DateTime.now()
                      : ServerTimezone.toServerLocal(widget.txn.createdAt!)),
              onDateChanged: ref
                  .read(orderEditPaymentProvider(_draftContext).notifier)
                  .setCreatedDate,
              onTimeChanged: ref
                  .read(orderEditPaymentProvider(_draftContext).notifier)
                  .setCreatedTime,
            ),
            if (s.method == 'transfer') ...[
              const SizedBox(height: 12),
              TargetAccountDropdown(
                value: s.paymentSource,
                onChanged: (value) => ref
                    .read(orderEditPaymentProvider(_draftContext).notifier)
                    .setPaymentSource(value),
              ),
            ],
            const SizedBox(height: 12),
            TxnPhotoSection(
              orderRef: widget.orderRef,
              txnId: widget.txn.id,
              showRemove: true,
              showEmptyState: false,
            ),
            const SizedBox(height: 16),
            DiscardFormDraftAction(
              isDirty: s.isDirty,
              onDiscard: () {
                _draftNotifier.clearDraft();
                Navigator.pop(context);
              },
            ),
            FilledButton(
              onPressed: operation.busy ? null : _submit,
              child: operation.busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(OrdersLabels.editPayment),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
