import 'package:flutter/material.dart';

import '../../../data/models/product.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.photoBaseUrl,
    this.onTap,
    this.onLongPress,
    this.showPriceBadge = false,
  });

  final Product product;
  final String photoBaseUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showPriceBadge;

  String _displayPrice(Product product) {
    if (product.priceChips.isEmpty) {
      return formatVND(product.basePrice);
    }

    final chipMin = product.priceChips
        .map((chip) => chip.price)
        .reduce((a, b) => a < b ? a : b);
    final hasPositiveBasePrice = product.basePrice > 0;
    final minPrice =
        hasPositiveBasePrice && product.basePrice < chipMin ? product.basePrice : chipMin;

    return '${VN.priceFrom} ${formatVND(minPrice)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = categoryEmojiMap[product.category] ?? '🍰';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo fills the card
            Image.network(
              '$photoBaseUrl/api/products/${product.id}/photo',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[100],
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
            ),
            // Gradient overlay + name at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, 24, 8, showPriceBadge ? 48 : 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (product.productCode.isNotEmpty) ...[
                      _CodeBadge(code: product.productCode),
                      const SizedBox(height: 2),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        product.name,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!showPriceBadge)
                      Text(
                        _displayPrice(product),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Price badge strip at very bottom (picker mode only)
            // Card's clipBehavior handles rounded bottom corners
            if (showPriceBadge)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: theme.colorScheme.primaryContainer,
                  child: Text(
                    _displayPrice(product),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeBadge extends StatelessWidget {
  const _CodeBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
