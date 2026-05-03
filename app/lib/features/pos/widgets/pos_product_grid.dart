import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product.dart';
import '../../../data/models/price_chip.dart';
import '../../../data/api/api_client.dart';
import '../../../providers/pos_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// 2-column product grid with stock badges for POS screen.
class PosProductGrid extends ConsumerWidget {
  const PosProductGrid({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(posCartProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: products.length,
      itemBuilder: (context, i) {
        final product = products[i];
        final stockQty = product.stockQty ?? 0;
        final inCartQty = cart.items
            .where((c) => c.product.id == product.id)
            .fold<int>(0, (sum, item) => sum + item.quantity);
        final isOutOfStock = stockQty <= 0;

        return _ProductPosCard(
          product: product,
          stockQty: stockQty,
          inCartQty: inCartQty > 0 ? inCartQty : null,
          isOutOfStock: isOutOfStock,
          baseUrl: baseUrl,
          onTap: () => _onProductTap(context, ref, product, isOutOfStock),
          onChipTap: (chip) => _onChipTap(
            context,
            ref,
            product,
            chip,
            isOutOfStock,
          ),
        );
      },
    );
  }

  void _onProductTap(
    BuildContext context,
    WidgetRef ref,
    Product product,
    bool isOutOfStock,
  ) {
    if (isOutOfStock) {
      _showForceSellDialog(context, ref, product);
    } else {
      ref.read(posCartProvider.notifier).addItem(product);
      showTopSnackBar(context, '${product.name} đã thêm vào giỏ');
    }
  }

  void _onChipTap(
    BuildContext context,
    WidgetRef ref,
    Product product,
    PriceChip chip,
    bool isOutOfStock,
  ) {
    if (isOutOfStock) {
      _showForceSellDialog(
        context,
        ref,
        product,
        selectedPrice: chip.price,
        selectedChipId: chip.id,
        selectedChipLabel: chip.label,
      );
      return;
    }

    ref.read(posCartProvider.notifier).addItem(
      product,
      selectedPrice: chip.price,
      selectedChipId: chip.id,
      selectedChipLabel: chip.label,
    );
    showTopSnackBar(context, '${product.name} (${chip.label}) đã thêm vào giỏ');
  }

  void _showForceSellDialog(
    BuildContext context,
    WidgetRef ref,
    Product product, {
    double? selectedPrice,
    int? selectedChipId,
    String? selectedChipLabel,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(VN.sanPhamHetHang),
        content: Text(VN.banAnyway),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              ref.read(posCartProvider.notifier).addItem(
                product,
                selectedPrice: selectedPrice,
                selectedChipId: selectedChipId,
                selectedChipLabel: selectedChipLabel,
              );
              if (context.mounted) {
                showTopSnackBar(
                  context,
                  selectedChipLabel != null
                      ? '${product.name} ($selectedChipLabel) đã thêm vào giỏ (force-sell)'
                      : '${product.name} đã thêm vào giỏ (force-sell)',
                );
              }
            },
            child: Text(VN.xacNhan),
          ),
        ],
      ),
    );
  }
}

class _ProductPosCard extends StatelessWidget {
  const _ProductPosCard({
    required this.product,
    required this.stockQty,
    required this.inCartQty,
    required this.isOutOfStock,
    required this.baseUrl,
    required this.onTap,
    required this.onChipTap,
  });

  final Product product;
  final int stockQty;
  final int? inCartQty;
  final bool isOutOfStock;
  final String baseUrl;
  final VoidCallback onTap;
  final ValueChanged<PriceChip> onChipTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleChips = product.priceChips.take(6).toList();
    final hasPriceChips = visibleChips.isNotEmpty;

    return Opacity(
      opacity: isOutOfStock ? 0.5 : 1.0,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hasPriceChips ? null : onTap,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Product image
                  Expanded(
                    flex: 3,
                    child: product.photoPath.isNotEmpty
                        ? Image.network(
                            '$baseUrl/api/products/${product.id}/photo',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildPlaceholder(theme),
                          )
                        : _buildPlaceholder(theme),
                  ),

                  // Product info
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            product.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Text(
                                hasPriceChips
                                    ? 'Chọn giá'
                                    : formatVND(product.basePrice),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              _buildStockBadge(stockQty),
                            ],
                          ),
                          if (hasPriceChips)
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: visibleChips
                                  .map(
                                    (chip) => ActionChip(
                                      label: Text(
                                        '${chip.label} • ${formatVND(chip.price)}',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => onChipTap(chip),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // In-cart quantity badge
              if (inCartQty != null && inCartQty! > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'x$inCartQty',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.cake,
        size: 40,
        color: theme.colorScheme.outline,
      ),
    );
  }

  Widget _buildStockBadge(int qty) {
    Color bg;
    if (qty > 3) {
      bg = Colors.green;
    } else if (qty >= 1) {
      bg = Colors.orange;
    } else {
      bg = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        qty > 0 ? '$qty' : 'Hết',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
