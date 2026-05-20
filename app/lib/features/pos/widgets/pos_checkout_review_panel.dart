import 'package:flutter/material.dart';

import '../../../providers/pos_provider.dart';
import '../../../shared/labels/orders.dart';
import '../utils/pos_cart_item_display.dart';

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
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: items.length + 4,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  OrdersLabels.checkoutReviewTitle,
                  style: theme.textTheme.titleLarge,
                );
              }

              if (index == 1) {
                return Text(
                  OrdersLabels.checkoutReviewHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }

              if (index <= items.length + 1) {
                return _buildLineItem(items[index - 2]);
              }

              if (index == items.length + 2) {
                return Card(
                  child: ListTile(
                    title: const Text(VN.paymentMethod),
                    trailing: Text(paymentMethodLabel),
                  ),
                );
              }

              return Card(
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
              );
            },
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
                    label: const Text(OrdersLabels.done),
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
    final displayTotal = item.isGift ? 0.0 : item.total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(posCartItemDisplayName(item)),
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
                '${VN.total}: ${formatVND(displayTotal)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
