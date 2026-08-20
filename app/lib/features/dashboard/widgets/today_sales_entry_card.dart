import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';
import 'metric_card.dart';

/// Single entry-point card replacing the former three "Chỉ số hôm nay"
/// MetricCards (DG-374 Phase 1 / FR2). Tapping navigates to `/today-sales`.
/// Shows today's revenue as a live preview value when available.
class TodaySalesEntryCard extends StatelessWidget {
  const TodaySalesEntryCard({
    super.key,
    required this.revenueToday,
    required this.onTap,
  });

  final String? revenueToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      icon: Icons.attach_money_outlined,
      label: SharedLabels.dashboardMetricViewTodaySales,
      value: revenueToday,
      onTap: onTap,
    );
  }
}