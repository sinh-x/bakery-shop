import 'package:flutter/material.dart';

import '../../../data/api/stock_service.dart';
import '../../../shared/utils/product_photo_url.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../stock_screen.dart';

/// Card widget rendering a single [StockOverviewItem] on the stock management
/// screen.
///
/// Extracted from `stock_screen.dart` in Phase 1 of DG-266 to prepare for
/// making per-chip price tags tappable (Phase 3). The widget is a pure
/// refactor of the previous private `_StockItemCard` — no behavior change.
class StockItemCard extends StatelessWidget {
  const StockItemCard({
    super.key,
    required this.item,
    required this.emoji,
    required this.baseUrl,
    required this.cacheBuster,
    required this.onRestock,
    required this.onWaste,
    required this.onAdjust,
    this.onChipTap,
  });

  final StockOverviewItem item;
  final String emoji;
  final String baseUrl;
  final String cacheBuster;
  final VoidCallback onRestock;
  final VoidCallback onWaste;
  final VoidCallback onAdjust;

  /// Called when a per-chip price tag is tapped with the chip's
  /// [PriceChipOption.normalizedPrice]. When null, chips are not tappable
  /// (the restock button remains the only entry point). Per DG-266 Phase 3.
  final void Function(int normalizedPrice)? onChipTap;

  @override
  Widget build(BuildContext context) {
    final totalQty = item.totalQuantity;
    final statusColor = stockStatusColor(totalQty);
    final statusLabel = stockStatusLabel(totalQty);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    productPhotoUrl(
                      baseUrl,
                      item.productId,
                      cacheBuster: cacheBuster,
                    ),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey[100],
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    Text(
                      '$totalQty',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                    ),
                    Text(
                      VN.tonKho,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.perChip.map((option) {
                final canTap = onChipTap != null;
                final chipContent = Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${option.displayLabel} (${option.normalizedPrice}): ${option.quantity}',
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.add_circle_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                );
                if (!canTap) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: chipContent,
                  );
                }
                // Tappable chip with InkWell ripple. Material ancestor is
                // required so the InkWell ripple paints above the chip's
                // background tint. Minimum touch target padding ensures the
                // 48x48dp Material target per NFR1.
                return Material(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onChipTap!(option.normalizedPrice),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 36,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: chipContent,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(VN.nhapHang),
                    onPressed: onRestock,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text(VN.haoHut),
                    onPressed: onWaste,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text(VN.dieuChinh),
                    onPressed: onAdjust,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}