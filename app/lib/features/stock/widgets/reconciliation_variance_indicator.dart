import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

class ReconciliationVarianceIndicator extends StatelessWidget {
  const ReconciliationVarianceIndicator({required this.variance, super.key});

  final int variance;

  @override
  Widget build(BuildContext context) {
    final color = variance == 0 ? Colors.green[700]! : Colors.red[700]!;
    return Text(
      '${VN.soLuongChenhLech}: ${_formatVariance(variance)}',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }

  String _formatVariance(int value) {
    if (value == 0) {
      return '0';
    }
    return value > 0 ? '+$value' : '$value';
  }
}
