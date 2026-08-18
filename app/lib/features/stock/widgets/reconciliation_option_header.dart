import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/stock.dart';

class OptionHeader extends StatelessWidget {
  const OptionHeader({required this.option, required this.visibleChipLabels, super.key});

  final ReconciliationDraftOption option;
  final String visibleChipLabels;

  @override
  Widget build(BuildContext context) {
    final priceLineStyle = Theme.of(context).textTheme.titleSmall;
    // When a base-price option collides with a chip option at the same
    // normalized price, both headers render the same `Giá <price> - Tồn dự
    // kiến: N` line. Surface a "Giá gốc" badge when this is the base option
    // so the two lines stay visually unambiguous (DG-413 UI-1).
    final isBaseCollisionOption = option.isCollidingBaseBucket;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Giá ${formatVND(option.normalizedPrice.toDouble())} - ${StockLabels.tonDuKien}: ${option.expectedQty}',
            style: priceLineStyle?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: (priceLineStyle.fontSize ?? 14) + 1,
            ),
          ),
          if (isBaseCollisionOption)
            Text(
              OrdersLabels.giaGoc,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (visibleChipLabels.isNotEmpty)
            Text(
              '${StockLabels.nhanChip}: $visibleChipLabels',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}