import 'package:bakery_app/shared/utils.dart' show statusMap;
import 'package:flutter/material.dart';

import '../../../shared/theme/bakery_theme.dart';

/// Header row for a status group in the cake queue (FR1, FR3).
///
/// Renders a colored dot from `BakeryTheme.statusColors`, the status label
/// from `statusMap`, and a count badge. Tapping toggles the group's
/// collapsed state via [onTap]. Grouping keys are the parent order's
/// status (new/confirmed/in_progress/ready/delivered), not the work item
/// status.
class CakeQueueGroupHeader extends StatelessWidget {
  const CakeQueueGroupHeader({
    super.key,
    required this.status,
    required this.count,
    required this.isCollapsed,
    required this.onTap,
  });

  final String status;
  final int count;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = BakeryTheme.statusColors[status] ?? Colors.grey;
    final label = statusMap[status] ?? status;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                isCollapsed
                    ? Icons.keyboard_arrow_right
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: statusColor,
              ),
              const SizedBox(width: 4),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
