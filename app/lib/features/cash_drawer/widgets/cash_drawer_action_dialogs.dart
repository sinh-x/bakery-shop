import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Result returned by the cash-drawer dialogs.
///
/// `null` means the user cancelled. A non-null value carries the entered
/// amount (VND integer), optional note, and (for cash-in/cash-out) the
/// selected source/destination and staff member so the caller can invoke the
/// matching `CashDrawerService` method.
class CashDrawerDialogResult {
  const CashDrawerDialogResult({
    required this.amount,
    this.note = '',
    this.source,
    this.destination,
    this.staffName,
  });

  final int amount;
  final String note;

  /// Cash-in source: 'owner' | 'employee' | 'equity'. Null for non-cash-in
  /// dialogs.
  final String? source;

  /// Cash-out destination: 'owner' | 'employee'. Null for non-cash-out
  /// dialogs.
  final String? destination;

  /// Selected staff member name (required when source/destination ==
  /// 'employee').
  final String? staffName;
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
/// amount or `null` when cancelled. When [referenceBalance] is provided,
/// it is displayed as the 1101 accounting reference at any value (negative,
/// zero, or positive) — DG-360 Phase 2 removed the old `> 0` guard so the
/// owner can reconcile against an over-drawn 1101 balance too. When
/// [previousCloseCountedAmount] is provided (non-null), it is displayed as
/// "Số dư sau khi đóng quầy lần trước" (DG-331 FR9 / AC8).
///
/// Phase 4.1 F3: [referenceBalance] is shown upfront (before any 409
/// proposal) so the owner can reconcile against the 1101 journal balance
/// immediately, not only after a surplus/shortage proposal.
Future<CashDrawerDialogResult?> showOpenDrawerDialog(
  BuildContext context, {
  int referenceBalance = 0,
  int? previousCloseCountedAmount,
}) {
  final helpers = <String>[
    '${VN.cashDrawerReferenceBalance}: ${formatVND(referenceBalance.toDouble())}',
  ];
  if (previousCloseCountedAmount != null) {
    helpers.add(
      '${VN.cashDrawerPreviousCloseBalance}: '
      '${formatVND(previousCloseCountedAmount.toDouble())}',
    );
  }
  return _showAmountDialog(
    context: context,
    title: VN.cashDrawerOpen,
    amountLabel: VN.cashDrawerOpeningBalance,
    confirmLabel: VN.cashDrawerOpen,
    allowZero: false,
    helper: helpers.join('\n'),
  );
}

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

/// DG-330: shows the transfer confirmation dialog when the opening balance
/// is lower than the 1101 reference balance. The excess MUST transfer to
/// 1102 (owner's cash) — declining is not permitted because the drawer
/// cannot open with an unexplained shortfall. Returns [TransferDecision.accept]
/// or `null` (cancel → consult Kế toán).
enum TransferDecision { accept }

Future<TransferDecision?> showTransferConfirmationDialog(
  BuildContext context, {
  required int referenceBalance,
  required int openingBalance,
  required int excess,
}) async {
  return showDialog<TransferDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(VN.cashDrawerTransferTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Số dư kế toán 1101: ${formatVND(referenceBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text('Số tiền mở quầy: ${formatVND(openingBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text(
            'Chênh lệch thiếu: ${formatVND(excess.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(VN.cashDrawerTransferQuestion),
          const SizedBox(height: 8),
          Text(
            VN.cashDrawerTransferDeclineBlocked,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(TransferDecision.accept),
          icon: const Icon(Icons.east),
          label: const Text(VN.cashDrawerTransferAccept),
        ),
      ],
    ),
  );
}

/// DG-330: shows the stock reconciliation confirmation dialog when the
/// opening balance exceeds the 1101 reference.
enum StockReconDecision { accept, decline, ownerCapital }

Future<StockReconDecision?> showStockReconciliationDialog(
  BuildContext context, {
  required int referenceBalance,
  required int openingBalance,
  required int excess,
}) async {
  return showDialog<StockReconDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(VN.cashDrawerStockReconTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Số dư kế toán 1101: ${formatVND(referenceBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text('Số tiền mở quầy: ${formatVND(openingBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text(
            'Chênh lệch thừa: ${formatVND(excess.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(VN.cashDrawerStockReconQuestion),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(StockReconDecision.ownerCapital),
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text(VN.cashDrawerExcessOwnerCapital),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(StockReconDecision.accept),
          icon: const Icon(Icons.check),
          label: const Text(VN.cashDrawerStockReconAccept),
        ),
      ],
    ),
  );
}

/// DG-330: asks whether the excess should be recorded as an unidentified
/// sale with 50% COGS markup.
enum UnidentifiedSaleDecision { accept, decline }

Future<UnidentifiedSaleDecision?> showUnidentifiedSaleDialog(
  BuildContext context, {
  required int excess,
}) async {
  return showDialog<UnidentifiedSaleDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(VN.cashDrawerUnidentifiedSaleTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chênh lệch: ${formatVND(excess.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(VN.cashDrawerUnidentifiedSaleQuestion),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(UnidentifiedSaleDecision.decline),
          icon: const Icon(Icons.block),
          label: const Text(VN.cashDrawerUnidentifiedSaleDecline),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(UnidentifiedSaleDecision.accept),
          icon: const Icon(Icons.check),
          label: const Text(VN.cashDrawerUnidentifiedSaleAccept),
        ),
      ],
    ),
  );
}

/// DG-331: decision returned by [showCloseSurplusDialog]. Maps to the
/// `surplusSource` value sent back to the backend on the confirmed close.
/// `null` means the user cancelled the confirmation (treat as abort close).
enum CloseSurplusDecision { ownerCash, unidentifiedSale }

/// DG-331 AC9: shows the close surplus confirmation dialog when the backend
/// reports that the counted amount exceeds the expected balance. Asks the
/// owner to choose the nature of the surplus:
///   - [CloseSurplusDecision.ownerCash] → DR 1101/CR 1102 (owner put cash in)
///   - [CloseSurplusDecision.unidentifiedSale] → DR 1101/CR 4100 +
///     DR 5900/CR 1300 (50% COGS)
/// Returns `null` when the user cancels (the close flow is aborted).
Future<CloseSurplusDecision?> showCloseSurplusDialog(
  BuildContext context, {
  required int expectedBalance,
  required int countedAmount,
  required int surplus,
}) async {
  return showDialog<CloseSurplusDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(VN.cashDrawerCloseSurplusTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Số dư dự kiến: ${formatVND(expectedBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text('Số tiền đếm được: ${formatVND(countedAmount.toDouble())}'),
          const SizedBox(height: 4),
          Text(
            'Chênh lệch thừa: ${formatVND(surplus.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(VN.cashDrawerCloseSurplusQuestion),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(CloseSurplusDecision.unidentifiedSale),
          icon: const Icon(Icons.receipt_long),
          label: const Text(VN.cashDrawerCloseSurplusUnidentifiedSale),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(CloseSurplusDecision.ownerCash),
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text(VN.cashDrawerCloseSurplusOwnerCash),
        ),
      ],
    ),
  );
}

/// DG-331: decision returned by [showCloseShortageDialog]. Maps to the
/// `shortageSource` value sent back to the backend on the confirmed close.
/// `null` means the user cancelled the confirmation (treat as abort close).
enum CloseShortageDecision { ownerWithdraw, equityLoss }

/// DG-331 AC9: shows the close shortage confirmation dialog when the backend
/// reports that the counted amount is below the expected balance. Asks the
/// owner to choose the nature of the shortage:
///   - [CloseShortageDecision.ownerWithdraw] → DR 1102/CR 1101 (owner took
///     cash)
///   - [CloseShortageDecision.equityLoss] → DR 3100/CR 1101 (equity loss)
/// Returns `null` when the user cancels (the close flow is aborted).
Future<CloseShortageDecision?> showCloseShortageDialog(
  BuildContext context, {
  required int expectedBalance,
  required int countedAmount,
  required int shortage,
}) async {
  return showDialog<CloseShortageDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(VN.cashDrawerCloseShortageTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Số dư dự kiến: ${formatVND(expectedBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text('Số tiền đếm được: ${formatVND(countedAmount.toDouble())}'),
          const SizedBox(height: 4),
          Text(
            'Chênh lệch thiếu: ${formatVND(shortage.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(VN.cashDrawerCloseShortageQuestion),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(CloseShortageDecision.equityLoss),
          icon: const Icon(Icons.trending_down),
          label: const Text(VN.cashDrawerCloseShortageEquityLoss),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(CloseShortageDecision.ownerWithdraw),
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text(VN.cashDrawerCloseShortageOwnerWithdraw),
        ),
      ],
    ),
  );
}

/// Shows the cash-in dialog (FR2 / FR3a / AC15).
///
/// `staff` is the active staff list used to populate the per-staff picker when
/// the user selects the `employee` source. Pass an empty list when no staff
/// are configured (the employee option remains selectable but the picker will
/// be empty).
///
/// Phase 4.1 F5: [expectedBalance] is shown as "Số dư hiện tại" helper text so
/// the owner knows how much is already in the drawer before adding more.
Future<CashDrawerDialogResult?> showCashInDialog(
  BuildContext context, {
  List<StaffMember> staff = const <StaffMember>[],
  int expectedBalance = 0,
}) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerCashIn,
      amountLabel: VN.cashDrawerAmountLabel,
      confirmLabel: VN.xacNhan,
      allowZero: false,
      helper: expectedBalance > 0
          ? '${VN.cashDrawerCurrentBalance}: ${formatVND(expectedBalance.toDouble())}'
          : null,
      selector: _CashDrawerSelector.cashIn(staff),
    );

/// Shows the cash-out dialog (FR3 / FR4 / FR13 / AC15).
///
/// `staff` is the active staff list used to populate the per-staff picker when
/// the user selects the `employee` destination.
///
/// Phase 4.1 F6: [expectedBalance] is shown as "Số dư hiện tại" helper text so
/// the owner knows how much they can withdraw.
Future<CashDrawerDialogResult?> showCashOutDialog(
  BuildContext context, {
  List<StaffMember> staff = const <StaffMember>[],
  int expectedBalance = 0,
}) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerCashOut,
      amountLabel: VN.cashDrawerAmountLabel,
      confirmLabel: VN.xacNhan,
      allowZero: false,
      helper: expectedBalance > 0
          ? '${VN.cashDrawerCurrentBalance}: ${formatVND(expectedBalance.toDouble())}'
          : null,
      selector: _CashDrawerSelector.cashOut(staff),
    );

/// Shows the close-drawer dialog (FR7 / AC7).
///
/// Displays the current expected balance so the owner can compare against
/// the counted amount; the discrepancy is computed by the backend on close.
///
/// Phase 4.1 F4: [accountingBalance1101] is shown below the expected balance
/// line as "Số dư kế toán 1101" for reconciliation reference.
Future<CashDrawerDialogResult?> showCloseDrawerDialog(
  BuildContext context, {
  required int expectedBalance,
  int accountingBalance1101 = 0,
}) {
  final helpers = <String>[
    '${VN.cashDrawerExpectedBalance}: ${formatVND(expectedBalance.toDouble())}',
  ];
  if (accountingBalance1101 > 0) {
    helpers.add(
      '${VN.cashDrawerReferenceBalance}: ${formatVND(accountingBalance1101.toDouble())}',
    );
  }
  return _showAmountDialog(
    context: context,
    title: VN.cashDrawerClose,
    amountLabel: VN.cashDrawerCountedAmount,
    confirmLabel: VN.cashDrawerClose,
    allowZero: true,
    helper: helpers.join('\n'),
  );
}

Future<CashDrawerDialogResult?> _showAmountDialog({
  required BuildContext context,
  required String title,
  required String amountLabel,
  required String confirmLabel,
  required bool allowZero,
  String? helper,
  _CashDrawerSelector? selector,
}) async {
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<CashDrawerDialogResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
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
                  inputFormatters: [
                    _ThousandsSeparatorInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: amountLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final raw = (value ?? '').replaceAll(',', '').trim();
                    final parsed = int.tryParse(raw);
                    if (parsed == null) return VN.cashDrawerAmountLabel;
                    if (!allowZero && parsed <= 0) {
                      return VN.cashDrawerAmountLabel;
                    }
                    if (parsed < 0) return VN.cashDrawerAmountLabel;
                    return null;
                  },
                ),
                if (selector != null) ...[
                  const SizedBox(height: 12),
                  selector.build(context, setState),
                ],
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () {
              final formValid = formKey.currentState?.validate() ?? false;
              final selectorValid = selector?.validate() ?? true;
              if (formValid && selectorValid) {
                Navigator.of(context).pop(
                  CashDrawerDialogResult(
                    amount: int.parse(amountCtrl.text.replaceAll(',', '').trim()),
                    note: noteCtrl.text.trim(),
                    source: selector?.sourceValue,
                    destination: selector?.destinationValue,
                    staffName: selector?.selectedStaffName,
                  ),
                );
              } else if (!selectorValid) {
                // Force the staff-picker error to render.
                setState(() {});
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );

  return result;
}

/// Encapsulates the source/destination dropdown + conditional staff picker
/// shared by the cash-in and cash-out dialogs (DG-330 Phase 8).
class _CashDrawerSelector {
  _CashDrawerSelector._({
    required this._mode,
    required this._staff,
    required this._options,
    required this._headerLabel,
    required this._selectedValue,
  });

  factory _CashDrawerSelector.cashIn(List<StaffMember> staff) =>
      _CashDrawerSelector._(
        mode: _SelectorMode.cashIn,
        staff: staff,
        options: const [
          (value: 'owner', label: VN.cashDrawerSourceOwner),
          (value: 'employee', label: VN.cashDrawerSourceEmployee),
          (value: 'equity', label: VN.cashDrawerSourceEquity),
        ],
        headerLabel: VN.cashDrawerSourceLabel,
        selectedValue: 'owner',
      );

  factory _CashDrawerSelector.cashOut(List<StaffMember> staff) =>
      _CashDrawerSelector._(
        mode: _SelectorMode.cashOut,
        staff: staff,
        options: const [
          (value: 'owner', label: VN.cashDrawerDestinationOwner),
          (value: 'employee', label: VN.cashDrawerDestinationEmployee),
        ],
        headerLabel: VN.cashDrawerDestinationLabel,
        selectedValue: 'owner',
      );

  final _SelectorMode _mode;
  final List<StaffMember> _staff;
  final List<({String value, String label})> _options;
  final String _headerLabel;

  String _selectedValue;
  String? _selectedStaffName;

  String? get sourceValue =>
      _mode == _SelectorMode.cashIn ? _selectedValue : null;

  String? get destinationValue =>
      _mode == _SelectorMode.cashOut ? _selectedValue : null;

  String? get selectedStaffName =>
      _selectedValue == 'employee' ? _selectedStaffName : null;

  bool _needsStaffPicker() => _selectedValue == 'employee';

  /// Returns true when the employee option is chosen but no staff member is
  /// selected.
  bool validate() {
    if (_needsStaffPicker()) {
      return _selectedStaffName != null && _selectedStaffName!.isNotEmpty;
    }
    return true;
  }

  Widget build(BuildContext context, StateSetter setState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _headerLabel,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _selectedValue,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final opt in _options)
              DropdownMenuItem(value: opt.value, child: Text(opt.label)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedValue = value;
              _selectedStaffName = null;
            });
          },
        ),
        if (_needsStaffPicker()) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedStaffName,
            decoration: const InputDecoration(
              labelText: VN.cashDrawerStaffPickerLabel,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final member in _staff)
                DropdownMenuItem(
                  value: member.name,
                  child: Text(member.name),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedStaffName = value;
              });
            },
            validator: (_) {
              if (!_needsStaffPicker()) return null;
              if (_selectedStaffName == null ||
                  _selectedStaffName!.isEmpty) {
                return VN.cashDrawerStaffRequired;
              }
              return null;
            },
          ),
        ],
      ],
    );
  }
}

enum _SelectorMode { cashIn, cashOut }

/// Formats numeric input with thousand-separator commas while typing.
/// Only allows digits — the formatter inserts commas at thousand positions.
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final digits = text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    final formatted = _addCommas(digits);
    final offset = formatted.length;
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  String _addCommas(String digits) {
    final buffer = StringBuffer();
    final len = digits.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}