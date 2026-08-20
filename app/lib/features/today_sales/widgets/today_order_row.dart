import 'package:bakery_app/shared/utils.dart' show formatVND, statusMap;
import 'package:flutter/material.dart';

import '../../../data/models/order.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/order_helpers.dart';

/// A single today-order row: order ref, customer name, status badge, total
/// price (VND formatted), and payment-status indicator.
///
/// Extracted from `today_order_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class TodayOrderRow extends StatelessWidget {
  const TodayOrderRow({
    super.key,
    required this.order,
    required this.paymentBadge,
    this.onTap,
  });

  final Order order;

  /// Precomputed (color, label) pair for the payment-status badge. Computed
  /// once by the parent [TodayOrderList] so the row's `build` does not
  /// re-evaluate it on every layout pass (CQ-6).
  final (Color, String) paymentBadge;

  final void Function(Order order)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final paymentColor = paymentBadge.$1;
    final paymentLabel = paymentBadge.$2;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    deliveryIcon(order.deliveryType),
                    size: 18,
                    color: deliveryIconColor(
                      order.deliveryType,
                      theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      visualOrderCode(
                        orderRef: order.orderRef,
                        publicOrderCode: order.publicOrderCode,
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(120)),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                order.customerName,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    formatVND(order.totalPrice),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: paymentColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: paymentColor.withAlpha(100)),
                    ),
                    child: Text(
                      paymentLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: paymentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}