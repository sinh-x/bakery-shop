import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/order.dart';
import '../../../providers/order/due_date_order_list_providers.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/section_title.dart';
import 'today_order_list.dart';

/// Today's orders section (FR6/AC6): today's orders grouped by status.
/// Extracted to keep the body widget under the 300-line screen threshold
/// (flutter-coding-standards §1).
///
/// CQ-1: the order rows now come from a dedicated [dueDateOrdersProvider]
/// fetch (`GET /api/orders?due_date=<today>`) instead of the removed
/// `summary.orders` list. The summary endpoint remains the source of truth
/// for revenue and order count; only the order rows are fetched separately.
class TodayOrdersSection extends ConsumerWidget {
  const TodayOrdersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayStr = formatApiDate(DateTime.now());
    final ordersAsync = ref.watch(dueDateOrdersProvider(todayStr));
    final todayOrders = ordersAsync.asData?.value ?? const <Order>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: SharedLabels.todayOrders),
        const SizedBox(height: 8),
        if (ordersAsync.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          TodayOrderList(orders: todayOrders),
      ],
    );
  }
}