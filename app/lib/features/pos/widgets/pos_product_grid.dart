// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product.dart';
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
    final hasPriceChips = product.priceChips.isNotEmpty;

    if (hasPriceChips) {
      _showChipPickerDialog(context, ref, product, isOutOfStock);
    } else if (isOutOfStock) {
      _showForceSellDialog(context, ref, product);
    } else {
      ref.read(posCartProvider.notifier).addItem(product);
      showTopSnackBar(context, '${product.name} đã thêm vào giỏ');
    }
  }

  void _showChipPickerDialog(
    BuildContext context,
    WidgetRef ref,
    Product product,
    bool isOutOfStock,
  ) {
    final theme = Theme.of(context);
    final chips = product.priceChips;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final defaultPrice = chips.isNotEmpty
            ? chips.map((c) => c.price).reduce((a, b) => a < b ? a : b)
            : product.basePrice;

        int? selectedChipId;
        String? selectedChipLabel;
        double selectedPrice = defaultPrice;
        final priceCtrl = TextEditingController(
          text: defaultPrice.toInt().toString(),
        );

        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(
              product.name,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (chips.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: chips.map((chip) {
                        final isSelected = selectedChipId == chip.id;
                        return ChoiceChip(
                          label: Text(
                            '${chip.label} · ${formatVND(chip.price)}',
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              selectedChipId = chip.id;
                              selectedChipLabel = chip.label;
                              selectedPrice = chip.price;
                              priceCtrl.text = chip.price.toInt().toString();
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                      labelText: VN.itemPrice,
                      border: OutlineInputBorder(),
                      suffixText: 'đ',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final parsed = double.tryParse(v.trim());
                      if (parsed != null) {
                        setState(() {
                          selectedPrice = parsed;
                          final matchesChip = chips.any(
                            (c) => c.id == selectedChipId && c.price == parsed,
                          );
                          if (!matchesChip) {
                            selectedChipId = null;
                            selectedChipLabel = null;
                          }
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text(VN.cancel),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  if (isOutOfStock) {
                    _showForceSellDialog(
                      context,
                      ref,
                      product,
                      selectedPrice: selectedPrice,
                      selectedChipId: selectedChipId,
                      selectedChipLabel: selectedChipLabel,
                    );
                  } else {
                    ref
                        .read(posCartProvider.notifier)
                        .addItem(
                          product,
                          selectedPrice: selectedPrice,
                          selectedChipId: selectedChipId,
                          selectedChipLabel: selectedChipLabel,
                        );
                    final labelSuffix = selectedChipLabel != null
                        ? ' ($selectedChipLabel)'
                        : '';
                    showTopSnackBar(
                      context,
                      '${product.name}$labelSuffix đã thêm vào giỏ',
                    );
                  }
                },
                child: const Text('Thêm'),
              ),
            ],
          ),
        );
      },
    );
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
              ref
                  .read(posCartProvider.notifier)
                  .addItem(
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

@visibleForTesting
String posStockStatusLabel(int qty) {
  if (qty > 3) return VN.availableStock(qty);
  if (qty >= 1) return VN.lowStock(qty);
  return VN.outOfStock;
}

@visibleForTesting
IconData posStockStatusIcon(int qty) {
  if (qty > 3) return Icons.check_circle;
  if (qty >= 1) return Icons.warning_amber;
  return Icons.remove_circle;
}

class _ProductPosCard extends StatelessWidget {
  const _ProductPosCard({
    required this.product,
    required this.stockQty,
    required this.inCartQty,
    required this.isOutOfStock,
    required this.baseUrl,
    required this.onTap,
  });

  final Product product;
  final int stockQty;
  final int? inCartQty;
  final bool isOutOfStock;
  final String baseUrl;
  final VoidCallback onTap;

  String _displayPrice(Product product) {
    if (product.priceChips.isEmpty) {
      return formatVND(product.basePrice);
    }

    final chipMin = product.priceChips
        .map((chip) => chip.price)
        .reduce((a, b) => a < b ? a : b);
    final hasPositiveBasePrice = product.basePrice > 0;
    final minPrice = hasPositiveBasePrice && product.basePrice < chipMin
        ? product.basePrice
        : chipMin;

    return '${VN.priceFrom} ${formatVND(minPrice)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: isOutOfStock ? 0.5 : 1.0,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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
                            semanticLabel: 'Ảnh sản phẩm ${product.name}',
                            errorBuilder: (_, _, _) => _buildPlaceholder(theme),
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
                                _displayPrice(product),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              _buildStockBadge(stockQty),
                            ],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
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
      child: Icon(Icons.cake, size: 40, color: theme.colorScheme.outline),
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

    final label = posStockStatusLabel(qty);
    final icon = posStockStatusIcon(qty);

    return Semantics(
      label: 'Tồn kho: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
