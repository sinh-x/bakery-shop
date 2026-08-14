import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';
import 'order_breakdown_mode.dart';

/// Dropdown that switches the breakdown display mode (FR2 / AC2).
class OrderBreakdownModeDropdown extends StatelessWidget {
  const OrderBreakdownModeDropdown({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final OrderBreakdownMode mode;
  final ValueChanged<OrderBreakdownMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DropdownButton<OrderBreakdownMode>(
        value: mode,
        isExpanded: false,
        items: const [
          DropdownMenuItem(
            value: OrderBreakdownMode.count,
            child: Text(SharedLabels.todaySalesOrderBreakdownModeCount),
          ),
          DropdownMenuItem(
            value: OrderBreakdownMode.countRevenue,
            child: Text(
                SharedLabels.todaySalesOrderBreakdownModeCountRevenue),
          ),
          DropdownMenuItem(
            value: OrderBreakdownMode.countRevenueShare,
            child: Text(
                SharedLabels.todaySalesOrderBreakdownModeCountRevenueShare),
          ),
        ],
        onChanged: (m) {
          if (m != null) onChanged(m);
        },
      ),
    );
  }
}