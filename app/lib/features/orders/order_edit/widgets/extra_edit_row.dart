import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';
import '../../../../data/models/work_item.dart';

class ExtraEditRow extends StatelessWidget {
  const ExtraEditRow({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onToggleGift,
    required this.onRemove,
  });

  final WorkItem item;
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
                item.isGift ? OrdersLabels.giftBadge : OrdersLabels.paymentFee,
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
              '${item.productName} (${formatVND(item.unitPrice)})',
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