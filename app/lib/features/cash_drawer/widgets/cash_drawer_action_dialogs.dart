import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../providers/cash_drawer_selector_notifier.dart';
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
  BuildContext context,
  WidgetRef ref, {
  int referenceBalance = 0,
  int? previousCloseCountedAmount,
}) {
  final helpers = <String>[
    '${CashDrawerLabels.cashDrawerReferenceBalance}: ${formatVND(referenceBalance.toDouble())}',
  ];
  if (previousCloseCountedAmount != null) {
    helpers.add(
      '${CashDrawerLabels.cashDrawerPreviousCloseBalance}: '
      '${formatVND(previousCloseCountedAmount.toDouble())}',
    );
  }
  return _showAmountDialog(
    context: context,
    ref: ref,
    title: CashDrawerLabels.cashDrawerOpen,
    amountLabel: CashDrawerLabels.cashDrawerOpeningBalance,
    confirmLabel: CashDrawerLabels.cashDrawerOpen,
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
      title: const Text(CashDrawerLabels.cashDrawerCarryOverTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(CashDrawerLabels.cashDrawerCarryOverPrompt),
          const SizedBox(height: 4),
          Text(
            formatVND(carryOverAmount.toDouble()),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          const Text(CashDrawerLabels.cashDrawerCarryOverQuestion),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(CarryOverDecision.decline),
          icon: const Icon(Icons.block),
          label: const Text(CashDrawerLabels.cashDrawerCarryOverDecline),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(CarryOverDecision.accept),
          icon: const Icon(Icons.east),
          label: const Text(CashDrawerLabels.cashDrawerCarryOverAccept),
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
///
/// DG-360 CQ-6: the open flow reuses this dialog (via the dual-use
/// [CloseSurplusProposalException]) but the close labels ("Số dư dự kiến" /
/// "Số tiền đếm được") are misleading in that context. Pass
/// `openFlow: true` to switch to the open-flow labels ("Số dư kế toán 1101"
/// / "Số tiền mở quầy") and the open-flow title/question.
Future<CloseSurplusDecision?> showCloseSurplusDialog(
  BuildContext context, {
  required int expectedBalance,
  required int countedAmount,
  required int surplus,
  bool openFlow = false,
}) async {
  final String title =
      openFlow ? CashDrawerLabels.cashDrawerOpenSurplusTitle : CashDrawerLabels.cashDrawerCloseSurplusTitle;
  final String referenceLabel = openFlow
      ? CashDrawerLabels.cashDrawerOpenSurplusReferenceLabel
      : 'Số dư dự kiến';
  final String openingLabel = openFlow
      ? CashDrawerLabels.cashDrawerOpenSurplusOpeningLabel
      : 'Số tiền đếm được';
  final String question = openFlow
      ? CashDrawerLabels.cashDrawerOpenSurplusQuestion
      : CashDrawerLabels.cashDrawerCloseSurplusQuestion;
  return showDialog<CloseSurplusDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$referenceLabel: ${formatVND(expectedBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text('$openingLabel: ${formatVND(countedAmount.toDouble())}'),
          const SizedBox(height: 4),
          Text(
            'Chênh lệch thừa: ${formatVND(surplus.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(question),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(CloseSurplusDecision.unidentifiedSale),
          icon: const Icon(Icons.receipt_long),
          label: const Text(CashDrawerLabels.cashDrawerCloseSurplusUnidentifiedSale),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(CloseSurplusDecision.ownerCash),
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text(CashDrawerLabels.cashDrawerCloseSurplusOwnerCash),
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
///
/// DG-360 CQ-6: the open flow reuses this dialog (via the dual-use
/// [CloseShortageProposalException]) but the close labels ("Số dư dự kiến"
/// / "Số tiền đếm được") are misleading in that context. Pass
/// `openFlow: true` to switch to the open-flow labels ("Số dư kế toán 1101"
/// / "Số tiền mở quầy") and the open-flow title/question.
Future<CloseShortageDecision?> showCloseShortageDialog(
  BuildContext context, {
  required int expectedBalance,
  required int countedAmount,
  required int shortage,
  bool openFlow = false,
}) async {
  final String title = openFlow
      ? CashDrawerLabels.cashDrawerOpenShortageTitle
      : CashDrawerLabels.cashDrawerCloseShortageTitle;
  final String referenceLabel = openFlow
      ? CashDrawerLabels.cashDrawerOpenShortageReferenceLabel
      : 'Số dư dự kiến';
  final String openingLabel = openFlow
      ? CashDrawerLabels.cashDrawerOpenShortageOpeningLabel
      : 'Số tiền đếm được';
  final String question = openFlow
      ? CashDrawerLabels.cashDrawerOpenShortageQuestion
      : CashDrawerLabels.cashDrawerCloseShortageQuestion;
  return showDialog<CloseShortageDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$referenceLabel: ${formatVND(expectedBalance.toDouble())}'),
          const SizedBox(height: 4),
          Text('$openingLabel: ${formatVND(countedAmount.toDouble())}'),
          const SizedBox(height: 4),
          Text(
            'Chênh lệch thiếu: ${formatVND(shortage.toDouble())}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Text(question),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () =>
              Navigator.of(context).pop(CloseShortageDecision.equityLoss),
          icon: const Icon(Icons.trending_down),
          label: const Text(CashDrawerLabels.cashDrawerCloseShortageEquityLoss),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(CloseShortageDecision.ownerWithdraw),
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text(CashDrawerLabels.cashDrawerCloseShortageOwnerWithdraw),
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
  BuildContext context,
  WidgetRef ref, {
  List<StaffMember> staff = const <StaffMember>[],
  int expectedBalance = 0,
}) =>
    _showAmountDialog(
      context: context,
      ref: ref,
      title: CashDrawerLabels.cashDrawerCashIn,
      amountLabel: CashDrawerLabels.cashDrawerAmountLabel,
      confirmLabel: OrdersLabels.xacNhan,
      allowZero: false,
      helper: expectedBalance > 0
          ? '${CashDrawerLabels.cashDrawerCurrentBalance}: ${formatVND(expectedBalance.toDouble())}'
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
  BuildContext context,
  WidgetRef ref, {
  List<StaffMember> staff = const <StaffMember>[],
  int expectedBalance = 0,
}) =>
    _showAmountDialog(
      context: context,
      ref: ref,
      title: CashDrawerLabels.cashDrawerCashOut,
      amountLabel: CashDrawerLabels.cashDrawerAmountLabel,
      confirmLabel: OrdersLabels.xacNhan,
      allowZero: false,
      helper: expectedBalance > 0
          ? '${CashDrawerLabels.cashDrawerCurrentBalance}: ${formatVND(expectedBalance.toDouble())}'
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
  BuildContext context,
  WidgetRef ref, {
  required int expectedBalance,
  int accountingBalance1101 = 0,
}) {
  final helpers = <String>[
    '${CashDrawerLabels.cashDrawerExpectedBalance}: ${formatVND(expectedBalance.toDouble())}',
  ];
  if (accountingBalance1101 != 0) {
    helpers.add(
      '${CashDrawerLabels.cashDrawerReferenceBalance}: ${formatVND(accountingBalance1101.toDouble())}',
    );
  }
  return _showAmountDialog(
    context: context,
    ref: ref,
    title: CashDrawerLabels.cashDrawerClose,
    amountLabel: CashDrawerLabels.cashDrawerCountedAmount,
    confirmLabel: CashDrawerLabels.cashDrawerClose,
    allowZero: true,
    helper: helpers.join('\n'),
  );
}

Future<CashDrawerDialogResult?> _showAmountDialog({
  required BuildContext context,
  required WidgetRef ref,
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

  // Seed the selector notifier's initial selected value (defaults to
  // 'owner' for both cash-in and cash-out).
  if (selector != null) {
    ref.read(cashDrawerSelectorProvider.notifier).setSelectedValue(
          selector.initialSelectedValue,
        );
  }

  final result = await showDialog<CashDrawerDialogResult>(
    context: context,
    builder: (context) => _AmountDialog(
      title: title,
      amountLabel: amountLabel,
      confirmLabel: confirmLabel,
      allowZero: allowZero,
      helper: helper,
      selector: selector,
      amountCtrl: amountCtrl,
      noteCtrl: noteCtrl,
      formKey: formKey,
    ),
  );

  return result;
}

/// Stateful dialog body that hosts the form + optional selector. Reads the
/// [cashDrawerSelectorProvider] for the source/destination + staff selection
/// (DG-404 Phase 4.7).
class _AmountDialog extends ConsumerStatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.amountLabel,
    required this.confirmLabel,
    required this.allowZero,
    required this.helper,
    required this.selector,
    required this.amountCtrl,
    required this.noteCtrl,
    required this.formKey,
  });

  final String title;
  final String amountLabel;
  final String confirmLabel;
  final bool allowZero;
  final String? helper;
  final _CashDrawerSelector? selector;
  final TextEditingController amountCtrl;
  final TextEditingController noteCtrl;
  final GlobalKey<FormState> formKey;

  @override
  ConsumerState<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends ConsumerState<_AmountDialog> {
  @override
  Widget build(BuildContext context) {
    final selectorState =
        widget.selector == null ? null : ref.watch(cashDrawerSelectorProvider);
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: widget.formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.helper != null) ...[
                Text(
                  widget.helper!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: widget.amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                inputFormatters: [
                  _ThousandsSeparatorInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: widget.amountLabel,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final raw = (value ?? '').replaceAll(',', '').trim();
                  final parsed = int.tryParse(raw);
                  if (parsed == null) return CashDrawerLabels.cashDrawerAmountLabel;
                  if (!widget.allowZero && parsed <= 0) {
                    return CashDrawerLabels.cashDrawerAmountLabel;
                  }
                  if (parsed < 0) return CashDrawerLabels.cashDrawerAmountLabel;
                  return null;
                },
              ),
              if (widget.selector != null && selectorState != null) ...[
                const SizedBox(height: 12),
                widget.selector!.build(context, ref, selectorState),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: widget.noteCtrl,
                decoration: const InputDecoration(
                  labelText: CashDrawerLabels.cashDrawerNoteLabel,
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
            final formValid = widget.formKey.currentState?.validate() ?? false;
            final selectorValid = widget.selector?.validate(ref) ?? true;
            if (formValid && selectorValid) {
              Navigator.of(context).pop(
                CashDrawerDialogResult(
                  amount: int.parse(
                      widget.amountCtrl.text.replaceAll(',', '').trim()),
                  note: widget.noteCtrl.text.trim(),
                  source: widget.selector?.sourceValue(ref),
                  destination: widget.selector?.destinationValue(ref),
                  staffName: widget.selector?.selectedStaffName(ref),
                ),
              );
            } else if (!selectorValid) {
              // Force the staff-picker error to render.
              ref.read(cashDrawerSelectorProvider.notifier).rebuild();
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Encapsulates the source/destination dropdown + conditional staff picker
/// shared by the cash-in and cash-out dialogs (DG-330 Phase 8).
///
/// DG-404 Phase 4.7: selection state (source/destination + staff name) is
/// owned by [cashDrawerSelectorProvider]; this class is now a stateless
/// config holder that reads the notifier state via `ref.watch` and writes
/// via `ref.read(provider.notifier).set*`.
class _CashDrawerSelector {
  _CashDrawerSelector._({
    required this._mode,
    required this._staff,
    required this._options,
    required this._headerLabel,
    required this._initialSelectedValue,
  });

  factory _CashDrawerSelector.cashIn(List<StaffMember> staff) =>
      _CashDrawerSelector._(
        mode: _SelectorMode.cashIn,
        staff: staff,
        options: const [
          (value: 'owner', label: CashDrawerLabels.cashDrawerSourceOwner),
          (value: 'employee', label: CashDrawerLabels.cashDrawerSourceEmployee),
          (value: 'equity', label: CashDrawerLabels.cashDrawerSourceEquity),
        ],
        headerLabel: CashDrawerLabels.cashDrawerSourceLabel,
        initialSelectedValue: 'owner',
      );

  factory _CashDrawerSelector.cashOut(List<StaffMember> staff) =>
      _CashDrawerSelector._(
        mode: _SelectorMode.cashOut,
        staff: staff,
        options: const [
          (value: 'owner', label: CashDrawerLabels.cashDrawerDestinationOwner),
          (value: 'employee', label: CashDrawerLabels.cashDrawerDestinationEmployee),
        ],
        headerLabel: CashDrawerLabels.cashDrawerDestinationLabel,
        initialSelectedValue: 'owner',
      );

  final _SelectorMode _mode;
  final List<StaffMember> _staff;
  final List<({String value, String label})> _options;
  final String _headerLabel;
  final String _initialSelectedValue;

  String get initialSelectedValue => _initialSelectedValue;

  String? sourceValue(WidgetRef ref) =>
      _mode == _SelectorMode.cashIn
          ? ref.read(cashDrawerSelectorProvider).selectedValue
          : null;

  String? destinationValue(WidgetRef ref) =>
      _mode == _SelectorMode.cashOut
          ? ref.read(cashDrawerSelectorProvider).selectedValue
          : null;

  String? selectedStaffName(WidgetRef ref) {
    final s = ref.read(cashDrawerSelectorProvider);
    return s.selectedValue == 'employee' ? s.selectedStaffName : null;
  }

  bool _needsStaffPicker(String selectedValue) => selectedValue == 'employee';

  /// Returns true when the employee option is chosen but no staff member is
  /// selected.
  bool validate(WidgetRef ref) {
    final s = ref.read(cashDrawerSelectorProvider);
    if (_needsStaffPicker(s.selectedValue)) {
      return s.selectedStaffName != null && s.selectedStaffName!.isNotEmpty;
    }
    return true;
  }

  Widget build(BuildContext context, WidgetRef ref, CashDrawerSelectorState state) {
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
          initialValue: state.selectedValue,
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
            ref.read(cashDrawerSelectorProvider.notifier).setSelectedValue(value);
          },
        ),
        if (_needsStaffPicker(state.selectedValue)) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: state.selectedStaffName,
            decoration: const InputDecoration(
              labelText: CashDrawerLabels.cashDrawerStaffPickerLabel,
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
              ref
                  .read(cashDrawerSelectorProvider.notifier)
                  .setSelectedStaffName(value);
            },
            validator: (_) {
              if (!_needsStaffPicker(state.selectedValue)) return null;
              if (state.selectedStaffName == null ||
                  state.selectedStaffName!.isEmpty) {
                return CashDrawerLabels.cashDrawerStaffRequired;
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