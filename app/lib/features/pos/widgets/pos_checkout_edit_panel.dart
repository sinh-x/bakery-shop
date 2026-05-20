import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

class PosCheckoutEditPanel extends StatelessWidget {
  const PosCheckoutEditPanel({
    super.key,
    required this.total,
    required this.selectedPaymentMethod,
    required this.isProcessing,
    required this.onPaymentMethodChanged,
    required this.onOpenReview,
  });

  final double total;
  final String selectedPaymentMethod;
  final bool isProcessing;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(VN.total, style: theme.textTheme.titleLarge),
                Text(
                  formatVND(total),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Semantics(
              label: VN.selectPaymentMethod,
              child: SegmentedButton<String>(
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
                onSelectionChanged: (selection) =>
                    onPaymentMethodChanged(selection.first),
                showSelectedIcon: true,
                multiSelectionEnabled: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      );
                    }
                    return BorderSide(color: theme.colorScheme.outline);
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Tooltip(
                message: VN.confirmCounterPayment,
                child: FilledButton.icon(
                  onPressed: isProcessing ? null : onOpenReview,
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text(VN.thanhToan),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
