import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';
import '../../../shared/widgets/section_title.dart';
import '../../dashboard/widgets/metric_card.dart';

/// Revenue + payment summary for the Today Sales screen (DG-374 Phase 2 /
/// FR3), extended in DG-378 Phase 3 to add a cash-source breakdown, and in
/// DG-391 Phase 3 to add an AR (accounts receivable) line.
///
/// Split into three groups:
/// - "Tổng doanh thu": revenue + order count
/// - "Tổng tiền nhận được": cash + bank transfer (sales payment totals) +
///   AR line (DG-391 / FR5 / AC4): `ar = revenue − (cash + bank)`, orange
///   when AR > 0 (still owed), green when AR ≤ 0 (fully collected/surplus).
/// - "Nguồn tiền mặt" (DG-378 / FR3 / AC3): sales cash, cash-in, cash-out,
///   net cash. Net cash = `cashTotal + cashInTotal - cashOutTotal` (§14
///   default) — reflects the actual drawer inflow from sales plus owner
///   capital injections minus owner draws.
///
/// Loading state: each card whose value is `null` shows a skeleton
/// placeholder (NFR2 — per-section loading indicators) via [MetricCard]'s
/// `value == null` behavior.
class RevenueSummarySection extends StatelessWidget {
  const RevenueSummarySection({
    super.key,
    required this.totalRevenue,
    required this.orderCount,
    required this.cashTotal,
    required this.bankTransferTotal,
    required this.cashInTotal,
    required this.cashOutTotal,
  });

  final double? totalRevenue;
  final int? orderCount;
  final double? cashTotal;
  final double? bankTransferTotal;

  /// Owner/employee/equity capital injections into the drawer for the day
  /// (journal `source_type = 'cash_drawer_cash_in'`). DG-378.
  final double? cashInTotal;

  /// Owner draws from the drawer for the day (journal
  /// `source_type = 'cash_drawer_cash_out'`). DG-378.
  final double? cashOutTotal;

  @override
  Widget build(BuildContext context) {
    final totalReceived = (cashTotal != null && bankTransferTotal != null)
        ? cashTotal! + bankTransferTotal!
        : null;

    // Net cash = sales cash + capital injections − owner draws (§14 default).
    // Only compute when all three components are loaded; otherwise leave null
    // so the net cash card shows the same loading skeleton as its siblings.
    final netCash = (cashTotal != null && cashInTotal != null && cashOutTotal != null)
        ? cashTotal! + cashInTotal! - cashOutTotal!
        : null;

    // AR (accounts receivable) = revenue − (cash + bank transfer). Only
    // computed when all three inputs are loaded (DG-391 Phase 3 / FR5 / AC4).
    // Positive AR means customers still owe money (orange); AR ≤ 0 means the
    // period is fully collected or has a prepayment surplus (green).
    final ar = (totalRevenue != null && totalReceived != null)
        ? totalRevenue! - totalReceived
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
        const SizedBox(height: 8),
        MetricCard(
          icon: Icons.account_balance_wallet_outlined,
          label: SharedLabels.todaySalesAccountsReceivable,
          value: ar == null ? null : formatVND(ar),
          color: ar == null ? null : (ar > 0 ? Colors.orange : Colors.green),
        ),
        const SizedBox(height: 20),
        const SectionTitle(title: SharedLabels.todaySalesCashSourceSection),
        const SizedBox(height: 8),
        _MetricPair(
          a: MetricCard(
            icon: Icons.point_of_sale_outlined,
            label: SharedLabels.todaySalesCashSourceSalesCash,
            value: cashTotal == null ? null : formatVND(cashTotal!),
            color: Colors.green,
          ),
          b: MetricCard(
            icon: Icons.south_west_outlined,
            label: SharedLabels.todaySalesCashSourceCashIn,
            value: cashInTotal == null ? null : formatVND(cashInTotal!),
            color: Colors.teal,
          ),
        ),
        const SizedBox(height: 8),
        _MetricPair(
          a: MetricCard(
            icon: Icons.north_east_outlined,
            label: SharedLabels.todaySalesCashSourceCashOut,
            value: cashOutTotal == null ? null : formatVND(cashOutTotal!),
            color: Colors.deepOrange,
          ),
          b: MetricCard(
            icon: Icons.account_balance_wallet_outlined,
            label: SharedLabels.todaySalesCashSourceNetCash,
            value: netCash == null ? null : formatVND(netCash),
            color: Colors.indigo,
          ),
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