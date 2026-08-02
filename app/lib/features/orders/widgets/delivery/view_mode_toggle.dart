import 'package:flutter/material.dart';

import '../../../../shared/labels/orders.dart';

/// Cycle button that toggles between list → week → day → list views.
///
/// Extracted from `delivery_content.dart` (CQ-2, DG-329 Phase 5.6-c1 review
/// remediation) to keep the content file under the 200-line Flutter
/// coding-standards widget threshold (NFR2). This is existing debt
/// catalogued in `docs/code-quality-audit.md`. This is an
/// implementation-detail widget of the delivery tab and is not intended
/// for reuse outside it.
class ViewModeToggle extends StatelessWidget {
  const ViewModeToggle({
    super.key,
    required this.viewMode,
    required this.onChanged,
  });

  final String viewMode;
  final ValueChanged<String> onChanged;

  IconData _icon() {
    switch (viewMode) {
      case 'list':
        return Icons.calendar_month_outlined;
      case 'week':
        return Icons.view_day_outlined;
      case 'day':
        return Icons.view_list;
      default:
        return Icons.calendar_month_outlined;
    }
  }

  String _tooltip() {
    switch (viewMode) {
      case 'list':
        return OrdersLabels.deliverySwitchToWeek;
      case 'week':
        return OrdersLabels.deliverySwitchToDay;
      case 'day':
        return OrdersLabels.deliverySwitchToList;
      default:
        return OrdersLabels.deliverySwitchToWeek;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_icon()),
      tooltip: _tooltip(),
      onPressed: () {
        switch (viewMode) {
          case 'list':
            onChanged('week');
          case 'week':
            onChanged('day');
          case 'day':
            onChanged('list');
        }
      },
    );
  }
}