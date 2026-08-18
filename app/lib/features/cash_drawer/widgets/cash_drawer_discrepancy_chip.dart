import 'package:flutter/material.dart';

import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:bakery_app/shared/labels/cash_drawer.dart';

/// Surplus / shortage / exact chip rendered next to the expected-balance
/// line in [CashDrawerHistoryCard]'s subtitle.
///
/// Extracted from `cash_drawer_history_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerDiscrepancyChip extends StatelessWidget {
  const CashDrawerDiscrepancyChip({super.key, required this.discrepancy});

  final int? discrepancy;

  @override
  Widget build(BuildContext context) {
    if (discrepancy == null) return const SizedBox.shrink();
    final value = discrepancy!;
    final label = value == 0
        ? CashDrawerLabels.cashDrawerExact
        : value > 0
            ? CashDrawerLabels.cashDrawerSurplus
            : CashDrawerLabels.cashDrawerShortage;
    final color = value == 0
        ? Colors.grey.shade700
        : value > 0
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label (${formatVND(value.toDouble())})',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}