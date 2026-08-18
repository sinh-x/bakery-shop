import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// The `Chưa phân loại` (uncategorized) trailing line, shown only when
/// the backend reports a positive uncategorized supplier total in the
/// cashflow-summary section.
///
/// Extracted from `cashflow_summary_section.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashflowUncategorizedLine extends StatelessWidget {
  const CashflowUncategorizedLine({super.key, required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.outline,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(SharedLabels.todaySalesCashflowUncategorized, style: style),
          Text(formatVND(amount), style: style),
        ],
      ),
    );
  }
}