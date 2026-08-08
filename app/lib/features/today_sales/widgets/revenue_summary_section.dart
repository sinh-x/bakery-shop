import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/metric_card.dart';

/// Revenue summary section for the Today Sales screen (DG-374 Phase 2 / FR3).
///
/// Renders four [MetricCard]s in a 2-column grid:
/// - total revenue today (from journal 4100 + orders totalPrice)
/// - order count today (orders with dueDate == today)
/// - cash payment total (sum of today's payment transactions with method=cash)
/// - bank transfer total (sum of today's payment transactions with
///   method=transfer/card routed to bank accounts 1200/1210/1220/1290)
///
/// Loading state: each card whose value is `null` shows a skeleton placeholder
/// (NFR2 — per-section loading indicators) via [MetricCard]'s `value == null`
/// behavior.
class RevenueSummarySection extends StatelessWidget {
  const RevenueSummarySection({
    super.key,
    required this.totalRevenue,
    required this.orderCount,
    required this.cashTotal,
    required this.bankTransferTotal,
  });

  /// Total revenue today (journal 4100 credits + orders totalPrice). `null`
  /// while loading — renders a skeleton placeholder.
  final double? totalRevenue;

  /// Number of orders due today. `null` while loading.
  final int? orderCount;

  /// Sum of today's cash payments (method=cash, routed to account 1101).
  /// `null` while loading.
  final double? cashTotal;

  /// Sum of today's bank-transfer payments (method=transfer/card, routed to
  /// bank accounts 1200/1210/1220/1290). `null` while loading.
  final double? bankTransferTotal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesRevenueSection),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            MetricCard(
              icon: Icons.attach_money_outlined,
              label: SharedLabels.todaySalesTotalRevenue,
              value: totalRevenue == null ? null : formatVND(totalRevenue!),
            ),
            MetricCard(
              icon: Icons.receipt_long_outlined,
              label: SharedLabels.todaySalesOrderCount,
              value: orderCount == null ? null : '$orderCount',
            ),
            MetricCard(
              icon: Icons.payments_outlined,
              label: SharedLabels.todaySalesCashTotal,
              value: cashTotal == null ? null : formatVND(cashTotal!),
              color: Colors.green,
            ),
            MetricCard(
              icon: Icons.account_balance_outlined,
              label: SharedLabels.todaySalesBankTransferTotal,
              value: bankTransferTotal == null
                  ? null
                  : formatVND(bankTransferTotal!),
              color: Colors.blue,
            ),
          ],
        ),
      ],
    );
  }
}
