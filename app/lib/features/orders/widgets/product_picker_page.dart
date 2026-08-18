import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show categoryEmojiMap;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../../data/providers/categories_provider.dart';
import '../../../providers/order_providers.dart';
import '../../../data/providers/products_provider.dart';
import '../../../shared/widgets/app_bar_overflow_menu.dart';
import '../../products/widgets/product_card.dart';
import '../utils/trung_bay_inventory_extensions.dart';
import 'category_tab_tracker.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
class ProductPickerPage extends ConsumerStatefulWidget {
  const ProductPickerPage({
    super.key,
    required this.selectedItems,
    required this.onChanged,
    this.initialCategorySlug,
    this.onCategorySelected,
  });

  final List<DraftOrderItem> selectedItems;
  final VoidCallback onChanged;
  final String? initialCategorySlug;
  final void Function(String? slug)? onCategorySelected;

  @override
  ConsumerState<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends ConsumerState<ProductPickerPage> {
  late Set<int> _selectedIds;
  bool _multiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.selectedItems.map((i) => i.product.id).toSet();
  }

  void _toggleProduct(Product product) {
    setState(() {
      if (_selectedIds.contains(product.id)) {
        _selectedIds.remove(product.id);
      } else {
        _selectedIds.add(product.id);
      }
    });
  }

  void _selectSingleProduct(Product product) {
    widget.selectedItems.add(_createDraftItem(product));
    widget.onChanged();
    Navigator.of(context).pop();
  }

  /// Builds a [DraftOrderItem] for a newly picked product. For trưng bày
  /// products the assigned price (COGS anchor) is seeded to the product's
  /// base price; staff may later select a price chip or mark the selling
  /// price upward in [ExpandableItemCard]. Non-trưng bày products keep
  /// `assignedPrice` null so backend COGS falls back to `unitPrice` (FR8).
  /// See DG-296 Phase 4.
  ///
  /// For cake items (`banh_kem` category), `is_birthday` defaults to `true`
  /// so the candle type radio group is immediately visible (DG-340 Phase 4 /
  /// FR6). Staff can still uncheck the birthday checkbox for non-birthday
  /// cake orders; existing drafts are not re-checked because this only runs
  /// at item-creation time (AC6 — existing behavior preserved).
  DraftOrderItem _createDraftItem(Product product) {
    return DraftOrderItem(
      product: product,
      assignedPrice: product.isTrungBay ? product.basePrice : null,
      isBirthday: product.category == 'banh_kem',
    );
  }

  void _enterMultiSelectMode(Product product) {
    setState(() {
      _multiSelectMode = true;
      _selectedIds.add(product.id);
    });
  }

  void _onConfirm(List<Product> allProducts) {
    // Remove items that were deselected
    widget.selectedItems.removeWhere(
      (i) => !_selectedIds.contains(i.product.id),
    );

    // Add newly selected products (quantity = 1)
    for (final id in _selectedIds) {
      final alreadyAdded = widget.selectedItems.any((i) => i.product.id == id);
      if (!alreadyAdded) {
        final product = allProducts.where((p) => p.id == id).firstOrNull;
        if (product != null) {
          widget.selectedItems.add(_createDraftItem(product));
        }
      }
    }

    widget.onChanged();
    Navigator.of(context).pop();
  }

  Widget _buildGrid(
    List<Category> categories,
    List<Product> allProducts,
    String baseUrl,
    String cacheBuster,
  ) {
    final activeCategories = categories.where((c) => c.active == 1).toList();
    final activeProducts = allProducts.where((p) => p.active == 1).toList();

    final appBar = _buildAppBar(allProducts, activeCategories);

    if (activeCategories.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: _buildCategoryGrid(activeProducts, baseUrl, cacheBuster),
      );
    }

    final initialIndex = _initialTabIndex(activeCategories);

    return DefaultTabController(
      initialIndex: initialIndex,
      length: activeCategories.length,
      child: CategoryTabTracker(
        activeCategories: activeCategories,
        onCategorySelected: widget.onCategorySelected,
        child: Scaffold(
          appBar: appBar,
          body: TabBarView(
            children: activeCategories.map((cat) {
              final catProducts = activeProducts
                  .where((p) => p.category == cat.slug)
                  .toList();
              return catProducts.isEmpty
                  ? Center(
                      child: Text(
                        ProductsLabels.noProducts,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    )
                  : _buildCategoryGrid(catProducts, baseUrl, cacheBuster);
            }).toList(),
          ),
        ),
      ),
    );
  }

  int _initialTabIndex(List<Category> activeCategories) {
    final slug = widget.initialCategorySlug;
    if (slug == null) return 0;
    final idx = activeCategories.indexWhere((c) => c.slug == slug);
    return idx >= 0 ? idx : 0;
  }

  PreferredSizeWidget _buildAppBar(
    List<Product> allProducts,
    List<Category> activeCategories,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        _multiSelectMode && _selectedIds.isNotEmpty
            ? '${_selectedIds.length} đã chọn'
            : OrdersLabels.selectProducts,
      ),
      actions: [
        if (_multiSelectMode)
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Xác nhận',
            onPressed: () => _onConfirm(allProducts),
          ),
        const AppBarOverflowMenu(),
      ],
      bottom: activeCategories.isNotEmpty
          ? TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: activeCategories.map((cat) {
                final icon = cat.icon.isNotEmpty
                    ? cat.icon
                    : (categoryEmojiMap[cat.slug] ?? '');
                return Tab(text: '$icon ${cat.name}');
              }).toList(),
            )
          : null,
    );
  }

  Widget _buildCategoryGrid(
    List<Product> products,
    String baseUrl,
    String cacheBuster,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final product = products[i];
        final selected = _selectedIds.contains(product.id);
        return Stack(
          fit: StackFit.expand,
          children: [
            ProductCard(
              product: product,
              photoBaseUrl: baseUrl,
              cacheBuster: cacheBuster,
              showPriceBadge: true,
              onTap: _multiSelectMode
                  ? () => _toggleProduct(product)
                  : () => _selectSingleProduct(product),
              onLongPress: _multiSelectMode
                  ? null
                  : () => _enterMultiSelectMode(product),
            ),
            if (selected && _multiSelectMode)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 52,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);

    return productsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(OrdersLabels.selectProducts),
          actions: const [AppBarOverflowMenu()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(OrdersLabels.selectProducts),
          actions: const [AppBarOverflowMenu()],
        ),
        body: const Center(child: Text(SharedLabels.apiError)),
      ),
      data: (products) => categoriesAsync.when(
        loading: () =>
            _buildGrid([], products, baseUrl, photoRefreshTick.toString()),
        error: (e, _) =>
            _buildGrid([], products, baseUrl, photoRefreshTick.toString()),
        data: (categories) => _buildGrid(
          categories,
          products,
          baseUrl,
          photoRefreshTick.toString(),
        ),
      ),
    );
  }
}
