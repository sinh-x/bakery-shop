import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/order_create_state_provider.dart';
import 'section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class Stage4ReviewScreen extends ConsumerWidget {
  const Stage4ReviewScreen({
    super.key,
    required this.onBack,
    required this.onSubmit,
    this.isProcessing = false,
  });

  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final bool isProcessing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(orderCreateStateProvider);
    final data = state.wizardData;
    final theme = Theme.of(context);

    final regularItems = state.items.where((i) => !i.isExtra).toList();
    final extraItems = state.items.where((i) => i.isExtra).toList();
    final total = regularItems.fold<double>(
      0,
      (sum, i) => sum + i.unitPrice * i.quantity,
    );

    final dateStr = state.dueDate != null
        ? '${state.dueDate!.day}/${state.dueDate!.month}/${state.dueDate!.year}'
        : '—';
    final timeStr = state.dueTime != null
        ? '${state.dueTime!.hour.toString().padLeft(2, '0')}:${state.dueTime!.minute.toString().padLeft(2, '0')}'
        : '—';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OrdersLabels.reviewSummary,
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

                const SectionHeader(OrdersLabels.stage1Label),
                _buildReviewRow(theme, VN.products, '${regularItems.length} sản phẩm'),
                if (regularItems.isNotEmpty)
                  ...regularItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 2),
                      child: Text(
                        '${item.product.name} x${item.quantity} — ${formatVND(item.unitPrice * item.quantity)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (extraItems.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildReviewRow(theme, VN.extras, '${extraItems.length} phụ kiện'),
                  ...extraItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 2),
                      child: Text(
                        '${item.product.name} x${item.quantity}${item.isGift ? ' (${VN.tangKem})' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
                _buildReviewRow(theme, VN.total, formatVND(total)),
                const SizedBox(height: 16),

                const SectionHeader(OrdersLabels.stage2Label),
                _buildReviewRow(theme, VN.customerName, data.customerName.isNotEmpty ? data.customerName : '—'),
                if (data.customerPhone.isNotEmpty)
                  _buildReviewRow(theme, VN.customerPhone, data.customerPhone),
                _buildReviewRow(theme, VN.orderSource, state.source.isNotEmpty ? state.source : '—'),
                const SizedBox(height: 16),

                const SectionHeader(OrdersLabels.stage3Label),
                _buildReviewRow(theme, VN.deliveryType, _deliveryTypeLabel(data.deliveryType)),
                if (data.needsAddress) ...[
                  if (data.deliveryPhone.isNotEmpty)
                    _buildReviewRow(theme, OrdersLabels.deliveryPhone, data.deliveryPhone),
                  if (data.deliveryAddress.isNotEmpty)
                    _buildReviewRow(theme, VN.deliveryAddress, data.deliveryAddress),
                ],
                if (data.deliveryType == 'bus' || data.deliveryType == 'door')
                  _buildReviewRow(
                    theme,
                    VN.shippingFee,
                    data.shippingFee > 0 ? formatVND(data.shippingFee) : VN.shippingFree,
                  ),
                if (data.notes.isNotEmpty)
                  _buildReviewRow(theme, VN.notes, data.notes),
                _buildReviewRow(theme, VN.dueDate, '$dateStr — $timeStr'),
              ],
            ),
          ),
        ),
        _buildNavigation(),
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
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _deliveryTypeLabel(String type) {
    switch (type) {
      case 'bus':
        return VN.deliveryBus;
      case 'door':
        return VN.deliveryDoor;
      case 'pickup':
      default:
        return VN.pickup;
    }
  }

  Widget _buildNavigation() {
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
                : const Text(OrdersLabels.reviewCreateOrder),
          ),
        ],
      ),
    );
  }
}
