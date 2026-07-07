import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/pos_provider.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/utils/order_helpers.dart';
import '../../orders/widgets/order_wizard.dart';
import '../../orders/widgets/section_header.dart';
import 'pos_checkout_cart_item_tile.dart';

class PosReviewPanel extends ConsumerWidget {
  const PosReviewPanel({
    super.key,
    required this.wizardData,
    required this.selectedPaymentMethod,
    required this.isProcessing,
    required this.onPaymentMethodChanged,
    required this.onBack,
    required this.onSubmit,
  });

  final OrderWizardData wizardData;
  final String selectedPaymentMethod;
  final bool isProcessing;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(posCartProvider);
    final theme = Theme.of(context);
    final data = wizardData;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OrdersLabels.checkoutReviewTitle,
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
                const SectionHeader(OrdersLabels.stage2Label),
                _buildReviewRow(
                  theme,
                  VN.customerName,
                  data.customerName.isNotEmpty ? data.customerName : '—',
                ),
                if (data.customerPhone.isNotEmpty)
                  _buildReviewRow(theme, VN.customerPhone, data.customerPhone),
                const SizedBox(height: 16),
                const SectionHeader(OrdersLabels.stage3Label),
                _buildReviewRow(
                  theme,
                  VN.deliveryType,
                  deliveryTypeLabel(data.deliveryType),
                ),
                if (data.needsAddress) ...[
                  if (data.deliveryPhone.isNotEmpty)
                    _buildReviewRow(
                      theme,
                      OrdersLabels.deliveryPhone,
                      data.deliveryPhone,
                    ),
                  if (data.deliveryAddress.isNotEmpty)
                    _buildReviewRow(theme, VN.deliveryAddress, data.deliveryAddress),
                ],
                const SizedBox(height: 16),
                const SectionHeader(VN.products),
                ...cart.items.map(
                  (item) => PosCheckoutCartItemTile(item: item),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${VN.total}: ', style: theme.textTheme.bodyMedium),
                    Text(
                      formatVND(cart.total),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionHeader(VN.paymentMethod),
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

  Widget _buildReviewRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
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