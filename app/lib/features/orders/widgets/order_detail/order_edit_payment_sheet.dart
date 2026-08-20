import 'dart:async';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/payment_transaction.dart';
import '../../../../providers/order_providers.dart';
import '../../providers/order_edit_payment_notifier.dart';
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

class _OrderEditPaymentSheetState
    extends ConsumerState<OrderEditPaymentSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final txn = widget.txn;
    // Defer the seed to avoid modifying a provider during the build phase
    // (initState is part of the build lifecycle). Seed includes the existing
    // `createdAt` (DG-415 Phase 3 / FR2) so the picker opens pre-filled.
    Future.microtask(() {
      if (mounted) {
        ref.read(orderEditPaymentProvider.notifier).seed(
              type: txn.type,
              method: txn.method,
              paymentSource: txn.paymentSource,
              createdAt: txn.createdAt,
            );
      }
    });
    // Convert back from actual amount to thousands for display
    _amountCtrl = TextEditingController(
      text: vndThousandsTextFromAmount(txn.amount),
    );
    _notesCtrl = TextEditingController(text: txn.notes);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = vndFromThousands(double.parse(_amountCtrl.text.trim()));
    ref.read(orderEditPaymentProvider.notifier).setSubmitting(true);
    try {
      final s = ref.read(orderEditPaymentProvider);
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .edit(
            widget.txn.id,
            amount: amount,
            type: s.type,
            method: s.method,
            notes: _notesCtrl.text.trim(),
            paymentSource: s.paymentSource,
            createdAt: s.createdAt,
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, OrdersLabels.paymentUpdated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) ref.read(orderEditPaymentProvider.notifier).setSubmitting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(orderEditPaymentProvider);

    const types = [
      ('deposit', OrdersLabels.txnTypeDeposit),
      ('payment', OrdersLabels.txnTypePayment),
      ('full_payment', OrdersLabels.txnTypeFullPayment),
      ('refund', OrdersLabels.txnTypeRefund),
    ];
    const methods = [('cash', OrdersLabels.methodCash), ('transfer', OrdersLabels.methodTransfer)];

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
                          .read(orderEditPaymentProvider.notifier)
                          .setType(t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(OrdersLabels.paymentMethod, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: s.method == m.$1,
                      onSelected: (_) => ref
                          .read(orderEditPaymentProvider.notifier)
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
                if (v == null || v.trim().isEmpty) return SharedLabels.fieldRequired;
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
            TxnDateTimePickerRow(
              dateTime: s.createdAt ?? widget.txn.createdAt ?? DateTime.now(),
              onDateChanged: ref
                  .read(orderEditPaymentProvider.notifier)
                  .setCreatedDate,
              onTimeChanged: ref
                  .read(orderEditPaymentProvider.notifier)
                  .setCreatedTime,
            ),
            if (s.method == 'transfer') ...[
              const SizedBox(height: 12),
              TargetAccountDropdown(
                value: s.paymentSource,
                onChanged: (value) => ref
                    .read(orderEditPaymentProvider.notifier)
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
            FilledButton(
              onPressed: s.submitting ? null : _submit,
              child: s.submitting
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