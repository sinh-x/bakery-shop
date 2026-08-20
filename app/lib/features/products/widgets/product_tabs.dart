import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../../data/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'product_grid.dart';

/// Tabbed body of the product catalog screen.
///
/// Renders a per-category [TabBarView] of [ProductGrid]s, plus a
/// show-inactive switch and inline error row for the inactive-products
/// async value.
///
/// Extracted from `product_catalog_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductTabs extends StatelessWidget {
  const ProductTabs({
    super.key,
    required this.state,
    required this.inactiveProductsAsync,
    required this.categories,
    required this.baseUrl,
    required this.cacheBuster,
    required this.showInactiveProducts,
    required this.onShowInactiveProductsChanged,
    required this.onRetryInactiveProducts,
    required this.onLoadMore,
  });

  final ProductPaginationState state;
  final AsyncValue<List<Product>> inactiveProductsAsync;
  final List<Category> categories;
  final String baseUrl;
  final String cacheBuster;
  final bool showInactiveProducts;
  final ValueChanged<bool> onShowInactiveProductsChanged;
  final VoidCallback onRetryInactiveProducts;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final products = state.loaded;
    final grouped = <String, List<Product>>{};
    for (final cat in categories) {
      grouped[cat.slug] = products
          .where((p) => p.category == cat.slug)
          .toList();
    }

    final inactiveGrouped = inactiveProductsAsync.maybeWhen(
      data: (inactiveProducts) {
        final grouped = <String, List<Product>>{};
        for (final cat in categories) {
          grouped[cat.slug] = inactiveProducts
              .where((p) => p.category == cat.slug)
              .toList();
        }
        return grouped;
      },
      orElse: () => <String, List<Product>>{},
    );

    return Column(
      children: [
        SwitchListTile(
          dense: true,
          value: showInactiveProducts,
          onChanged: onShowInactiveProductsChanged,
          secondary: Icon(
            showInactiveProducts
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          title: const Text(ProductsLabels.hiddenProducts),
        ),
        if (showInactiveProducts)
          inactiveProductsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(SharedLabels.apiError)),
                  TextButton(
                    onPressed: onRetryInactiveProducts,
                    child: const Text(SharedLabels.retry),
                  ),
                ],
              ),
            ),
            data: (_) => const SizedBox.shrink(),
          ),
        Expanded(
          child: TabBarView(
            children: categories.map((cat) {
              final items = [
                ...(grouped[cat.slug] ?? const <Product>[]),
                if (showInactiveProducts)
                  ...(inactiveGrouped[cat.slug] ?? const <Product>[]),
              ];
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    ProductsLabels.noProducts,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  ),
                );
              }
              return ProductGrid(
                items: items,
                baseUrl: baseUrl,
                cacheBuster: cacheBuster,
                paginationState: state,
                onLoadMore: onLoadMore,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}