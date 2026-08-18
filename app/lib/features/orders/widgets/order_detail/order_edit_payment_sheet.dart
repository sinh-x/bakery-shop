import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/payment_transaction.dart';
import '../../../../providers/order_providers.dart';
import 'package:bakery_app/shared/utils/vnd_units.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'txn_photo_section.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

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
  late String _type;
  late String _method;
  String? _paymentSource;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _type = widget.txn.type;
    _method = widget.txn.method;
    _paymentSource = widget.txn.paymentSource;
    // Convert back from actual amount to thousands for display
    _amountCtrl = TextEditingController(
      text: vndThousandsTextFromAmount(widget.txn.amount),
    );
    _notesCtrl = TextEditingController(text: widget.txn.notes);
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
    setState(() => _submitting = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .edit(
            widget.txn.id,
            amount: amount,
            type: _type,
            method: _method,
            notes: _notesCtrl.text.trim(),
            paymentSource: _paymentSource,
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.paymentUpdated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const types = [
      ('deposit', VN.txnTypeDeposit),
      ('payment', VN.txnTypePayment),
      ('full_payment', VN.txnTypeFullPayment),
      ('refund', VN.txnTypeRefund),
    ];
    const methods = [('cash', VN.methodCash), ('transfer', VN.methodTransfer)];

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
            Text(VN.editPayment, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(VN.txnType, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: _type == t.$1,
                      onSelected: (_) => setState(() => _type = t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(VN.paymentMethod, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: _method == m.$1,
                      onSelected: (_) => setState(() {
                    _method = m.$1;
                    if (m.$1 != 'transfer') _paymentSource = null;
                  }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentAmountLabel,
                border: OutlineInputBorder(),
                suffixText: ',000đ',
                helperText: VN.paymentThousandsHint,
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return VN.fieldRequired;
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return VN.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentNotes,
                border: OutlineInputBorder(),
              ),
            ),
            if (_method == 'transfer') ...[
              const SizedBox(height: 12),
              TargetAccountDropdown(
                value: _paymentSource,
                onChanged: (value) =>
                    setState(() => _paymentSource = value),
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
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(VN.editPayment),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}