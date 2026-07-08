import 'package:flutter/material.dart';

import '../../../data/models/order_draft.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// One-line row for an extra (phu_kien) [DraftOrderItem] in Stage 1.
///
/// Shows: gift/pay badge toggle, product name + unit price, quantity
/// decrement/increment, and a remove button. Replaces [ExpandableItemCard]
/// for extras per FB-4.
class SimpleExtraRow extends StatelessWidget {
  const SimpleExtraRow({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleGift,
    required this.onRemove,
  });

  final DraftOrderItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onToggleGift;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggleGift,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.isGift
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: item.isGift ? Colors.green : Colors.grey.shade300,
                ),
              ),
              child: Text(
                item.isGift ? VN.giftBadge : VN.paymentFee,
                style: TextStyle(
                  fontSize: 10,
                  color: item.isGift ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${item.product.name} (${formatVND(item.unitPrice)})',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDecrement,
          ),
          Text('${item.quantity}', style: theme.textTheme.bodyMedium),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onIncrement,
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}