// EXEMPT: 200-line threshold exceeded because the work item card renders
// photo thumbnails, attribute chips, and status badges in a tightly coupled
// layout that does not decompose into reusable sub-widgets.
// Reviewed 2026-07-30.
import 'package:bakery_app/shared/utils.dart' show formatVND, workItemStatusLabel;
import 'package:flutter/material.dart';

import '../../../../data/models/enum_attribute.dart';
import '../../../../data/models/order_photo.dart';
import '../../../../data/models/work_item.dart';
import 'candle_type_line.dart';
import '../enum_attribute_display.dart';
import '../order_item_markup_line.dart';
import 'order_detail_helpers.dart';
import 'order_work_item_photo_strip.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// A card showing a single work item with status, qty/price, photos, and
/// status-transition chips.
class OrderWorkItemCard extends StatelessWidget {
  const OrderWorkItemCard({
    super.key,
    required this.item,
    required this.onTransition,
    required this.photos,
    required this.baseUrl,
    required this.onTap,
    this.enumAttributes = const [],
  });

  final WorkItem item;
  final ValueChanged<String>? onTransition;
  final List<OrderPhoto> photos;
  final String baseUrl;
  final VoidCallback? onTap;

  /// Product-defined enum attributes (e.g. `nhan_banh`) used to render
  /// `labelVi: valueVi` lines for the stored `item.attributes` selections
  /// (DG-362 Phase 3 / FR1 / AC1).
  final List<EnumAttribute> enumAttributes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = workItemStatusColors[item.status] ?? Colors.grey;
    final statusLabel = workItemStatusLabel(item.status);
    const allStatuses = [
      'pending',
      'confirmed',
      'working',
      'ready',
      'delivered',
      'cancelled',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status badge + product name + chevron
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(100)),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (item.isExtra) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.isGift
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.card_giftcard,
                            size: 10,
                            color: item.isGift ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.isGift ? OrdersLabels.giftBadge : OrdersLabels.paymentFee,
                            style: TextStyle(
                              fontSize: 9,
                              color: item.isGift ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.productName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              // Qty × price
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${item.quantity} × ${formatVND(item.unitPrice)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              // Markup display for trưng bày work items (DG-296 Phase 5, FR7/AC6).
              if (item.assignedPrice != null &&
                  item.assignedPrice! < item.unitPrice)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OrderItemMarkupLine(
                    unitPrice: item.unitPrice,
                    assignedPrice: item.assignedPrice,
                  ),
                ),
              // Enum attribute lines (DG-362 Phase 3 / FR1 / AC1).
              ...buildEnumAttributeLines(
                context,
                item.attributes,
                enumAttributes,
              ),
              // Birthday badge + age
              if (item.isBirthday)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Text('🎂', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 4),
                      Text(
                        item.age != null
                            ? '${OrdersLabels.birthdayWithAge} ${item.age} tuổi'
                            : OrdersLabels.birthdayWithAge,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.pink.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              // Candle type (FR4 / AC3) — shared widget (DG-371 MAJOR-2).
              CandleTypeLine(
                candleType: item.attributes['candle_type']?.toString(),
              ),
              // Notes
              if (item.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.notes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              // Per-item photos
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                OrderWorkItemPhotoStrip(photos: photos, baseUrl: baseUrl),
              ],
              // Status transition chips
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: allStatuses.map((s) {
                  final isCurrent = s == item.status;
                  final color = workItemStatusColors[s] ?? Colors.grey;
                  return FilterChip(
                    label: Text(workItemStatusLabel(s)),
                    selected: isCurrent,
                    selectedColor: color.withAlpha(40),
                    checkmarkColor: color,
                    side: BorderSide(
                      color: isCurrent ? color : Colors.grey.shade300,
                    ),
                    labelStyle: TextStyle(
                      color: isCurrent ? color : null,
                      fontWeight: isCurrent ? FontWeight.bold : null,
                      fontSize: 12,
                    ),
                    onSelected: isCurrent || onTransition == null
                        ? null
                        : (_) => onTransition!(s),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}