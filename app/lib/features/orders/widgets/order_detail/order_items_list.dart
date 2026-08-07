import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/enum_attribute.dart';
import '../../../../data/models/order.dart';
import '../../../../data/models/order_item.dart';
import '../../../../data/models/product.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/utils/product_photo_url.dart';
import 'candle_type_line.dart';
import '../enum_attribute_display.dart';
import '../order_item_markup_line.dart';
import '../section_header.dart';

/// Builds the list of regular (non-extra) order items, each row showing
/// product photo (when available), product name, qty × unit price, markup,
/// enum attributes, birthday/age/candle/notes info, and cash info.
class OrderItemsList extends StatelessWidget {
  const OrderItemsList({
    super.key,
    required this.order,
    required this.enumAttributesFor,
    required this.products,
    required this.baseUrl,
  });

  final Order order;
  final List<EnumAttribute> Function(String productId) enumAttributesFor;

  /// Product catalogue used to resolve each item's product photo
  /// (`product.photoPath`) for the thumbnail shown next to cake items
  /// (DG-371 Phase 2 / FR1 / AC1).
  final List<Product> products;

  /// API base URL used to build product photo URLs
  /// (`$baseUrl/api/products/<id>/photo`).
  final String baseUrl;

  /// Resolve the [Product] matching [productId] (by id or productCode).
  Product? _productFor(String productId) {
    if (productId.isEmpty || products.isEmpty) return null;
    for (final p in products) {
      if (p.id.toString() == productId || p.productCode == productId) {
        return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(VN.products),
        ...order.items.where((item) => !item.isExtra).map(
              (item) => _OrderItemRow(
                item: item,
                product: _productFor(item.productId),
                baseUrl: baseUrl,
                enumAttributes: enumAttributesFor(item.productId),
                isExtra: false,
              ),
            ),
        if (order.items.any((item) => item.isExtra)) ...[
          const SizedBox(height: 12),
          const SectionHeader(VN.extras),
          ...order.items.where((item) => item.isExtra).map(
                (item) => _OrderItemRow(
                  item: item,
                  product: _productFor(item.productId),
                  baseUrl: baseUrl,
                  enumAttributes: enumAttributesFor(item.productId),
                  isExtra: true,
                ),
              ),
        ],
      ],
    );
  }
}

/// A single order item row shared by regular items and extras.
///
/// Renders the product photo thumbnail (40×40 via `CachedNetworkImage`) when
/// the resolved product has a non-empty `photoPath`, plus product name,
/// qty × unit price, markup, enum attribute lines, birthday/age/candle
/// info, notes, and cash info (DG-371 Phase 2 / FR1–FR3 / AC1–AC2).
class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.item,
    required this.product,
    required this.baseUrl,
    required this.enumAttributes,
    required this.isExtra,
  });

  final OrderItem item;
  final Product? product;
  final String baseUrl;
  final List<EnumAttribute> enumAttributes;
  final bool isExtra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = product != null && product!.photoPath.isNotEmpty;
    final photoUrl = hasPhoto
        ? productPhotoUrl(baseUrl, product!.id)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product photo thumbnail (FR1 / AC1) — only when photoPath is set.
          if (hasPhoto) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 40,
                  height: 40,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (context, url, error) => const SizedBox(
                  width: 40,
                  height: 40,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
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
                  enumAttributes,
                ),
                // Birthday badge + age (FR2 / AC1).
                if (item.isBirthday)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Text('🎂', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                        Text(
                          item.age != null
                              ? '${VN.birthdayWithAge} ${item.age} tuổi'
                              : VN.birthdayWithAge,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.pink.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Candle type (FR2 / AC2) — shared widget (DG-371 MAJOR-2).
                CandleTypeLine(
                  candleType: item.attributes['candle_type']?.toString(),
                ),
                // Notes (FR2 / AC1).
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
                // Cash info (F27)
                if (item.attributes['cash_amount'] != null &&
                    item.attributes['cash_amount'].toString().isNotEmpty &&
                    item.attributes['cash_amount'].toString() != '0') ...[
                  const SizedBox(height: 2),
                  Text(
                    '${VN.rutTien}: ${formatVND((int.tryParse(item.attributes['cash_amount'].toString()) ?? 0).toDouble())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.attributes['cash_fee'] != null &&
                      item.attributes['cash_fee'].toString().isNotEmpty &&
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
          if (isExtra && item.isGift)
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
    );
  }
}