import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/orders.dart';
/// Renders the candle-type line for an order item or work item when the
/// `candle_type` attribute is present, non-empty, and not `khong_nen`
/// (DG-371 review cycle 1 / MAJOR-2).
///
/// Shared by [OrderItemsList] (`order_items_list.dart`) and
/// [OrderWorkItemCard] (`order_work_item_card.dart`) so the candle-type
/// display logic lives in one place.
class CandleTypeLine extends StatelessWidget {
  const CandleTypeLine({
    super.key,
    required this.candleType,
  });

  /// Raw `candle_type` attribute value. When this is `null`, empty, or
  /// equal to `khong_nen`, the widget renders nothing.
  final String? candleType;

  @override
  Widget build(BuildContext context) {
    final value = candleType;
    if (value == null || value.isEmpty || value == 'khong_nen') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '${OrdersLabels.packCandles}: ${OrdersLabels.candleTypeLabel(value)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.pink.shade700,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}