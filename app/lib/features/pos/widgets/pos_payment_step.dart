import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/labels/orders.dart';

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
    required this.selectedPaymentMethod,
    required this.isProcessing,
    required this.onPaymentMethodChanged,
    required this.onAmountChanged,
    required this.onBack,
    required this.onSubmit,
  });

  final double orderTotal;
  final String selectedPaymentMethod;
  final bool isProcessing;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<double> onAmountChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  ConsumerState<PosPaymentStep> createState() => _PosPaymentStepState();
}

class _PosPaymentStepState extends ConsumerState<PosPaymentStep> {
  late final TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: formatVND(widget.orderTotal),
    );
    _amountCtrl.addListener(_onAmountTextChanged);
  }

  @override
  void didUpdateWidget(PosPaymentStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderTotal != widget.orderTotal &&
        !_amountCtrl.text.contains(RegExp(r'[1-9]'))) {
      _amountCtrl.text = formatVND(widget.orderTotal);
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountTextChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  void _onAmountTextChanged() {
    final raw = _amountCtrl.text
        .replaceAll(RegExp(r'[^\d]'), '');
    final parsed = double.tryParse(raw);
    if (parsed != null) {
      widget.onAmountChanged(parsed);
    }
  }

  void _onAmountFocusLost() {
    final raw = _amountCtrl.text
        .replaceAll(RegExp(r'[^\d]'), '');
    final parsed = double.tryParse(raw);
    if (parsed != null && parsed > 0) {
      final clamped = parsed > widget.orderTotal
          ? widget.orderTotal
          : parsed;
      _amountCtrl.text = formatVND(clamped);
      widget.onAmountChanged(clamped);
    } else {
      _amountCtrl.text = formatVND(widget.orderTotal);
      widget.onAmountChanged(widget.orderTotal);
    }
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
                  decoration: const InputDecoration(
                    suffixText: VN.currency,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
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
