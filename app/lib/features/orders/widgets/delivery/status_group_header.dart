import 'package:flutter/material.dart';

import '../../../../shared/theme/bakery_theme.dart';
import 'package:bakery_app/shared/labels/orders.dart' show statusMap;

/// Status-group header row for the delivery list view: a colored status dot,
/// the localized status label, and a count badge.
///
/// Extracted from `delivery_content.dart` (CQ-2, DG-329 Phase 5.6-c1 review
/// remediation) to keep the content file under the 200-line Flutter
/// coding-standards widget threshold (NFR2). This is existing debt
/// catalogued in `docs/code-quality-audit.md`. This is an
/// implementation-detail widget of the delivery list view and is not
/// intended for reuse outside it.
class DeliveryStatusGroupHeader extends StatelessWidget {
  const DeliveryStatusGroupHeader({
    super.key,
    required this.status,
    required this.count,
  });

  /// Status key (e.g. `new`, `confirmed`, `in_progress`, `ready`,
  /// `delivered`).
  final String status;

  /// Number of orders in this status group.
  final int count;

  @override
  Widget build(BuildContext context) {
    final statusColor = BakeryTheme.statusColors[status] ?? Colors.grey;
    final statusLabel = statusMap[status] ?? status;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
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
              statusLabel,
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
    );
  }
}