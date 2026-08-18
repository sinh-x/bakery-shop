import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/product.dart';
import '../../../data/providers/categories_provider.dart';
import '../../../data/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'product_card.dart';

/// Paginated product grid for a single catalog tab.
///
/// Renders a [ProductCard] per product and a tap-to-load footer when
/// [paginationState.hasMore]. Triggers infinite-scroll load-more when
/// the grid nears the bottom (DG-409 Phase 4).
///
/// Extracted from `product_catalog_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductGrid extends ConsumerWidget {
  const ProductGrid({
    super.key,
    required this.items,
    required this.baseUrl,
    required this.cacheBuster,
    required this.paginationState,
    required this.onLoadMore,
  });

  final List<Product> items;
  final String baseUrl;
  final String cacheBuster;
  final ProductPaginationState paginationState;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // DG-409 Phase 4: infinite-scroll — trigger load-more when near the
    // bottom of the grid. The global pagination state drives the next-page
    // fetch (more products across ALL categories), so the active tab fills
    // up as pages arrive.
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(productsPaginationProvider);
        ref.invalidate(productsProvider);
        ref.invalidate(categoriesProvider);
        ref.invalidate(inactiveProductsProvider);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 300 &&
              paginationState.hasMore &&
              !paginationState.isLoadingMore) {
            onLoadMore();
          }
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: items.length + (paginationState.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == items.length) {
              // CQ-9 (review-auto): explicit tap-to-load footer. The
              // perpetual spinner dead-end is replaced by a tappable
              // "Tải thêm" cell that shows a spinner ONLY while
              // `isLoadingMore`. Tapping triggers `onLoadMore` (still also
              // fired by the scroll-end listener above for infinite-scroll
              // parity).
              if (paginationState.isLoadingMore) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                );
              }
              return InkWell(
                onTap: onLoadMore,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.expand_more, size: 28),
                      SizedBox(height: 4),
                      Text(SharedLabels.loadMore),
                    ],
                  ),
                ),
              );
            }
            return ProductCard(
              product: items[index],
              photoBaseUrl: baseUrl,
              cacheBuster: cacheBuster,
              onTap: () => context.push('/products/${items[index].id}/edit'),
            );
          },
        ),
      ),
    );
  }
}