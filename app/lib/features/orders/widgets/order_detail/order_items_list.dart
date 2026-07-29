import 'package:flutter/material.dart';

import '../../../../data/models/enum_attribute.dart';
import '../../../../data/models/order.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import '../enum_attribute_display.dart';
import '../order_item_markup_line.dart';
import '../section_header.dart';

/// Builds the list of regular (non-extra) order items, each row showing
/// product name, qty × unit price, markup, enum attributes, and cash info.
class OrderItemsList extends StatelessWidget {
  const OrderItemsList({
    super.key,
    required this.order,
    required this.enumAttributesFor,
  });

  final Order order;
  final List<EnumAttribute> Function(String productId) enumAttributesFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(VN.products),
        ...order.items.where((item) => !item.isExtra).map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            '${item.quantity} × ${formatVND(item.unitPrice)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          // Markup display for trưng bày items (DG-296 Phase 5, FR7/AC6).
                          OrderItemMarkupLine(
                            unitPrice: item.unitPrice,
                            assignedPrice: item.assignedPrice,
                          ),
                          // Enum attribute display (DG-092 F7 / AC-6)
                          ...buildEnumAttributeLines(
                            context,
                            item.attributes,
                            enumAttributesFor(item.productId),
                          ),
                          // Cash info (F27)
                          if (item.attributes['cash_amount'] != null &&
                              item.attributes['cash_amount']
                                  .toString()
                                  .isNotEmpty &&
                              item.attributes['cash_amount'].toString() !=
                                  '0') ...[
                            const SizedBox(height: 2),
                            Text(
                              '${VN.rutTien}: ${formatVND((int.tryParse(item.attributes['cash_amount'].toString()) ?? 0).toDouble())}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (item.attributes['cash_fee'] != null &&
                                item.attributes['cash_fee']
                                    .toString()
                                    .isNotEmpty &&
                                item.attributes['cash_fee'].toString() != '0')
                              Text(
                                '${VN.phiRutTien}: ${formatVND((int.tryParse(item.attributes['cash_fee'].toString()) ?? 0).toDouble())}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.green.shade700,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      formatVND(item.quantity * item.unitPrice),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (order.items.any((item) => item.isExtra)) ...[
          const SizedBox(height: 12),
          const SectionHeader(VN.extras),
          ...order.items.where((item) => item.isExtra).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              '${item.quantity} × ${formatVND(item.unitPrice)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            // Markup display for trưng bày extras (DG-296 Phase 5, FR7/AC6).
                            OrderItemMarkupLine(
                              unitPrice: item.unitPrice,
                              assignedPrice: item.assignedPrice,
                            ),
                            ...buildEnumAttributeLines(
                              context,
                              item.attributes,
                              enumAttributesFor(item.productId),
                            ),
                          ],
                        ),
                      ),
                      if (item.isGift)
                        Text(
                          VN.giftBadge,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Text(
                          formatVND(item.quantity * item.unitPrice),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
  }
}