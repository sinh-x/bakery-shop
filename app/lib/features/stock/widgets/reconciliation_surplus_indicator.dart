import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Displays the surplus inflow quantity for a reconciliation option.
///
/// When `counted > expected`, the surplus will be converted into a `restock`
/// inflow by the reconciliation backend (after netting any negative balance).
/// This indicator surfaces the inflow quantity and a restock badge so staff
/// can confirm the surplus is intentional before submitting.
class ReconciliationSurplusIndicator extends StatelessWidget {
  const ReconciliationSurplusIndicator({required this.surplus, super.key});

  final int surplus;

  @override
  Widget build(BuildContext context) {
    final color = Colors.teal[700]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.south_west, size: 14, color: Colors.teal),
          const SizedBox(width: 4),
          Text(
            '${VN.soLuongBu}: +$surplus',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            VN.nhapBuTonKho,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}