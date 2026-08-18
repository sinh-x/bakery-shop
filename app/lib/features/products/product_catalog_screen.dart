import 'package:bakery_app/shared/utils.dart' show categoryEmojiMap, categoryMap;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../data/models/category.dart';
import '../../shared/providers/auth_provider.dart';
import '../../data/providers/categories_provider.dart';
import '../../data/providers/products_provider.dart';
import '../../shared/labels/shared.dart';
import '../../shared/mixins/auto_refresh_mixin.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'widgets/product_grid_skeleton.dart';
import 'widgets/product_tabs.dart';
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
          title: const Text(SharedLabels.tabProducts),
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
            title: const Text(SharedLabels.tabProducts),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: SharedLabels.lamMoi,
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
                      child: Text(SharedLabels.openCategoryManagement),
                    ),
                  const PopupMenuItem<String>(
                    value: 'browse_catalog',
                    child: Text(SharedLabels.openCatalogBrowse),
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
            loading: () => const ProductGridSkeleton(),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    SharedLabels.apiError,
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
                    label: const Text(SharedLabels.retry),
                  ),
                ],
              ),
            ),
            data: (state) => ProductTabs(
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
