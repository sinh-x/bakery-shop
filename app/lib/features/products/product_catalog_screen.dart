import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../shared/providers/auth_provider.dart';
import '../../data/providers/categories_provider.dart';
import '../../data/providers/products_provider.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/product_card.dart';

class ProductCatalogScreen extends ConsumerStatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  ConsumerState<ProductCatalogScreen> createState() =>
      _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends ConsumerState<ProductCatalogScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  bool _showInactiveProducts = false;

  @override
  String screenRoutePath() => '/products';

  @override
  void invalidateProviders() {
    ref.invalidate(productsProvider);
    ref.invalidate(categoriesProvider);
  }

  @override
  void initState() {
    super.initState();
    initAutoRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    setupAutoRefreshRouteListener();
  }

  @override
  void dispose() {
    disposeAutoRefresh();
    super.dispose();
  }

  void _onAppBarMenuSelected(BuildContext context, String value) {
    switch (value) {
      case 'manage_categories':
        context.push('/categories/manage');
        return;
      case 'settings':
        context.push('/settings');
        return;
      case 'browse_catalog':
        context.push('/products/browse');
        return;
      default:
        assert(() {
          debugPrint('Unknown product catalog app bar menu action: $value');
          return true;
        }());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          title: const Text(VN.tabProducts),
          actions: const [AppBarOverflowMenu()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, st) => _buildWithCategories(
        context,
        ref,
        categoryMap.entries
            .map(
              (e) => Category(
                id: 0,
                slug: e.key,
                name: e.value,
                codePrefix: '',
                active: 1,
              ),
            )
            .toList(),
      ),
      data: (categories) => _buildWithCategories(
        context,
        ref,
        categories.where((c) => c.active == 1).toList(),
      ),
    );
  }

  Widget _buildWithCategories(
    BuildContext context,
    WidgetRef ref,
    List<Category> categories,
  ) {
    // DG-409 Phase 4 (FR10, AC3): paginated active products. The legacy
    // productsProvider stays for non-catalog consumers (POS, order edit,
    // cake queue, product picker); the catalog screen reads the paginated
    // state so 200+ products load in pages of 50 with load-more.
    final productsAsync = ref.watch(productsPaginationProvider);
    final inactiveProductsAsync = ref.watch(inactiveProductsProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);

    return DefaultTabController(
      length: categories.length,
      child: Builder(
        builder: (innerContext) => Scaffold(
          appBar: AppBar(
            title: const Text(VN.tabProducts),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: VN.lamMoi,
                onPressed: () {
                  ref.invalidate(productsPaginationProvider);
                  ref.invalidate(productsProvider);
                  ref.invalidate(categoriesProvider);
                },
              ),
              AppBarOverflowMenu(
                onSelected: (value) => _onAppBarMenuSelected(context, value),
                items: [
                  if (ref.watch(authProvider).isAdmin)
                    const PopupMenuItem<String>(
                      value: 'manage_categories',
                      child: Text(VN.openCategoryManagement),
                    ),
                  const PopupMenuItem<String>(
                    value: 'browse_catalog',
                    child: Text(VN.openCatalogBrowse),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: categories.map((cat) {
                final icon = cat.icon.isNotEmpty
                    ? cat.icon
                    : (categoryEmojiMap[cat.slug] ?? '');
                return Tab(text: '$icon ${cat.name}');
              }).toList(),
            ),
          ),
          body: productsAsync.when(
            loading: () => const _ProductGridSkeleton(),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    VN.apiError,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(productsPaginationProvider);
                      ref.invalidate(productsProvider);
                      ref.invalidate(categoriesProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text(VN.retry),
                  ),
                ],
              ),
            ),
            data: (state) => _ProductTabs(
              state: state,
              inactiveProductsAsync: inactiveProductsAsync,
              categories: categories,
              baseUrl: baseUrl,
              cacheBuster: photoRefreshTick.toString(),
              showInactiveProducts: _showInactiveProducts,
              onShowInactiveProductsChanged: (value) {
                setState(() => _showInactiveProducts = value);
              },
              onRetryInactiveProducts: () {
                ref.invalidate(inactiveProductsProvider);
              },
              onLoadMore: () =>
                  ref.read(productsPaginationProvider.notifier).loadMore(),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              final idx = DefaultTabController.of(innerContext).index;
              final slug = categories.isNotEmpty
                  ? categories[idx].slug
                  : 'banh_kem';
              innerContext.push('/products/new?category=$slug');
            },
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class _ProductTabs extends StatelessWidget {
  const _ProductTabs({
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
          title: const Text(VN.hiddenProducts),
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
                  const Expanded(child: Text(VN.apiError)),
                  TextButton(
                    onPressed: onRetryInactiveProducts,
                    child: const Text(VN.retry),
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
                    VN.noProducts,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  ),
                );
              }
              return _ProductGrid(
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

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({
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

/// Loading skeleton shown while the first product page loads (DG-409
/// Phase 4 / loading indicators).
class _ProductGridSkeleton extends StatelessWidget {
  const _ProductGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: 6,
      itemBuilder: (context, _) => const Card(
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}
