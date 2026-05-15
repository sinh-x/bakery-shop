import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'widgets/product_card.dart';

class ProductCatalogScreen extends ConsumerStatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  ConsumerState<ProductCatalogScreen> createState() =>
      _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends ConsumerState<ProductCatalogScreen>
    with WidgetsBindingObserver {
  bool _wasNavigatedAway = false;
  GoRouter? _goRouter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (_goRouter != router) {
      _goRouter?.routerDelegate.removeListener(_onRouteChange);
      _goRouter = router;
      _goRouter?.routerDelegate.addListener(_onRouteChange);
    }
  }

  @override
  void dispose() {
    _goRouter?.routerDelegate.removeListener(_onRouteChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(productsProvider);
      ref.invalidate(categoriesProvider);
    }
  }

  void _onRouteChange() {
    if (!mounted) return;
    final path = GoRouterState.of(context).uri.path;
    if (path == '/products' && _wasNavigatedAway) {
      _wasNavigatedAway = false;
      ref.invalidate(productsProvider);
      ref.invalidate(categoriesProvider);
    } else if (path != '/products') {
      _wasNavigatedAway = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text(VN.tabProducts)),
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
    final productsAsync = ref.watch(productsProvider);
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
                  ref.invalidate(productsProvider);
                  ref.invalidate(categoriesProvider);
                },
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: VN.manageCategories,
                onPressed: () => context.push('/categories/manage'),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: VN.settings,
                onPressed: () => context.push('/settings'),
              ),
              IconButton(
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: VN.browseScreenTitle,
                onPressed: () => context.push('/products/browse'),
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
            loading: () => const Center(child: CircularProgressIndicator()),
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
                      ref.invalidate(productsProvider);
                      ref.invalidate(categoriesProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text(VN.retry),
                  ),
                ],
              ),
            ),
            data: (products) => _ProductTabs(
              products: products,
              inactiveProductsAsync: inactiveProductsAsync,
              categories: categories,
              baseUrl: baseUrl,
              cacheBuster: photoRefreshTick.toString(),
              onRetryInactiveProducts: () {
                ref.invalidate(inactiveProductsProvider);
              },
              onReactivateProduct: (productId) async {
                await ref
                    .read(productsProvider.notifier)
                    .reactivateProduct(productId);
              },
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
    required this.products,
    required this.inactiveProductsAsync,
    required this.categories,
    required this.baseUrl,
    required this.cacheBuster,
    required this.onRetryInactiveProducts,
    required this.onReactivateProduct,
  });

  final List<Product> products;
  final AsyncValue<List<Product>> inactiveProductsAsync;
  final List<Category> categories;
  final String baseUrl;
  final String cacheBuster;
  final VoidCallback onRetryInactiveProducts;
  final Future<void> Function(int productId) onReactivateProduct;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Product>>{};
    for (final cat in categories) {
      grouped[cat.slug] = products
          .where((p) => p.category == cat.slug)
          .toList();
    }

    return Column(
      children: [
        Expanded(
          child: TabBarView(
            children: categories.map((cat) {
              final items = grouped[cat.slug] ?? [];
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
              return Consumer(
                builder: (context, ref, _) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productsProvider);
                    ref.invalidate(categoriesProvider);
                    ref.invalidate(inactiveProductsProvider);
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) => ProductCard(
                      product: items[index],
                      photoBaseUrl: baseUrl,
                      cacheBuster: cacheBuster,
                      onTap: () => context.push('/products/${items[index].id}/edit'),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        _InactiveProductsSection(
          inactiveProductsAsync: inactiveProductsAsync,
          onReactivateProduct: onReactivateProduct,
          onRetry: onRetryInactiveProducts,
        ),
      ],
    );
  }
}

class _InactiveProductsSection extends StatelessWidget {
  const _InactiveProductsSection({
    required this.inactiveProductsAsync,
    required this.onReactivateProduct,
    required this.onRetry,
  });

  final AsyncValue<List<Product>> inactiveProductsAsync;
  final Future<void> Function(int productId) onReactivateProduct;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return inactiveProductsAsync.when(
      loading: () => const SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                VN.apiError,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text(VN.retry),
              ),
            ],
          ),
        ),
      ),
      data: (inactiveProducts) {
        if (inactiveProducts.isEmpty) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    VN.hiddenProducts,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ...inactiveProducts.map(
                    (product) => _InactiveProductTile(
                      product: product,
                      onReactivateProduct: onReactivateProduct,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InactiveProductTile extends StatelessWidget {
  const _InactiveProductTile({
    required this.product,
    required this.onReactivateProduct,
  });

  final Product product;
  final Future<void> Function(int productId) onReactivateProduct;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(product.name),
      trailing: FilledButton.tonalIcon(
        onPressed: () => onReactivateProduct(product.id),
        icon: const Icon(Icons.visibility_outlined),
        label: const Text(VN.showProduct),
      ),
    );
  }
}
