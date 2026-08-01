import 'package:flutter/material.dart';

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

/// Shows the cash-in dialog (FR2 / FR3a / AC15).
///
/// `staff` is the active staff list used to populate the per-staff picker when
/// the user selects the `employee` source. Pass an empty list when no staff
/// are configured (the employee option remains selectable but the picker will
/// be empty).
Future<CashDrawerDialogResult?> showCashInDialog(
  BuildContext context, {
  List<StaffMember> staff = const <StaffMember>[],
}) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerCashIn,
      amountLabel: VN.cashDrawerAmountLabel,
      confirmLabel: VN.xacNhan,
      allowZero: false,
      selector: _CashDrawerSelector.cashIn(staff),
    );

/// Shows the cash-out dialog (FR3 / FR4 / FR13 / AC15).
///
/// `staff` is the active staff list used to populate the per-staff picker when
/// the user selects the `employee` destination.
Future<CashDrawerDialogResult?> showCashOutDialog(
  BuildContext context, {
  List<StaffMember> staff = const <StaffMember>[],
}) =>
    _showAmountDialog(
      context: context,
      title: VN.cashDrawerCashOut,
      amountLabel: VN.cashDrawerAmountLabel,
      confirmLabel: VN.xacNhan,
      allowZero: false,
      selector: _CashDrawerSelector.cashOut(staff),
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
                  decoration: InputDecoration(
                    labelText: amountLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
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
                    amount: int.parse(amountCtrl.text.trim()),
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
        selectedValue: 'equity',
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