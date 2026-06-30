import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/products_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../../../shared/mixins/auto_refresh_mixin.dart';
import '../../../shared/utils/category_grouping.dart';
import '../../../shared/utils/date_formatting.dart';
import '../../../shared/widgets/app_bar_overflow_menu.dart';
import '../../../shared/widgets/collapsible_category_sections.dart';
import 'widgets/pos_cart_bar.dart';
import 'widgets/pos_product_grid.dart';

/// Main POS (Point of Sale) screen — 6th bottom tab.
/// Product-first flow with 3-tap quick sale for walk-in customers.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen>
    with WidgetsBindingObserver, AutoRefreshMixin {
  String _searchQuery = '';
  bool _showOutOfStockProducts = false;
  DateTime _lastStockRefreshAt = DateTime.now();
  final CategorySectionExpansionController _sectionExpansionController =
      CategorySectionExpansionController();

  @override
  String screenRoutePath() => '/pos';

  @override
  void invalidateProviders() {
    ref.invalidate(productsProvider);
  }

  @override
  void onAutoRefreshTriggered() {
    super.onAutoRefreshTriggered();
    if (mounted) {
      setState(() => _lastStockRefreshAt = DateTime.now());
    }
  }

  List<Product> _visibleProducts(List<Product> products) {
    var result = products.where((p) => p.active == 1).toList();

    if (!_showOutOfStockProducts) {
      result = result.where((p) => (p.stockQty ?? 0) > 0).toList();
    }

    // Default: trung_bay products only (when no search)
    if (_searchQuery.isEmpty) {
      result = result
          .where((p) => p.attributes['trung_bay']?.toString() == 'true')
          .toList();
    } else {
      // Search: all products matching query
      final q = _searchQuery.toLowerCase();
      result = result.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    return result;
  }

  List<GroupedCategorySection<Product>> _groupedSections({
    required List<Product> products,
    required List<Category> categories,
  }) {
    final activeCategories = categories.where((c) => c.active == 1).toList();
    final visible = _visibleProducts(products);
    final sections = groupItemsByCategory<Product>(
      items: visible,
      categories: activeCategories,
      categoryKeyOf: (product) => product.category,
      itemLabelOf: (product) => product.name,
    );

    return sections;
  }

  void _expandSectionsForSearch(
    List<GroupedCategorySection<Product>> sections,
  ) {
    if (_searchQuery.isEmpty) {
      return;
    }
    for (final section in sections) {
      _sectionExpansionController.setExpanded(section.categoryKey, true);
    }
  }

  void _onSearchChanged(String value) {
    final productsValue = ref.read(productsProvider).value;
    final categoriesValue = ref.read(categoriesProvider).value;

    setState(() => _searchQuery = value);

    if (value.isEmpty || productsValue == null || categoriesValue == null) {
      return;
    }

    final sections = _groupedSections(
      products: productsValue,
      categories: categoriesValue,
    );
    _expandSectionsForSearch(sections);
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

  void _refreshStock() {
    onAutoRefreshTriggered();
  }

  String _refreshLabel() {
    return VN.stockUpdatedAt(formatDisplayTime(_lastStockRefreshAt));
  }

  void _onPosAppBarMenuSelected(String value) {
    switch (value) {
      case 'stock_reconciliation':
        context.push('/stock/reconciliation');
        return;
      case 'stock_reconciliation_history':
        context.push('/stock/reconciliation/history');
        return;
      case 'orders_history':
        context.push('/orders/history');
        return;
      case 'stock':
        context.push('/stock');
        return;
      default:
        assert(() {
          debugPrint('Unknown POS app bar menu action: $value');
          return true;
        }());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.banHang),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: VN.lamMoi,
            onPressed: _refreshStock,
          ),
          AppBarOverflowMenu(
            onSelected: _onPosAppBarMenuSelected,
            items: const [
              PopupMenuItem<String>(
                value: 'stock_reconciliation',
                child: Text(VN.openStockReconciliation),
              ),
              PopupMenuItem<String>(
                value: 'stock_reconciliation_history',
                child: Text(VN.openStockReconciliationHistory),
              ),
              PopupMenuItem<String>(
                value: 'orders_history',
                child: Text(VN.openOrderHistory),
              ),
              PopupMenuItem<String>(value: 'stock', child: Text(VN.openStock)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: VN.searchProducts,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    VN.showOutOfStockProducts,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Switch.adaptive(
                  value: _showOutOfStockProducts,
                  onChanged: (value) {
                    setState(() => _showOutOfStockProducts = value);
                    if (_searchQuery.isEmpty) {
                      return;
                    }
                    final productsValue = ref.read(productsProvider).value;
                    final categoriesValue = ref.read(categoriesProvider).value;
                    if (productsValue == null || categoriesValue == null) {
                      return;
                    }
                    final sections = _groupedSections(
                      products: productsValue,
                      categories: categoriesValue,
                    );
                    _expandSectionsForSearch(sections);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _refreshLabel(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Product grid
          Expanded(
            child: Stack(
              children: [
                categoriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(child: Text(VN.categoryLoadError)),
                        TextButton(
                          onPressed: () => ref.invalidate(categoriesProvider),
                          child: const Text(VN.taiLai),
                        ),
                      ],
                    ),
                  ),
                  data: (categories) => productsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(VN.apiError),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _refreshStock,
                            child: const Text(VN.taiLai),
                          ),
                        ],
                      ),
                    ),
                    data: (products) {
                      final sections = _groupedSections(
                        products: products,
                        categories: categories,
                      );
                      if (sections.isEmpty) {
                        return Center(
                          child: Text(
                            VN.khongCoSanPham,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        );
                      }
                      return CollapsibleCategorySections<Product>(
                        sections: sections,
                        expansionController: _sectionExpansionController,
                        sectionContentBuilder: (context, section) =>
                            PosProductGrid(
                              products: section.items,
                              showOutOfStockProducts: _showOutOfStockProducts,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            ),
                      );
                    },
                  ),
                ),
                // Floating cart bar at bottom
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PosCartBar(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
