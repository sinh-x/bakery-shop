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

/// FR9 carry-over confirmation outcome returned by
/// [showCarryOverConfirmationDialog].
///
/// `null` means the user dismissed the dialog without a decision (treat as
/// cancel). Otherwise the caller should re-invoke `openDrawer` with the
/// matching `carryOverConfirmed` flag.
enum CarryOverDecision { accept, decline }

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

/// FR9: shows the carry-over proposal confirmation dialog when the backend
/// reports that the previous day's drawer is still open.
///
/// Surfaces the proposed carry-over amount (VND, formatted) and asks the
/// owner whether to carry it into today's opening balance. Returns:
///   - [CarryOverDecision.accept] → re-call `openDrawer` with
///     `carryOverConfirmed: true`.
///   - [CarryOverDecision.decline] → re-call `openDrawer` with
///     `carryOverConfirmed: false` (opens today without carrying over).
///   - `null` → the user dismissed the dialog (cancel the whole open flow).
Future<CarryOverDecision?> showCarryOverConfirmationDialog(
  BuildContext context, {
  required int carryOverAmount,
}) async {
  return showDialog<CarryOverDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(VN.cashDrawerCarryOverTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(VN.cashDrawerCarryOverPrompt),
          const SizedBox(height: 4),
          Text(
            formatVND(carryOverAmount.toDouble()),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(VN.cashDrawerCarryOverQuestion),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(CarryOverDecision.decline),
          icon: const Icon(Icons.block),
          label: const Text(VN.cashDrawerCarryOverDecline),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(CarryOverDecision.accept),
          icon: const Icon(Icons.east),
          label: const Text(VN.cashDrawerCarryOverAccept),
        ),
      ],
    ),
  );
}

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

  return result;
}