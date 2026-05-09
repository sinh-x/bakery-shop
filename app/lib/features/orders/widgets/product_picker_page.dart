// ignore_for_file: prefer_const_constructors  // DG-138#todo: replace with per-method suppressions after const audit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/category.dart';
import '../../../data/models/product.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/order_providers.dart';
import '../../../providers/products_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';
import '../../products/widgets/product_card.dart';

class ProductPickerPage extends ConsumerStatefulWidget {
  const ProductPickerPage({
    super.key,
    required this.selectedItems,
    required this.onChanged,
  });

  final List<DraftOrderItem> selectedItems;
  final VoidCallback onChanged;

  @override
  ConsumerState<ProductPickerPage> createState() => _ProductPickerPageState();
}

class _ProductPickerPageState extends ConsumerState<ProductPickerPage> {
  late Set<int> _selectedIds;
  bool _multiSelectMode = false;

  @override
  void initState() {
    super.initState();
    _selectedIds =
        widget.selectedItems.map((i) => i.product.id).toSet();
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
    final alreadyAdded =
        widget.selectedItems.any((i) => i.product.id == product.id);
    if (!alreadyAdded) {
      widget.selectedItems.add(DraftOrderItem(product: product));
    }
    widget.onChanged();
    Navigator.of(context).pop();
  }

  void _enterMultiSelectMode(Product product) {
    setState(() {
      _multiSelectMode = true;
      _selectedIds.add(product.id);
    });
  }

  void _onConfirm(List<Product> allProducts) {
    // Remove items that were deselected
    widget.selectedItems
        .removeWhere((i) => !_selectedIds.contains(i.product.id));

    // Add newly selected products (quantity = 1)
    for (final id in _selectedIds) {
      final alreadyAdded =
          widget.selectedItems.any((i) => i.product.id == id);
      if (!alreadyAdded) {
        final product = allProducts.where((p) => p.id == id).firstOrNull;
        if (product != null) {
          widget.selectedItems.add(DraftOrderItem(product: product));
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
  ) {
    final activeCategories =
        categories.where((c) => c.active == 1).toList();
    final activeProducts =
        allProducts.where((p) => p.active == 1).toList();

    final appBar = _buildAppBar(allProducts, activeCategories);

    if (activeCategories.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: _buildCategoryGrid(activeProducts, baseUrl),
      );
    }

    return DefaultTabController(
      length: activeCategories.length,
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
                      VN.noProducts,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  )
                : _buildCategoryGrid(catProducts, baseUrl);
          }).toList(),
        ),
      ),
    );
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
            : VN.selectProducts,
      ),
      actions: [
        if (_multiSelectMode)
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Xác nhận',
            onPressed: () => _onConfirm(allProducts),
          ),
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

  Widget _buildCategoryGrid(List<Product> products, String baseUrl) {
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
              showPriceBadge: true,
              onTap: _multiSelectMode
                  ? () => _toggleProduct(product)
                  : () => _selectSingleProduct(product),
              onLongPress: _multiSelectMode
                  ? null
                  : () => _enterMultiSelectMode(product),
            ),
            if (selected)
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

    return productsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(VN.selectProducts),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(VN.selectProducts),
        ),
        body: Center(child: Text(VN.apiError)),
      ),
      data: (products) => categoriesAsync.when(
        loading: () => _buildGrid([], products, baseUrl),
        error: (e, _) => _buildGrid([], products, baseUrl),
        data: (categories) => _buildGrid(categories, products, baseUrl),
      ),
    );
  }
}
