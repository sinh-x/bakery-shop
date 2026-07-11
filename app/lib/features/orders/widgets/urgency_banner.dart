import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/order_helpers.dart';

/// Pinned attention banner at top of the orders list summarizing critical and
/// urgent order counts.
///
/// Hidden when both counts are 0. When tapped, invokes [onTap] so the parent
/// screen can filter or scroll to high-urgency orders.
class UrgencyBanner extends StatelessWidget {
  const UrgencyBanner({
    super.key,
    required this.criticalCount,
    required this.urgentCount,
    required this.onTap,
  });

  final int criticalCount;
  final int urgentCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (criticalCount == 0 && urgentCount == 0) {
      return const SizedBox.shrink();
    }

    final criticalColor = BakeryTheme.urgencyTierColors[urgencyCritical] ?? Colors.red;
    final urgentColor = BakeryTheme.urgencyTierColors[urgencyUrgent] ?? Colors.amber;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: criticalColor.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.warning_rounded, color: criticalColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        OrdersLabels.urgencyBannerTitle,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _buildSummary(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (criticalCount > 0)
                  _CountChip(
                    count: criticalCount,
                    label: OrdersLabels.urgencyBannerCritical,
                    color: criticalColor,
                  ),
                if (urgentCount > 0) ...[
                  const SizedBox(width: 6),
                  _CountChip(
                    count: urgentCount,
                    label: OrdersLabels.urgencyBannerUrgent,
                    color: urgentColor,
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildSummary() {
    return OrdersLabels.urgencyBannerText(criticalCount, urgentCount);
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
