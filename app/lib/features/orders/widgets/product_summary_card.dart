import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/models/order_draft.dart';
import '../utils/trung_bay_inventory_extensions.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Product summary card shown on Stage 2/3/4 of the order wizard.
///
/// Displays per-item photo thumbnails, notes, quantity, unit price, line
/// total, and attributes (birthday age, rut tien, useInventory, price chip
/// label) so the user can verify correctness before submitting.
class ProductSummaryCard extends StatelessWidget {
  const ProductSummaryCard({super.key, required this.items});

  final List<DraftOrderItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final regularItems = items.where((i) => !i.isExtra).toList();
    final extraItems = items.where((i) => i.isExtra).toList();
    final total = regularItems.fold<double>(
      0,
      (sum, i) => sum + i.unitPrice * i.quantity,
    );

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              OrdersLabels.summaryProducts,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _buildRow(
              theme,
              VN.products,
              OrdersLabels.productCount(regularItems.length + extraItems.length),
            ),
            ...regularItems.map((item) => _buildItemBlock(theme, item)),
            if (extraItems.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildRow(theme, VN.extras, OrdersLabels.extraCount(extraItems.length)),
              ...extraItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 2),
                  child: Text(
                    '${item.product.name} x${item.quantity}${item.isGift ? ' (${VN.tangKem})' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            _buildRow(theme, VN.total, formatVND(total)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemBlock(ThemeData theme, DraftOrderItem item) {
    final cashAmount = int.tryParse(
      item.attributes['cash_amount']?.toString() ?? '',
    );
    final cashFee = int.tryParse(
      item.attributes['cash_fee']?.toString() ?? '',
    );
    final hasRutTien = item.attributes['rut_tien']?.toString() == 'true' &&
        cashAmount != null &&
        cashAmount > 0;
    final usesInventory = item.attributes.useInventory;
    final priceChipLabel = _resolvePriceChipLabel(item);

    final attributeLines = <String>[
      if (item.notes.isNotEmpty) '${VN.notes}: ${item.notes}',
      if (item.isBirthday && item.age.isNotEmpty)
        '${VN.birthdayWithAge}: ${item.age}',
      if (usesInventory) VN.useInventory,
      if (priceChipLabel != null) '${VN.priceChipLabel}: $priceChipLabel',
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.pendingPhotos.isNotEmpty) _buildPhotoStrip(theme, item),
          Text(
            '${item.product.name} x${item.quantity} — ${formatVND(item.unitPrice * item.quantity)}',
            style: theme.textTheme.bodySmall,
          ),
          for (final line in attributeLines)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
          if (hasRutTien) ...[
            Text(
              '  ${VN.rutTien}: ${formatVND(cashAmount.toDouble())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            if (cashFee != null && cashFee > 0)
              Text(
                '  ${VN.phiRutTien}: ${formatVND(cashFee.toDouble())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoStrip(ThemeData theme, DraftOrderItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: item.pendingPhotos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final xfile = item.pendingPhotos[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(xfile.path),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 56,
                  height: 56,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _resolvePriceChipLabel(DraftOrderItem item) {
    final chipId = item.priceChipId;
    if (chipId == null) return null;
    for (final chip in item.product.priceChips) {
      if (chip.id == chipId) return chip.label;
    }
    return null;
  }

  Widget _buildRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}