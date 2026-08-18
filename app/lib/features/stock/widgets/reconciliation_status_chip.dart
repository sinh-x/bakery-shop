import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/stock.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.hasError, super.key});

  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final color = hasError ? Colors.red[700]! : Colors.green[700]!;
    final text = hasError ? StockLabels.trangThaiCoLoi : StockLabels.trangThaiOn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${StockLabels.trangThai}: $text',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}