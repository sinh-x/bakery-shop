/// Categorized cash in/out breakdown card (DG-359 Phase 1, DG-363 Phase 3/4).
///
/// Renders an 8-category breakdown split into two groups — "Tiền vào" and
/// "Tiền ra" — each with its own total, plus a footer reconciling inflow −
/// outflow = expected balance. Special transaction types are folded into
/// canonical categories (FR7), and `payment_transaction` rows are split by
/// sign and shipping (FR4/FR5).
///
/// The widget is a pure function of its inputs: [transactions] (live, open
/// drawer — wired into [CashDrawerStatusCard]) or [breakdown] (snapshot,
/// closed drawer — wired into [CashDrawerHistoryList], Phase 4 / FR7). Empty
/// state (FR5) renders all 8 categories with zero totals/counts.
///
/// Per NFR3 (file ≤ 300 lines) the group widgets live in their own files
/// (`cash_drawer_breakdown_inflow_group.dart`,
/// `cash_drawer_breakdown_outflow_group.dart`) and the snapshot adapter in
/// `cash_drawer_breakdown_snapshot.dart`.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer_transaction.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'cash_drawer_breakdown_inflow_group.dart';
import 'cash_drawer_breakdown_outflow_group.dart';
import 'cash_drawer_breakdown_row.dart';

/// Canonical breakdown category (DG-359 FR1, DG-363 Phase 3). Order is fixed
/// so the table renders categories in a stable, predictable order. The
/// two new categories (`refund`, `busShipping`) join the existing six.
enum CashDrawerBreakdownCategory {
  sale,
  refund,
  expense,
  cashIn,
  cashOut,
  open,
  close,
  busShipping,
}

/// Map a raw journal `source_type` plus the row's amount and shipping portion
/// to a breakdown category (FR4/FR5/FR7).
///
/// `payment_transaction` is split by sign: amount < 0 → `refund`; amount > 0
/// → `sale` (the shipping split is applied later in
/// [aggregateCashDrawerBreakdown] so the sale row keeps only the non-shipping
/// portion). Special types `cash_drawer_auto_transfer`, `unidentified_sale`,
/// and `owner_capital` are folded into the closest canonical category as
/// specified in the requirements doc.
///
/// CQ-1 (DG-363 review-auto cycle 1): this source_type → category mapping
/// is triplicated. The same classification logic exists in two backend
/// files and MUST be kept in sync with this Dart code:
///   - `src/baker/db/schema/migrations/v097.py`:
///     `_migrate_v97_cash_drawer_breakdown_snapshot` (the backfill path that
///     persists snapshots for already-closed drawers)
///   - `src/baker/models/cash_drawer.py`:
///     `CashDrawer._aggregate_breakdown` (the live-aggregation path used at
///     close time and by /status)
/// Any change to a category mapping, ordering, fallback, or the
/// payment_transaction shipping split here MUST be mirrored in both backend
/// files so the client-side live aggregation, the persisted snapshot, and
/// the backend live aggregation stay consistent.
CashDrawerBreakdownCategory _categoryForType(
  String type,
  int amount,
  int shippingAmount,
) {
  switch (type) {
    case 'payment_transaction':
      // FR4: amount < 0 → refund; amount > 0 → sale. The shipping split is
      // applied in aggregateCashDrawerBreakdown (FR5) so the sale row keeps
      // only the non-shipping portion and busShipping gets the rest.
      if (amount < 0) return CashDrawerBreakdownCategory.refund;
      return CashDrawerBreakdownCategory.sale;
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
      if (kDebugMode) {
        debugPrint('Unknown source_type: $type');
      }
      return CashDrawerBreakdownCategory.sale;
  }
}

String labelForCategory(CashDrawerBreakdownCategory c) {
  switch (c) {
    case CashDrawerBreakdownCategory.sale:
      return VN.cashDrawerTxnTypeSale;
    case CashDrawerBreakdownCategory.refund:
      return VN.cashDrawerTxnTypeRefund;
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
    case CashDrawerBreakdownCategory.busShipping:
      return VN.cashDrawerTxnTypeBusShipping;
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

  /// Whether this category contributes to the inflow total ("Tổng tiền vào")
  /// vs the outflow total ("Tổng tiền ra"). Used by
  /// [aggregateCashDrawerBreakdown] to compute the group totals so that
  /// `totalIn − totalOut` reconciles with the 1101 expected balance (FR3/AC3).
  ///
  /// `busShipping` is displayed in the "Tiền ra" group (FR1) because the
  /// shipping portion is earmarked to be paid to the bus company, but its
  /// amount is positive (cash the customer paid in). It therefore counts
  /// toward the inflow total so the reconciliation holds; the "Tổng tiền ra"
  /// total sums only the genuinely negative outflow categories (refund,
  /// expense, cashOut, close).
  bool get isInflow =>
      category == CashDrawerBreakdownCategory.sale ||
      category == CashDrawerBreakdownCategory.cashIn ||
      category == CashDrawerBreakdownCategory.open ||
      category == CashDrawerBreakdownCategory.busShipping;
}

/// Aggregated breakdown result: one row per canonical category plus the
/// group totals (inflow total, outflow total) computed in the same pass.
/// `totalIn` sums inflow row amounts; `totalOut` sums the absolute value of
/// outflow row amounts. Computed alongside the rows so the widget does not
/// need a second pass over the data (CQ-2). `expectedBalance` is
/// `totalIn − totalOut` and should match the status card's expected balance
/// (FR3/AC3).
class CashDrawerBreakdown {
  const CashDrawerBreakdown({
    required this.rows,
    required this.totalIn,
    required this.totalOut,
  });

  final List<CashDrawerBreakdownRow> rows;
  final int totalIn;
  final int totalOut;

  int get expectedBalance => totalIn - totalOut;
}

/// Aggregate a transaction list into a [CashDrawerBreakdown] containing one
/// [CashDrawerBreakdownRow] per canonical category (FR1/FR2) and the group
/// totals. Empty categories are included with zero totals so the table
/// always shows 8 rows (FR5). Totals are accumulated in the same loop so the
/// widget renders them without a duplicate pass (CQ-2).
///
/// FR5 shipping split: for a `payment_transaction` inflow with
/// `shippingAmount > 0`, the sale category keeps `amount − shippingAmount`
/// and the `busShipping` category receives `shippingAmount` (counted as a
/// separate row contribution). The split matches the backend
/// `save_breakdown_snapshot` classification so the live breakdown reconciles
/// with the persisted snapshot.
CashDrawerBreakdown aggregateCashDrawerBreakdown(
    List<CashDrawerTransaction> transactions) {
  final totals = <CashDrawerBreakdownCategory, int>{
    for (final c in CashDrawerBreakdownCategory.values) c: 0,
  };
  final counts = <CashDrawerBreakdownCategory, int>{
    for (final c in CashDrawerBreakdownCategory.values) c: 0,
  };
  for (final t in transactions) {
    final c = _categoryForType(t.type, t.amount, t.shippingAmount);
    // FR5: split the shipping portion out of a payment sale inflow.
    if (c == CashDrawerBreakdownCategory.sale && t.shippingAmount > 0) {
      final salePortion = t.amount - t.shippingAmount;
      totals[CashDrawerBreakdownCategory.sale] =
          totals[CashDrawerBreakdownCategory.sale]! + salePortion;
      counts[CashDrawerBreakdownCategory.sale] =
          counts[CashDrawerBreakdownCategory.sale]! + 1;
      totals[CashDrawerBreakdownCategory.busShipping] =
          totals[CashDrawerBreakdownCategory.busShipping]! + t.shippingAmount;
      counts[CashDrawerBreakdownCategory.busShipping] =
          counts[CashDrawerBreakdownCategory.busShipping]! + 1;
      continue;
    }
    totals[c] = totals[c]! + t.amount;
    counts[c] = counts[c]! + 1;
  }
  final rows = [
    for (final c in CashDrawerBreakdownCategory.values)
      CashDrawerBreakdownRow(
        category: c,
        totalAmount: totals[c]!,
        count: counts[c]!,
      ),
  ];
  int totalIn = 0;
  int totalOut = 0;
  for (final r in rows) {
    if (r.isInflow) {
      if (r.totalAmount > 0) totalIn += r.totalAmount;
    } else {
      if (r.totalAmount < 0) totalOut += r.totalAmount.abs();
    }
  }
  return CashDrawerBreakdown(rows: rows, totalIn: totalIn, totalOut: totalOut);
}

/// Inflow group categories ("Tiền vào") in display order.
const inflowCategories = [
  CashDrawerBreakdownCategory.sale,
  CashDrawerBreakdownCategory.cashIn,
  CashDrawerBreakdownCategory.open,
];

/// Outflow group categories ("Tiền ra") in display order.
const outflowCategories = [
  CashDrawerBreakdownCategory.refund,
  CashDrawerBreakdownCategory.expense,
  CashDrawerBreakdownCategory.cashOut,
  CashDrawerBreakdownCategory.busShipping,
  CashDrawerBreakdownCategory.close,
];

/// Breakdown card widget (DG-359 Phase 1, DG-363 Phase 3/4). Renders the 8
/// category rows in two groups with per-group totals and a footer reconciling
/// inflow − outflow = expected balance.
///
/// Two modes: pass [transactions] for live aggregation (open drawer), or
/// [breakdown] for snapshot mode (closed drawer, Phase 4 / FR7 —
/// pre-built via [breakdownFromSnapshot], no /transactions request, NFR1).
/// [breakdown] wins when both are set (snapshot is source of truth).
class CashDrawerBreakdownCard extends StatelessWidget {
  const CashDrawerBreakdownCard({
    super.key,
    this.transactions,
    this.breakdown,
  });

  /// Live transaction list (open drawer). Ignored when [breakdown] is set.
  final List<CashDrawerTransaction>? transactions;

  /// Pre-aggregated breakdown (snapshot mode). When set, renders this
  /// directly without re-aggregating [transactions].
  final CashDrawerBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aggregated =
        breakdown ?? aggregateCashDrawerBreakdown(transactions ?? const []);
    final inflowRows = [
      for (final c in inflowCategories)
        aggregated.rows.firstWhere((r) => r.category == c),
    ];
    final outflowRows = [
      for (final c in outflowCategories)
        aggregated.rows.firstWhere((r) => r.category == c),
    ];
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
        CashDrawerBreakdownInflowGroup(
          rows: inflowRows,
          totalIn: aggregated.totalIn,
        ),
        const SizedBox(height: 8),
        CashDrawerBreakdownOutflowGroup(
          rows: outflowRows,
          totalOut: aggregated.totalOut,
        ),
        const Divider(height: 16),
        CashDrawerBreakdownExpectedBalanceRow(
            expected: aggregated.expectedBalance),
      ],
    );
  }
}