import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';

/// Dedicated POS payment step shown AFTER the Stage 4 review (DG-218 Phase 4,
/// FR-5). Presents the cash/transfer method selection and the submit action
/// that finalizes the order. The transfer-photo path
/// (`showTransferSourceDialog` + `uploadOrderPhoto`) is preserved by the
/// caller's [onSubmit] handler — this widget only captures the selected method.
///
/// This widget is intentionally review-only with respect to order data: it
/// does not read or mutate the cart/wizard state. It reports the selected
/// payment method up via [onPaymentMethodChanged] and triggers [onSubmit] when
/// the user taps the finalize button.
class PosPaymentStep extends StatelessWidget {
  const PosPaymentStep({
    super.key,
    required this.selectedPaymentMethod,
    required this.isProcessing,
    required this.onPaymentMethodChanged,
    required this.onBack,
    required this.onSubmit,
  });

  /// Currently selected payment method: `'cash'` or `'transfer'`.
  final String selectedPaymentMethod;

  /// Whether the order is being created. Disables the submit button and shows
  /// a spinner when true.
  final bool isProcessing;

  /// Called with the new method when the user changes the selection.
  final ValueChanged<String> onPaymentMethodChanged;

  /// Called when the user taps the back button (returns to the review step).
  final VoidCallback onBack;

  /// Called when the user taps the finalize button. The caller decides
  /// whether to invoke `_createOrder` (cash) or `_handleTransfer` (transfer),
  /// preserving the existing transfer-photo path.
  final VoidCallback onSubmit;

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
                const SizedBox(height: 8),
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
                  selected: {selectedPaymentMethod},
                  onSelectionChanged: (s) => onPaymentMethodChanged(s.first),
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
            onPressed: onBack,
            child: const Text(OrdersLabels.backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: isProcessing ? null : onSubmit,
            child: isProcessing
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