import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../../shared/labels/orders.dart';
import 'compact_mini_order_card.dart';

/// Compact `Wrap`-based layout for order chips in a calendar time-slot row
/// (DG-329 Phase 4 / FR5 / NFR2 / AC4). Renders up to
/// [OrdersLabels.compactOrderChipsPerRow] chips per row, each with a minimum
/// readable width of [OrdersLabels.compactOrderChipMinWidth] pixels. When the
/// available width cannot fit 4 chips, `Wrap` automatically flows extra
/// chips onto subsequent rows. Overflow beyond the row height is clipped.
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) to keep the components file under the
/// 200-line Flutter coding-standards widget threshold (NFR2). This is an
/// implementation-detail widget of the day/week calendar views and is not
/// intended for reuse outside the calendar grids.
class CompactOrderChips extends StatelessWidget {
  const CompactOrderChips({super.key, required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: orders
            .map((o) => CompactMiniOrderCard(order: o, compact: true))
            .toList(growable: false),
      ),
    );
  }
}