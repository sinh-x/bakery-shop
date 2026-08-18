import 'package:flutter/material.dart';

import '../../../data/models/order.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'today_order_list_empty.dart';
import 'today_order_list_error.dart';
import 'today_order_row.dart';

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
///
/// Coding standards (NFR2): row/empty/error rendering is delegated to
/// extracted widgets under `widgets/` (see [TodayOrderRow],
/// [TodayOrderListEmpty], [TodayOrderListError]).
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
      return TodayOrderListError(error: error, onRetry: onRetry);
    }
    if (orders.isEmpty) {
      return const TodayOrderListEmpty();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderListSection),
        const SizedBox(height: 8),
        for (final order in orders)
          TodayOrderRow(
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
    return (Colors.green, OrdersLabels.paid);
  } else if (order.amountPaid > 0) {
    return (Colors.orange, OrdersLabels.partialPaid);
  } else {
    return (Colors.red, OrdersLabels.unpaid);
  }
}