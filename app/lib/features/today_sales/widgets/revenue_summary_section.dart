import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/metric_card.dart';

/// Revenue + payment summary for the Today Sales screen (DG-374 Phase 2 / FR3).
///
/// Split into two groups:
/// - "Tổng doanh thu": revenue + order count
/// - "Tổng tiền nhận được": cash + bank transfer
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

  final double? totalRevenue;
  final int? orderCount;
  final double? cashTotal;
  final double? bankTransferTotal;

  @override
  Widget build(BuildContext context) {
    final totalReceived = (cashTotal != null && bankTransferTotal != null)
        ? cashTotal! + bankTransferTotal!
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: SharedLabels.todaySalesRevenueGroup),
        const SizedBox(height: 8),
        _MetricPair(
          a: MetricCard(
            icon: Icons.attach_money_outlined,
            label: SharedLabels.todaySalesTotalRevenue,
            value: totalRevenue == null ? null : formatVND(totalRevenue!),
          ),
          b: MetricCard(
            icon: Icons.receipt_long_outlined,
            label: SharedLabels.todaySalesOrderCount,
            value: orderCount == null ? null : '$orderCount',
          ),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: SharedLabels.todaySalesPaymentGroup),
        const SizedBox(height: 8),
        _MetricPair(
          a: MetricCard(
            icon: Icons.payments_outlined,
            label: SharedLabels.todaySalesCashTotal,
            value: cashTotal == null ? null : formatVND(cashTotal!),
            color: Colors.green,
          ),
          b: MetricCard(
            icon: Icons.account_balance_outlined,
            label: SharedLabels.todaySalesBankTransferTotal,
            value: bankTransferTotal == null
                ? null
                : formatVND(bankTransferTotal!),
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        MetricCard(
          icon: Icons.summarize_outlined,
          label: SharedLabels.todaySalesTotalReceived,
          value:
              totalReceived == null ? null : formatVND(totalReceived),
          color: Colors.teal,
        ),
      ],
    );
  }
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({required this.a, required this.b});

  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [a, b],
    );
  }
}
