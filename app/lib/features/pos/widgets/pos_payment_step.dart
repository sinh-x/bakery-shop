import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/labels/orders.dart';
import '../../../shared/utils/vnd_units.dart';
import '../../../shared/widgets/target_account_dropdown.dart';

/// Dedicated POS payment step shown AFTER the Stage 4 review (DG-218 Phase 4,
/// FR-5). Presents the cash/transfer method selection, an editable amount field
/// (B3), and the submit action that finalizes the order.
///
/// The transfer-photo path (`showTransferSourceDialog` + `uploadOrderPhoto`) is
/// preserved by the caller's [onSubmit] handler — this widget only captures the
/// selected method and amount.
///
/// This widget is intentionally review-only with respect to order data: it
/// does not read or mutate the cart/wizard state.
class PosPaymentStep extends ConsumerStatefulWidget {
  const PosPaymentStep({
    super.key,
    required this.orderTotal,
    required this.initialAmount,
    required this.hasTienRut,
    required this.tienRutAmount,
    required this.selectedPaymentMethod,
    required this.isProcessing,
    required this.onPaymentMethodChanged,
    required this.onAmountChanged,
    required this.onTienRutAmountChanged,
    required this.onBack,
    required this.onSubmit,
    this.selectedTargetAccount,
    this.onTargetAccountChanged,
  });

  final double orderTotal;
  final double initialAmount;
  final bool hasTienRut;
  final double tienRutAmount;
  final String selectedPaymentMethod;
  final bool isProcessing;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<double> onAmountChanged;
  final ValueChanged<double> onTienRutAmountChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  /// Optional target bank account for transfer payments (DG-244 Phase 2,
  /// FR7). `null` means no selection. Only shown when the method is
  /// `transfer`.
  final String? selectedTargetAccount;
  final ValueChanged<String?>? onTargetAccountChanged;

  @override
  ConsumerState<PosPaymentStep> createState() => _PosPaymentStepState();
}

class _PosPaymentStepState extends ConsumerState<PosPaymentStep> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _tienRutCtrl;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: vndThousandsTextFromAmount(widget.initialAmount),
    );
    _amountCtrl.addListener(_onAmountTextChanged);
    _tienRutCtrl = TextEditingController(
      text: widget.hasTienRut
          ? vndThousandsTextFromAmount(widget.tienRutAmount)
          : '',
    );
    _tienRutCtrl.addListener(_onTienRutTextChanged);
  }

  @override
  void didUpdateWidget(PosPaymentStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAmount != widget.initialAmount &&
        _amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '').isEmpty) {
      _amountCtrl.text = vndThousandsTextFromAmount(widget.initialAmount);
    }
    if (oldWidget.tienRutAmount != widget.tienRutAmount &&
        widget.hasTienRut &&
        _tienRutCtrl.text.replaceAll(RegExp(r'[^\d]'), '').isEmpty) {
      _tienRutCtrl.text = vndThousandsTextFromAmount(widget.tienRutAmount);
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountTextChanged);
    _amountCtrl.dispose();
    _tienRutCtrl.removeListener(_onTienRutTextChanged);
    _tienRutCtrl.dispose();
    super.dispose();
  }

  void _onAmountTextChanged() {
    final raw = _amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final parsed = double.tryParse(raw);
    if (parsed != null) {
      widget.onAmountChanged(vndFromThousands(parsed));
    }
    setState(() {});
  }

  void _onTienRutTextChanged() {
    final raw = _tienRutCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final parsed = double.tryParse(raw);
    if (parsed != null) {
      widget.onTienRutAmountChanged(vndFromThousands(parsed));
    }
    setState(() {});
  }

  void _onAmountFocusLost() {
    final raw = _amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final parsed = double.tryParse(raw);
    if (parsed != null && parsed > 0) {
      _amountCtrl.text = vndThousandsTextFromAmount(vndFromThousands(parsed));
    } else {
      _amountCtrl.text = vndThousandsTextFromAmount(widget.orderTotal);
      widget.onAmountChanged(widget.orderTotal);
    }
  }

  void _onTienRutFocusLost() {
    final raw = _tienRutCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final parsed = double.tryParse(raw);
    if (parsed != null && parsed > 0) {
      _tienRutCtrl.text =
          vndThousandsTextFromAmount(vndFromThousands(parsed));
    }
  }

  void _clearAmountField() {
    _amountCtrl.clear();
    widget.onAmountChanged(0);
  }

  void _clearTienRutField() {
    _tienRutCtrl.clear();
    widget.onTienRutAmountChanged(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  VN.selectPaymentMethod,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  OrdersLabels.checkoutReviewHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  VN.paymentAmount,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    suffixText: ',000đ',
                    helperText: VN.paymentThousandsHint,
                    suffixIcon: _amountCtrl.text
                            .replaceAll(RegExp(r'[^\d]'), '')
                            .isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: VN.clear,
                            onPressed: _clearAmountField,
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  onTap: () {
                    final raw = _amountCtrl.text
                        .replaceAll(RegExp(r'[^\d]'), '');
                    _amountCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: raw.length,
                    );
                  },
                  onEditingComplete: _onAmountFocusLost,
                  onSubmitted: (_) => _onAmountFocusLost(),
                ),
                if (widget.hasTienRut) ...[
                  const SizedBox(height: 16),
                  Text(
                    VN.soTienRut,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _tienRutCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      suffixText: ',000đ',
                      helperText: VN.paymentThousandsHint,
                      suffixIcon: _tienRutCtrl.text
                              .replaceAll(RegExp(r'[^\d]'), '')
                              .isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: VN.clear,
                              onPressed: _clearTienRutField,
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    onTap: () {
                      final raw = _tienRutCtrl.text
                          .replaceAll(RegExp(r'[^\d]'), '');
                      _tienRutCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: raw.length,
                      );
                    },
                    onEditingComplete: _onTienRutFocusLost,
                    onSubmitted: (_) => _onTienRutFocusLost(),
                  ),
                ],
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'cash',
                      label: Text(VN.tienMat),
                      icon: Icon(Icons.money),
                    ),
                    ButtonSegment(
                      value: 'transfer',
                      label: Text(VN.chuyenKhoan),
                      icon: Icon(Icons.qr_code),
                    ),
                  ],
                  selected: {widget.selectedPaymentMethod},
                  onSelectionChanged: (s) =>
                      widget.onPaymentMethodChanged(s.first),
                  showSelectedIcon: false,
                  multiSelectionEnabled: false,
                ),
                if (widget.selectedPaymentMethod == 'transfer') ...[
                  const SizedBox(height: 16),
                  TargetAccountDropdown(
                    value: widget.selectedTargetAccount,
                    onChanged: widget.onTargetAccountChanged,
                  ),
                ],
              ],
            ),
          ),
        ),
        _buildNavigation(theme),
      ],
    );
  }

  Widget _buildNavigation(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: widget.onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: widget.isProcessing ? null : widget.onSubmit,
            child: widget.isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(VN.submitOrder),
          ),
        ],
      ),
    );
  }
}
