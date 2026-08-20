import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/due_date_order_list_providers.dart';
import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/today_order_list.dart';

/// Order-list section for the day tab. CQ-1: the order rows now come from a
/// dedicated [dueDateOrdersProvider] fetch (`GET /api/orders?due_date=<date>`)
/// instead of the removed `summary.orders` list. The summary endpoint remains
/// the source of truth for revenue, order count, and status breakdown; only
/// the order rows are fetched separately. Orders are grouped by status with
/// due-date/time ordering within each group (DG-376 FR6/AC6).
///
/// Extracted from `day_tab_body.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DayOrderListSection extends ConsumerWidget {
  const DayOrderListSection({super.key, required this.selectedDate});

  final String selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(dueDateOrdersProvider(selectedDate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesOrderListSection),
        const SizedBox(height: 8),
        ordersAsync.when(
          data: (orders) => TodayOrderList(orders: orders),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Text(
              SharedLabels.errorLoading,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}