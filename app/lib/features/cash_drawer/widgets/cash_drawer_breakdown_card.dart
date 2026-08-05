/// Categorized cash in/out breakdown card (DG-359 Phase 1).
///
/// Renders a six-row breakdown of drawer transactions by category — Bán hàng,
/// Chi phí, Nạp tiền, Rút tiền, Mở quầy, Đóng quầy — followed by a footer with
/// total inflow and total outflow. Aggregation is fully client-side on a
/// list of [CashDrawerTransaction] already fetched by
/// `cashDrawerTransactionsProvider` (NFR2: no new network request).
///
/// Special transaction types are folded into the closest canonical category
/// (FR7):
///   - `cash_drawer_auto_transfer` → Rút tiền
///   - `unidentified_sale`         → Bán hàng
///   - `owner_capital`             → Nạp tiền
///
/// The widget is a pure function of its `transactions` prop, so Phase 2 can
/// wire it into [CashDrawerStatusCard] by passing the active drawer's loaded
/// transaction list. Empty state (FR5) renders all six categories with zero
/// totals and zero counts rather than a blank table.
library;

import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer_transaction.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Canonical breakdown category (DG-359 FR1). Order is fixed so the table
/// renders categories in a stable, predictable order.
enum CashDrawerBreakdownCategory {
  sale,
  expense,
  cashIn,
  cashOut,
  open,
  close,
}

/// Map a raw journal `source_type` to a breakdown category (FR7).
///
/// Special types `cash_drawer_auto_transfer`, `unidentified_sale`, and
/// `owner_capital` are folded into the closest canonical category as
/// specified in the requirements doc.
CashDrawerBreakdownCategory _categoryForType(String type) {
  switch (type) {
    case 'payment_transaction':
    case 'unidentified_sale':
      return CashDrawerBreakdownCategory.sale;
    case 'expense':
      return CashDrawerBreakdownCategory.expense;
    case 'cash_drawer_cash_in':
    case 'owner_capital':
      return CashDrawerBreakdownCategory.cashIn;
    case 'cash_drawer_cash_out':
    case 'cash_drawer_auto_transfer':
      return CashDrawerBreakdownCategory.cashOut;
    case 'cash_drawer_open':
      return CashDrawerBreakdownCategory.open;
    case 'cash_drawer_close_adjust':
      return CashDrawerBreakdownCategory.close;
    default:
      // Unknown source types fall back to the sale category so the row
      // stays visible; the per-row total surfaces the unrecognised amount.
      return CashDrawerBreakdownCategory.sale;
  }
}

String _labelFor(CashDrawerBreakdownCategory c) {
  switch (c) {
    case CashDrawerBreakdownCategory.sale:
      return VN.cashDrawerTxnTypeSale;
    case CashDrawerBreakdownCategory.expense:
      return VN.cashDrawerTxnTypeExpense;
    case CashDrawerBreakdownCategory.cashIn:
      return VN.cashDrawerTxnTypeCashIn;
    case CashDrawerBreakdownCategory.cashOut:
      return VN.cashDrawerTxnTypeCashOut;
    case CashDrawerBreakdownCategory.open:
      return VN.cashDrawerTxnTypeOpen;
    case CashDrawerBreakdownCategory.close:
      return VN.cashDrawerTxnTypeClose;
  }
}

/// Per-category aggregated row.
class CashDrawerBreakdownRow {
  const CashDrawerBreakdownRow({
    required this.category,
    required this.totalAmount,
    required this.count,
  });

  final CashDrawerBreakdownCategory category;
  final int totalAmount;
  final int count;

  /// Signed display amount: inflow categories keep `+`, outflow categories
  /// get `-`. The sign is derived from the category direction rather than
  /// the summed amount so an outflow with a net-positive sum still renders
  /// as a negative (defensive against malformed backend data).
  bool get isInflow =>
      category == CashDrawerBreakdownCategory.sale ||
      category == CashDrawerBreakdownCategory.cashIn ||
      category == CashDrawerBreakdownCategory.open;
}

/// Aggregate a transaction list into one [CashDrawerBreakdownRow] per
/// canonical category (FR1/FR2). Empty categories are included with zero
/// totals so the table always shows six rows (FR5).
List<CashDrawerBreakdownRow> aggregateCashDrawerBreakdown(
    List<CashDrawerTransaction> transactions) {
  final totals = <CashDrawerBreakdownCategory, int>{
    for (final c in CashDrawerBreakdownCategory.values) c: 0,
  };
  final counts = <CashDrawerBreakdownCategory, int>{
    for (final c in CashDrawerBreakdownCategory.values) c: 0,
  };
  for (final t in transactions) {
    final c = _categoryForType(t.type);
    totals[c] = totals[c]! + t.amount;
    counts[c] = counts[c]! + 1;
  }
  return [
    for (final c in CashDrawerBreakdownCategory.values)
      CashDrawerBreakdownRow(
        category: c,
        totalAmount: totals[c]!,
        count: counts[c]!,
      ),
  ];
}

/// Breakdown card widget (DG-359 Phase 1). Renders the six category rows
/// and a footer with total inflow / total outflow.
class CashDrawerBreakdownCard extends StatelessWidget {
  const CashDrawerBreakdownCard({
    super.key,
    required this.transactions,
  });

  final List<CashDrawerTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = aggregateCashDrawerBreakdown(transactions);
    int totalIn = 0;
    int totalOut = 0;
    for (final r in rows) {
      if (r.totalAmount > 0) {
        totalIn += r.totalAmount;
      } else if (r.totalAmount < 0) {
        totalOut += r.totalAmount.abs();
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          VN.cashDrawerBreakdownTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        for (final r in rows) _BreakdownRow(row: r),
        const Divider(height: 16),
        _TotalRow(
          label: VN.cashDrawerBreakdownTotalIn,
          amount: totalIn,
          inflow: true,
        ),
        _TotalRow(
          label: VN.cashDrawerBreakdownTotalOut,
          amount: totalOut,
          inflow: false,
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.row});

  final CashDrawerBreakdownRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inflow = row.isInflow && row.totalAmount > 0;
    final outflow = !row.isInflow && row.totalAmount < 0;
    final signed = row.totalAmount == 0
        ? formatVND(0)
        : inflow
            ? '+${formatVND(row.totalAmount.toDouble())}'
            : '-${formatVND(row.totalAmount.abs().toDouble())}';
    final color = row.totalAmount == 0
        ? null
        : inflow
            ? Colors.green.shade700
            : (outflow
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(_labelFor(row.category), style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 3,
            child: Text(
              signed,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${row.count}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    required this.inflow,
  });

  final String label;
  final int amount;
  final bool inflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        amount == 0 ? null : inflow ? Colors.green.shade700 : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          Text(
            (amount == 0 ? '' : (inflow ? '+' : '-')) +
                formatVND(amount.toDouble()),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}