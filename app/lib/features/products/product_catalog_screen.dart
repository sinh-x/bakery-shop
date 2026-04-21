import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/product_card.dart';

class ProductCatalogScreen extends ConsumerStatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  ConsumerState<ProductCatalogScreen> createState() =>
      _ProductCatalogScreenState();
}

class _ProductCatalogScreenState
    extends ConsumerState<ProductCatalogScreen>
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
            .map((e) => Category(
                  id: 0,
                  slug: e.key,
                  name: e.value,
                  codePrefix: '',
                  active: 1,
                ))
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
    final baseUrl = ref.watch(apiBaseUrlProvider);

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
              categories: categories,
              baseUrl: baseUrl,
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
    required this.categories,
    required this.baseUrl,
  });

  final List<Product> products;
  final List<Category> categories;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Product>>{};
    for (final cat in categories) {
      grouped[cat.slug] = products.where((p) => p.category == cat.slug).toList();
    }

    return TabBarView(
      children: categories.map((cat) {
        final items = grouped[cat.slug] ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              VN.noProducts,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          );
        }
        return Consumer(
          builder: (context, ref, _) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(productsProvider);
              ref.invalidate(categoriesProvider);
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
                onTap: () =>
                    context.push('/products/${items[index].id}/edit'),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}