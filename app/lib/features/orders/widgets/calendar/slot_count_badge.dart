import 'package:flutter/material.dart';

import '../../../../shared/labels/orders.dart';

/// Count badge shown at the top of a calendar time-slot row when the slot
/// has 3+ orders (DG-329 Phase 4 / FR5 / AC4). Renders as a small pill with
/// the order count, e.g. "3 đơn".
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2). This is an
/// implementation-detail widget of the day/week calendar views and is not
/// intended for reuse outside the calendar grids.
class SlotCountBadge extends StatelessWidget {
  const SlotCountBadge({super.key, required this.count, required this.theme});

  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        OrdersLabels.deliverySlotCountBadge(count),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}