/// Shared row widgets for the cash drawer breakdown card (DG-363 Phase 3).
///
/// Holds the per-category row, the count/amount header, and the per-group
/// total row used by both the inflow and outflow groups. Extracted from
/// `cash_drawer_breakdown_card.dart` per NFR3 (file ≤ 300 lines).
library;

import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND;
import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'cash_drawer_breakdown_card.dart';

/// Column header row shown once at the top of each group. The count column
/// header ("SL") is right-aligned to match the per-row count cell.
class CashDrawerBreakdownHeaderRow extends StatelessWidget {
  const CashDrawerBreakdownHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text('', style: theme.textTheme.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: Text('', style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              CashDrawerLabels.cashDrawerBreakdownCount,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-category row: label, signed colored amount, and count.
///
/// Inflow rows render `+amount` in green; outflow rows render `-amount` in
/// red (theme `colorScheme.error`). Zero amounts render `0đ` in the default
/// on-surface color so an empty category is not mistaken for an inflow.
class CashDrawerBreakdownRowWidget extends StatelessWidget {
  const CashDrawerBreakdownRowWidget({super.key, required this.row});

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
            child: Text(labelForCategory(row.category),
                style: theme.textTheme.bodyMedium),
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

/// Per-group total row (inflow total or outflow total). Inflow totals render
/// green `+`; outflow totals render red `−`. Zero totals render without a sign
/// prefix in the default color.
class CashDrawerBreakdownGroupTotalRow extends StatelessWidget {
  const CashDrawerBreakdownGroupTotalRow({
    super.key,
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
    final color = amount == 0
        ? null
        : inflow
            ? Colors.green.shade700
            : theme.colorScheme.error;
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

/// Expected-balance footer row: "Số dư dự kiến" = inflow − outflow (FR3/AC3).
/// Rendered at the bottom of the breakdown card, below the two group totals.
class CashDrawerBreakdownExpectedBalanceRow extends StatelessWidget {
  const CashDrawerBreakdownExpectedBalanceRow({super.key, required this.expected});

  final int expected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            CashDrawerLabels.cashDrawerBreakdownExpected,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            formatVND(expected.toDouble()),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}