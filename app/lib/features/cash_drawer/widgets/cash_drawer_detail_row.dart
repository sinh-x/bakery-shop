import 'package:flutter/material.dart';

import 'package:bakery_app/shared/utils.dart' show formatVND;

/// Label/value row rendered inside [CashDrawerHistoryCard]'s expansion body.
///
/// Extracted from `cash_drawer_history_list.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerDetailRow extends StatelessWidget {
  const CashDrawerDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            formatVND(value.toDouble()),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: emphasize ? FontWeight.bold : null,
              color: value < 0 ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}