import 'package:flutter/material.dart';

import '../../../../data/api/staff_service.dart';
import '../../../../data/models/order.dart';
import '../../../../shared/labels/orders.dart';
import '../../../../shared/utils/delivery_helpers.dart';

/// Per-staff workload summary (FR6/AC5): shows each active staff
/// member's count of today's non-terminal delivery orders, plus an
/// "unassigned" bucket. Renders for ALL active staff regardless of role
/// (not just `giao-hang`) — Phase 1 expanded `_deliveryStaff` to all
/// active staff, so the summary now appears whenever any active staff
/// exist. Collapses to the empty-state label when there are no active
/// staff and hides entirely when the staff list is still loading.
///
/// Extracted from `delivery_content.dart` (CQ-2, DG-329 Phase 5.6-c1 review
/// remediation) to keep the content file under the 200-line Flutter
/// coding-standards widget threshold (NFR2). This is existing debt
/// catalogued in `docs/code-quality-audit.md`. This is an
/// implementation-detail widget of the delivery tab and is not intended
/// for reuse outside it.
class WorkloadSummary extends StatelessWidget {
  const WorkloadSummary({
    super.key,
    required this.deliveryStaff,
    required this.todayOrders,
  });

  final List<StaffMember> deliveryStaff;
  final List<Order> todayOrders;

  @override
  Widget build(BuildContext context) {
    if (deliveryStaff.isEmpty) return const SizedBox.shrink();

    final summary = computeWorkloadSummary(todayOrders, deliveryStaff);
    final theme = Theme.of(context);

    final chips = <Widget>[];
    for (final entry in summary.entries) {
      chips.add(
        Chip(
          label: Text(
            OrdersLabels.workloadStaffCount(entry.staff.name, entry.count),
            style: theme.textTheme.bodySmall,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      );
    }
    chips.add(
      Chip(
        label: Text(
          '${OrdersLabels.workloadUnassigned}: ${summary.unassignedCount}',
          style: theme.textTheme.bodySmall,
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
    );

    final allZero = summary.entries.every((e) => e.count == 0) &&
        summary.unassignedCount == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              allZero
                  ? OrdersLabels.workloadSummaryEmpty
                  : OrdersLabels.workloadSummaryTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.outline,
              ),
            ),
            if (!allZero) ...chips,
          ],
        ),
      ),
    );
  }
}