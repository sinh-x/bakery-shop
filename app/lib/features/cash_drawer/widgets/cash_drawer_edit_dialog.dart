import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Result returned by the edit-transaction dialog (DG-379 Phase 4.3).
///
/// `null` means the user cancelled. A non-null value carries the entered
/// amount (VND integer) and/or notes so the caller can invoke
/// [CashDrawerService.editTransaction]. Either field may be `null` when the
/// owner leaves it unchanged (the caller passes `null` through to the
/// service, which omits it from the PATCH body).
class CashDrawerEditResult {
  const CashDrawerEditResult({this.amount, this.notes});

  /// New amount in VND, or `null` to leave the amount unchanged.
  final int? amount;

  /// New notes/description, or `null` to leave the notes unchanged. An empty
  /// string is a deliberate clear (sent through); `null` means "don't touch".
  final String? notes;
}

/// DG-379 Phase 4.3 (FR1-FR3, AC1/AC2): shows the edit-transaction dialog for
/// an open or close transaction.
///
/// Pre-fills the current [amount] and [notes] so the owner can adjust either
/// field. Returns a [CashDrawerEditResult] with the new values, or `null`
/// when cancelled. The amount field uses the same thousand-separator
/// formatter as the open/close/cash-in/cash-out dialogs in
/// `cash_drawer_action_dialogs.dart`. The notes field mirrors the note input
/// in those dialogs.
///
/// The caller is responsible for the reconciled guard (AC5) — this dialog is
/// only shown for editable transactions. The [txnTypeLabel] is rendered in
/// the dialog title so the owner sees which transaction type they are
/// editing ("Sửa giao dịch — Mở quầy").
Future<CashDrawerEditResult?> showEditTransactionDialog(
  BuildContext context, {
  required int currentAmount,
  required String currentNotes,
  required String txnTypeLabel,
}) async {
  final amountCtrl = TextEditingController(
    text: _formatThousands(currentAmount),
  );
  final noteCtrl = TextEditingController(text: currentNotes);
  final formKey = GlobalKey<FormState>();

  return showDialog<CashDrawerEditResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${CashDrawerLabels.cashDrawerEditTxnTitle} — $txnTypeLabel'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: const [_ThousandsSeparatorInputFormatter()],
                decoration: const InputDecoration(
                  labelText: OrdersLabels.paymentAmountLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final raw = (value ?? '').replaceAll(',', '').trim();
                  if (raw.isEmpty) return null; // leave unchanged
                  final parsed = int.tryParse(raw);
                  if (parsed == null || parsed <= 0) {
                    return CashDrawerLabels.cashDrawerAmountLabel;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: OrdersLabels.notes,
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton(
          onPressed: () {
            final valid = formKey.currentState?.validate() ?? false;
            if (!valid) return;
            final rawAmount =
                amountCtrl.text.replaceAll(',', '').trim();
            // Only send the amount when it changed; an unchanged amount is
            // omitted from the PATCH body so the backend leaves the journal
            // lines untouched.
            final newAmount = rawAmount.isEmpty || rawAmount == '$currentAmount'
                ? null
                : int.tryParse(rawAmount);
            // Determine whether notes changed. An empty-field-with-content
            // delta is sent as the new value (including empty string when
            // cleared). When unchanged, send null to leave the description.
            final newNotes = noteCtrl.text == currentNotes ? null : noteCtrl.text;
            Navigator.of(context).pop(
              CashDrawerEditResult(amount: newAmount, notes: newNotes),
            );
          },
          child: const Text(SharedLabels.save),
        ),
      ],
    ),
  );
}

/// Formats an integer with thousand-separator commas: `1500000` → `1,500,000`.
String _formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  final len = digits.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats numeric input with thousand-separator commas while typing.
/// Mirrors the private formatter in `cash_drawer_action_dialogs.dart` so the
/// edit dialog stays self-contained (the original is private to that file).
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const _ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final digits = text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    final buffer = StringBuffer();
    final len = digits.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}