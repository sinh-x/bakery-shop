import 'package:flutter/material.dart';

import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Result returned by the cash-drawer dialogs.
///
/// `null` means the user cancelled. A non-null value carries the entered
/// amount (VND integer) and optional note so the caller can invoke the
/// matching `CashDrawerService` method.
class CashDrawerDialogResult {
  const CashDrawerDialogResult({required this.amount, this.note = ''});

  final int amount;
  final String note;
}

/// Shows the open-drawer dialog (FR1 / AC1).
///
/// Collects a starting balance and optional note. Returns the entered
/// amount or `null` when cancelled.
Future<CashDrawerDialogResult?> showOpenDrawerDialog(
  BuildContext context,
) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerOpen,
      amountLabel: VN.cashDrawerOpeningBalance,
      confirmLabel: VN.cashDrawerOpen,
      allowZero: false,
    );

/// Shows the cash-in dialog (FR2 / AC2).
Future<CashDrawerDialogResult?> showCashInDialog(BuildContext context) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerCashIn,
      amountLabel: VN.cashDrawerAmountLabel,
      confirmLabel: VN.xacNhan,
      allowZero: false,
    );

/// Shows the cash-out dialog (FR3 / AC3).
Future<CashDrawerDialogResult?> showCashOutDialog(BuildContext context) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerCashOut,
      amountLabel: VN.cashDrawerAmountLabel,
      confirmLabel: VN.xacNhan,
      allowZero: false,
    );

/// Shows the close-drawer dialog (FR7 / AC7).
///
/// Displays the current expected balance so the owner can compare against
/// the counted amount; the discrepancy is computed by the backend on close.
Future<CashDrawerDialogResult?> showCloseDrawerDialog(
  BuildContext context, {
  required int expectedBalance,
}) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerClose,
      amountLabel: VN.cashDrawerCountedAmount,
      confirmLabel: VN.cashDrawerClose,
      allowZero: true,
      helper:
          '${VN.cashDrawerExpectedBalance}: ${formatVND(expectedBalance.toDouble())}',
    );

Future<CashDrawerDialogResult?> _showAmountDialog({
  required BuildContext context,
  required String title,
  required String amountLabel,
  required String confirmLabel,
  required bool allowZero,
  String? helper,
}) async {
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<CashDrawerDialogResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (helper != null) ...[
              Text(
                helper,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              decoration: InputDecoration(
                labelText: amountLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final raw = value?.trim() ?? '';
                final parsed = int.tryParse(raw);
                if (parsed == null) return VN.cashDrawerAmountLabel;
                if (!allowZero && parsed <= 0) return VN.cashDrawerAmountLabel;
                if (parsed < 0) return VN.cashDrawerAmountLabel;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: VN.cashDrawerNoteLabel,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(
                CashDrawerDialogResult(
                  amount: int.parse(amountCtrl.text.trim()),
                  note: noteCtrl.text.trim(),
                ),
              );
            }
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  amountCtrl.dispose();
  noteCtrl.dispose();
  return result;
}