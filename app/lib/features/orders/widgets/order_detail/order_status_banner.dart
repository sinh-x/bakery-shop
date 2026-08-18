import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import 'package:bakery_app/shared/theme/bakery_theme.dart';
import 'package:bakery_app/shared/utils/order_helpers.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Status banner showing the order's current status and visual order code.
class OrderStatusBanner extends StatelessWidget {
  const OrderStatusBanner({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withAlpha(120)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                statusLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                visualOrderCode(
                  orderRef: order.orderRef,
                  publicOrderCode: order.publicOrderCode,
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        // ── Missing-field warning (DG-241 Phase 3) ──────────────────────
        if (order.completeness == completenessIncomplete &&
            order.missingFields.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BakeryTheme.completenessTierColors['incomplete']
                      ?.withAlpha(15) ??
                  Colors.amber.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: BakeryTheme.completenessTierColors['incomplete'] ??
                    Colors.amber,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      BakeryTheme.completenessTierIcons['incomplete'] ??
                          Icons.warning_amber_rounded,
                      size: 20,
                      color:
                          BakeryTheme.completenessTierColors['incomplete'] ??
                              Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      OrdersLabels.missingFieldsSection,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: BakeryTheme
                                .completenessTierColors['incomplete'] ??
                            Colors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...order.missingFields.map((field) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              missingFieldLabel(field),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}