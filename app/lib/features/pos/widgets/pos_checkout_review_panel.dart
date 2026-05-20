import 'package:flutter/material.dart';

import '../../../providers/pos_provider.dart';
import '../../../shared/labels/shared.dart';

class PosCheckoutReviewPanel extends StatelessWidget {
  const PosCheckoutReviewPanel({
    super.key,
    required this.items,
    required this.total,
    required this.paymentMethodLabel,
    required this.isProcessing,
    required this.onEditOrder,
    required this.onFinalize,
  });

  final List<PosCartItem> items;
  final double total;
  final String paymentMethodLabel;
  final bool isProcessing;
  final VoidCallback onEditOrder;
  final VoidCallback onFinalize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            children: [
              Text(
                VN.checkoutReviewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                VN.checkoutReviewHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ...items.map(_buildLineItem),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  title: const Text(VN.paymentMethod),
                  trailing: Text(paymentMethodLabel),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text(VN.total),
                  trailing: Text(
                    formatVND(total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing ? null : onEditOrder,
                    child: const Text(VN.editOrder),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isProcessing ? null : onFinalize,
                    icon: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text(VN.xong),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineItem(PosCartItem item) {
    final hasChipLabel = (item.selectedChipLabel ?? '').trim().isNotEmpty;
    final displayName = hasChipLabel
        ? '${item.product.name} (${item.selectedChipLabel!.trim()})'
        : item.product.name;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayName),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${VN.soLuong}: ${item.quantity}'),
                Text('${VN.donGia}: ${formatVND(item.unitPrice)}'),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${VN.total}: ${formatVND(item.total)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
