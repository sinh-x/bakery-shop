import 'package:flutter/material.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/order_helpers.dart';
import '../../../shared/widgets/section_title.dart';

/// Today's order list for the Today Sales screen (DG-374 Phase 2 / FR4).
///
/// Renders one row per order due today, showing:
/// - order ref (visual order code)
/// - customer name
/// - status badge (colored by [BakeryTheme.statusColors])
/// - total price (VND formatted)
/// - payment status indicator (Đã TT / Cọc / Chưa TT)
///
/// Loading state: shows a [CircularProgressIndicator] while the orders
/// provider is resolving. Empty state: shows [SharedLabels.todaySalesEmptyOrders].
/// Error state: shows a retry affordance.
class TodayOrderList extends StatelessWidget {
  const TodayOrderList({
    super.key,
    required this.orders,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    this.onTapOrder,
  });

  /// Today's orders (already filtered by dueDate == today).
  final List<Order> orders;

  /// Whether the orders provider is still loading.
  final bool isLoading;

  /// Error from the orders provider, if any.
  final Object? error;

  /// Retry callback when the fetch fails.
  final VoidCallback onRetry;

  /// Optional tap handler for an order row.
  final void Function(Order order)? onTapOrder;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && orders.isEmpty) {
      return _OrderListError(error: error, onRetry: onRetry);
    }
    if (orders.isEmpty) {
      return _OrderListEmpty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderListSection),
        const SizedBox(height: 8),
        for (final order in orders)
          _TodayOrderRow(
            order: order,
            paymentBadge: _paymentBadgeFor(order),
            onTap: onTapOrder,
          ),
      ],
    );
  }
}

/// Computes the (color, label) payment-status badge for [order] once, so the
/// row widget does not recompute it on every build pass (CQ-6).
(Color, String) _paymentBadgeFor(Order order) {
  if (order.isPaid) {
    return (Colors.green, VN.paid);
  } else if (order.amountPaid > 0) {
    return (Colors.orange, VN.partialPaid);
  } else {
    return (Colors.red, VN.unpaid);
  }
}

class _TodayOrderRow extends StatelessWidget {
  const _TodayOrderRow({
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

class _OrderListEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          SharedLabels.todaySalesEmptyOrders,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _OrderListError extends StatelessWidget {
  const _OrderListError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SharedLabels.errorLoading),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text(SharedLabels.retry),
            ),
          ],
        ),
      ),
    );
  }
}
