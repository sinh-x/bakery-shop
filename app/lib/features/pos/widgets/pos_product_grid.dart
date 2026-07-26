import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/price_chip.dart';
import '../../../data/models/product.dart';
import '../../../data/api/api_client.dart';
import '../../../providers/pos_provider.dart';
import '../../../providers/products_provider.dart';
import '../../orders/utils/trung_bay_inventory_extensions.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/utils/product_photo_url.dart';

/// 2-column product grid with stock badges for POS screen.
class PosProductGrid extends ConsumerWidget {
  const PosProductGrid({
    super.key,
    required this.products,
    this.showOutOfStockProducts = false,
    this.shrinkWrap = false,
    this.physics,
    this.padding = const EdgeInsets.all(8),
  });

  final List<Product> products;
  final bool showOutOfStockProducts;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(posCartProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);

    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
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
          cacheBuster: photoRefreshTick.toString(),
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
    }
  }

  void _showChipPickerDialog(
    BuildContext context,
    WidgetRef ref,
    Product product,
    bool isOutOfStock,
  ) {
    final theme = Theme.of(context);
    final options = _posChipOptions(
      product,
      showOutOfStockProducts: showOutOfStockProducts,
    );
    final isTrungBay = product.isTrungBay;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final defaultOption = options.isNotEmpty
            ? options.reduce((a, b) => a.price <= b.price ? a : b)
            : null;
        final defaultPrice = defaultOption?.price ?? product.basePrice;

        int? selectedChipId = defaultOption?.backendChipId;
        int? selectedChipUiId = defaultOption?.uiId;
        String? selectedChipLabel = defaultOption?.cartLabel;
        double selectedPrice = defaultPrice;
        // Assigned price (COGS anchor) — only tracked for trưng bày markup.
        // For non-trưng bày it stays null so backend falls back to unitPrice.
        double assignedPrice = isTrungBay ? defaultPrice : 0;
        final priceCtrl = TextEditingController(
          text: isTrungBay
              ? (defaultPrice / 1000).toInt().toString()
              : defaultPrice.toInt().toString(),
        );
        String? floorWarning;

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
                  if (options.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: options.map((option) {
                        final isSelected = selectedChipUiId == option.uiId;
                        return ChoiceChip(
                          label: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${option.label} · ${formatVND(option.price)}',
                              ),
                              Text(
                                posStockStatusLabel(option.stockQty),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: option.stockQty > 0
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              selectedChipUiId = option.uiId;
                              selectedChipId = option.backendChipId;
                              selectedChipLabel = option.cartLabel;
                              selectedPrice = option.price;
                              if (isTrungBay) {
                                // Selecting a chip resets both the assigned
                                // (COGS anchor) and selling price to the chip
                                // price — markup is applied upward from there.
                                assignedPrice = option.price;
                                priceCtrl.text =
                                    (option.price / 1000).toInt().toString();
                                floorWarning = null;
                              } else {
                                priceCtrl.text =
                                    option.price.toInt().toString();
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isTrungBay) ...[
                    // "Giá gốc" — non-editable assigned price (COGS anchor).
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${VN.giaGoc}: ${formatVND(assignedPrice)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // "Giá bán" — editable selling price (markup). Entry is in
                    // thousands of đồng, same style as the transaction amount
                    // input (DG-296 Phase 3, FR1).
                    TextFormField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                        labelText: VN.giaBan,
                        helperText: VN.markupThousandsHint,
                        border: OutlineInputBorder(),
                        suffixText: ',000đ',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final thousands = int.tryParse(v.trim());
                        if (thousands == null) {
                          setState(() => floorWarning = null);
                          return;
                        }
                        final selling = thousands.toDouble() * 1000;
                        setState(() {
                          selectedPrice = selling;
                          final matchesOption = options.any(
                            (option) =>
                                option.uiId == selectedChipUiId &&
                                option.price == selling,
                          );
                          if (!matchesOption) {
                            selectedChipUiId = null;
                            selectedChipId = null;
                            selectedChipLabel = null;
                          }
                          // Price floor: selling price cannot go below the
                          // assigned price (FR3). Clamp + warn.
                          if (selling < assignedPrice) {
                            floorWarning = VN.markupFloorWarning;
                          } else {
                            floorWarning = null;
                          }
                        });
                      },
                    ),
                    if (floorWarning != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          floorWarning!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ] else
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
                            final matchesOption = options.any(
                              (option) =>
                                  option.uiId == selectedChipUiId &&
                                  option.price == parsed,
                            );
                            if (!matchesOption) {
                              selectedChipUiId = null;
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
                  // Price floor enforcement (FR3/AC3): clamp selling price to
                  // the assigned price when staff entered a lower value.
                  if (isTrungBay && selectedPrice < assignedPrice) {
                    selectedPrice = assignedPrice;
                    // Reset chip selection to the assigned-price option (if
                    // any) since selling == assigned after clamping.
                    final match = options
                        .where((o) => o.price == assignedPrice)
                        .firstOrNull;
                    selectedChipUiId = match?.uiId;
                    selectedChipId = match?.backendChipId;
                    selectedChipLabel = match?.cartLabel;
                  }
                  Navigator.pop(dialogCtx);
                  final selectedOption = selectedChipUiId == null
                      ? null
                      : options
                            .where((option) => option.uiId == selectedChipUiId)
                            .firstOrNull;
                  final selectedStockQty = selectedOption?.stockQty;
                  final isSelectedOptionOutOfStock =
                      selectedStockQty != null && selectedStockQty <= 0;
                  final isManualBaseOutOfStock =
                      selectedOption == null && posBaseStockQty(product) <= 0;
                  final assignedForCart =
                      isTrungBay ? assignedPrice : null;
                  if (isOutOfStock ||
                      isSelectedOptionOutOfStock ||
                      isManualBaseOutOfStock) {
                    _showForceSellDialog(
                      context,
                      ref,
                      product,
                      selectedPrice: selectedPrice,
                      selectedChipId: selectedChipId,
                      selectedChipLabel: selectedChipLabel,
                      assignedPrice: assignedForCart,
                    );
                  } else {
                    ref
                        .read(posCartProvider.notifier)
                        .addItem(
                          product,
                          selectedPrice: selectedPrice,
                          selectedChipId: selectedChipId,
                          selectedChipLabel: selectedChipLabel,
                          assignedPrice: assignedForCart,
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
    double? assignedPrice,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(VN.sanPhamHetHang),
        content: const Text(VN.banAnyway),
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
                    assignedPrice: assignedPrice,
                    useInventory: false,
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
            child: const Text(VN.xacNhan),
          ),
        ],
      ),
    );
  }
}

const _basePriceOptionUiId = -1;

class _PosChipOption {
  const _PosChipOption({
    required this.uiId,
    required this.label,
    required this.cartLabel,
    required this.price,
    required this.stockQty,
    required this.backendChipId,
  });

  final int uiId;
  final String label;
  final String? cartLabel;
  final double price;
  final int stockQty;
  final int? backendChipId;
}

List<_PosChipOption> _posChipOptions(
  Product product, {
  required bool showOutOfStockProducts,
}) {
  final options = <_PosChipOption>[];
  final hasBasePriceChip = product.priceChips.any(
    (chip) => chip.price == product.basePrice,
  );

  if (!hasBasePriceChip && product.basePrice > 0) {
    final baseStock = posBaseStockQty(product);
    if (showOutOfStockProducts || baseStock > 0) {
      options.add(
        _PosChipOption(
          uiId: _basePriceOptionUiId,
          label: VN.giaCoSo,
          cartLabel: null,
          price: product.basePrice,
          stockQty: baseStock,
          backendChipId: null,
        ),
      );
    }
  }

  for (final chip in product.priceChips) {
    final displayStock = posChipDisplayStockQty(product, chip);
    if (!showOutOfStockProducts && displayStock <= 0) {
      continue;
    }
    options.add(
      _PosChipOption(
        uiId: chip.id,
        label: chip.label,
        cartLabel: chip.label,
        price: chip.price,
        stockQty: displayStock,
        backendChipId: posBackendChipIdForSelection(product, chip),
      ),
    );
  }

  return options;
}

@visibleForTesting
String posStockStatusLabel(int qty) {
  if (qty > 3) return VN.availableStock(qty);
  if (qty >= 1) return VN.lowStock(qty);
  return VN.outOfStock;
}

@visibleForTesting
int posBaseStockQty(Product product) {
  final totalStock = product.stockQty ?? 0;
  final chipStock = product.priceChips.fold<int>(
    0,
    (sum, chip) => sum + (chip.stockQty ?? 0),
  );
  final baseStock = totalStock - chipStock;
  return baseStock > 0 ? baseStock : 0;
}

@visibleForTesting
int? posBackendChipIdForSelection(Product product, PriceChip chip) {
  if (chip.price == product.basePrice) return null;
  return chip.id;
}

@visibleForTesting
int posChipDisplayStockQty(Product product, PriceChip chip) {
  final chipStock = chip.stockQty ?? 0;
  if (posBackendChipIdForSelection(product, chip) == null) {
    return chipStock + posBaseStockQty(product);
  }
  return chipStock;
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
    required this.cacheBuster,
    required this.onTap,
  });

  final Product product;
  final int stockQty;
  final int? inCartQty;
  final bool isOutOfStock;
  final String baseUrl;
  final String cacheBuster;
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
                    child: Image.network(
                      productPhotoUrl(
                        baseUrl,
                        product.id,
                        cacheBuster: cacheBuster,
                      ),
                      fit: BoxFit.cover,
                      semanticLabel: 'Ảnh sản phẩm ${product.name}',
                      errorBuilder: (_, _, _) => _buildPlaceholder(theme),
                    ),
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
