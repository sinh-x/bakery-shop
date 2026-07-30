import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';

/// Renders the trưng bày markup amount line (`unitPrice − assignedPrice`) when
/// the item carries a positive markup.
///
/// Shows nothing when [assignedPrice] is null (historical data, treated as no
/// markup per FR7) or when `assignedPrice >= unitPrice` (no markup). The label
/// comes from the shared VN label constants ([VN.markupAmount]).
///
/// DG-296 Phase 5 (FR7 / AC6).
class OrderItemMarkupLine extends StatelessWidget {
  const OrderItemMarkupLine({
    super.key,
    required this.unitPrice,
    required this.assignedPrice,
  });

  final double unitPrice;
  final double? assignedPrice;

  @override
  Widget build(BuildContext context) {
    final assigned = assignedPrice;
    if (assigned == null || assigned >= unitPrice) return const SizedBox.shrink();
    final markup = unitPrice - assigned;
    return Text(
      '${VN.markupAmount}: ${formatVND(markup)}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.green.shade700,
            fontWeight: FontWeight.w500,
          ),
    );
  }
}
