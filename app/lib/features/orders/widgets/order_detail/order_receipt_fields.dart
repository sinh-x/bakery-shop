import 'package:flutter/material.dart';

import '../../providers/order_record_payment_notifier.dart';
import '../../../../shared/labels/orders.dart';
import '../../../../shared/labels/shared.dart';
import '../../../../shared/widgets/target_account_dropdown.dart';
import 'txn_date_time_picker_row.dart';

/// Receipt fields shared with the contextual draft owned by the parent sheet.
class OrderReceiptFields extends StatelessWidget {
  const OrderReceiptFields({
    super.key,
    required this.state,
    required this.notifier,
    required this.amountController,
    required this.notesController,
    required this.onTypeSelected,
    required this.onPickPhoto,
  });

  final OrderRecordPaymentState state;
  final OrderRecordPaymentNotifier notifier;
  final TextEditingController amountController;
  final TextEditingController notesController;
  final ValueChanged<String> onTypeSelected;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    const types = [
      ('deposit', OrdersLabels.txnTypeDeposit),
      ('payment', OrdersLabels.txnTypePayment),
      ('full_payment', OrdersLabels.txnTypeFullPayment),
      ('tien_rut', OrdersLabels.txnTypeRutTien),
      ('refund', OrdersLabels.txnTypeRefund),
    ];
    final methods = [
      ('cash', OrdersLabels.methodCash),
      ('transfer', OrdersLabels.methodTransfer),
      if (state.type != 'refund' && state.type != 'tien_rut')
        ('unknown', OrdersLabels.methodUnknown),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          OrdersLabels.txnType,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in types)
              ChoiceChip(
                label: Text(type.$2),
                selected: state.type == type.$1,
                onSelected: (_) => onTypeSelected(type.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          OrdersLabels.paymentMethod,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final method in methods)
              ChoiceChip(
                label: Text(method.$2),
                selected: state.method == method.$1,
                onSelected: (_) => notifier.setMethod(method.$1),
              ),
          ],
        ),
        if (state.method == 'unknown')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(OrdersLabels.unknownReceiptHint),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: amountController,
          decoration: const InputDecoration(
            labelText: OrdersLabels.paymentAmountLabel,
            border: OutlineInputBorder(),
            suffixText: ',000đ',
            helperText: OrdersLabels.paymentThousandsHint,
          ),
          keyboardType: TextInputType.number,
          autofocus: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return SharedLabels.fieldRequired;
            }
            final amount = double.tryParse(value.trim());
            return amount == null || !amount.isFinite || amount <= 0
                ? SharedLabels.invalidPrice
                : null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: notesController,
          decoration: const InputDecoration(
            labelText: OrdersLabels.paymentNotes,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TxnDateTimePickerRow(
          dateTime: state.createdAt ?? DateTime.now(),
          onDateChanged: notifier.setCreatedDate,
          onTimeChanged: notifier.setCreatedTime,
        ),
        if (state.method == 'transfer') ...[
          const SizedBox(height: 12),
          TargetAccountDropdown(
            value: state.paymentSource,
            onChanged: notifier.setPaymentSource,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: OrdersLabels.attachTransferPhotoTooltip,
              child: TextButton.icon(
                onPressed: onPickPhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 20),
                label: Text(
                  state.pendingTransferPhoto == null
                      ? OrdersLabels.attachTransferPhoto
                      : OrdersLabels.transferPhotoSelected,
                ),
              ),
            ),
          ),
          if (state.pendingTransferPhoto != null)
            Text(
              state.pendingTransferPhoto!.name,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ],
    );
  }
}
