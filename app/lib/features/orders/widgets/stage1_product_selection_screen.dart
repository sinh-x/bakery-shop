import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/category.dart';
import '../../../data/models/order_draft.dart';
import '../../../data/models/product.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/order/order_create_state_provider.dart';
import '../../../providers/order_providers.dart';
import '../../../providers/products_provider.dart';
import '../../products/widgets/product_card.dart';
import 'expandable_item_card.dart';
import 'section_header.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class Stage1ProductSelectionScreen extends ConsumerStatefulWidget {
  const Stage1ProductSelectionScreen({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  @override
  ConsumerState<Stage1ProductSelectionScreen> createState() =>
      _Stage1ProductSelectionScreenState();
}

class _Stage1ProductSelectionScreenState
    extends ConsumerState<Stage1ProductSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderCreateStateProvider);
    final items = state.items;
    final regularItems = items.where((i) => !i.isExtra).toList();
    final extraItems = items.where((i) => i.isExtra).toList();
    final total = regularItems.fold<double>(
      0,
      (sum, i) => sum + i.unitPrice * i.quantity,
    );

    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);

    final theme = Theme.of(context);

    return Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(VN.apiError)),
            data: (products) => categoriesAsync.when(
              loading: () => _buildContent(
                items,
                regularItems,
                extraItems,
                total,
                theme,
                products.where((p) => p.active == 1).toList(),
                [],
                baseUrl,
                photoRefreshTick.toString(),
              ),
              error: (e, _) => _buildContent(
                items,
                regularItems,
                extraItems,
                total,
                theme,
                products.where((p) => p.active == 1).toList(),
                [],
                baseUrl,
                photoRefreshTick.toString(),
              ),
              data: (categories) => _buildContent(
                items,
                regularItems,
                extraItems,
                total,
                theme,
                products.where((p) => p.active == 1).toList(),
                categories.where((c) => c.active == 1).toList(),
                baseUrl,
                photoRefreshTick.toString(),
              ),
            ),
          ),
    );
  }

  Widget _buildContent(
    List<DraftOrderItem> items,
    List<DraftOrderItem> regularItems,
    List<DraftOrderItem> extraItems,
    double total,
    ThemeData theme,
    List<Product> products,
    List<Category> categories,
    String baseUrl,
    String cacheBuster,
  ) {
    final selectedIds =
        regularItems.map((i) => i.product.id).toSet();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(VN.selectProducts),
                _ProductGrid(
                  products: products,
                  categories: categories,
                  baseUrl: baseUrl,
                  cacheBuster: cacheBuster,
                  selectedIds: selectedIds,
                  onProductTap: (product) {
                    final alreadyAdded = regularItems.any(
                      (i) => i.product.id == product.id,
                    );
                    if (!alreadyAdded) {
                      ref.read(orderCreateStateProvider.notifier).updateItems([
                        ...regularItems,
                        DraftOrderItem(product: product),
                        ...extraItems,
                      ]);
                    }
                  },
                ),
                if (regularItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionHeader(OrdersLabels.selectedProducts),
                  ...regularItems.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ExpandableItemCard(
                          item: item,
                          onRemove: () {
                            ref
                                .read(orderCreateStateProvider.notifier)
                                .updateItems([
                              ...items.where((i) => i != item),
                            ]);
                          },
                          onQtyChanged: (qty) {
                            item.quantity = qty;
                            ref
                                .read(orderCreateStateProvider.notifier)
                                .updateItems([...items]);
                          },
                          onStateChanged: () {
                            ref
                                .read(orderCreateStateProvider.notifier)
                                .updateItems([...items]);
                          },
                        ),
                      )),
                ],
                if (extraItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionHeader(VN.extras),
                  ...extraItems.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ExpandableItemCard(
                          item: item,
                          onRemove: () {
                            ref
                                .read(orderCreateStateProvider.notifier)
                                .updateItems([
                              ...items.where((i) => i != item),
                            ]);
                          },
                          onQtyChanged: (qty) {
                            item.quantity = qty;
                            ref
                                .read(orderCreateStateProvider.notifier)
                                .updateItems([...items]);
                          },
                          onStateChanged: () {
                            ref
                                .read(orderCreateStateProvider.notifier)
                                .updateItems([...items]);
                          },
                        ),
                      )),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.products,
    required this.categories,
    required this.baseUrl,
    required this.cacheBuster,
    required this.selectedIds,
    required this.onProductTap,
  });

  final List<Product> products;
  final List<Category> categories;
  final String baseUrl;
  final String cacheBuster;
  final Set<int> selectedIds;
  final ValueChanged<Product> onProductTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: categories.isEmpty
          ? _buildGrid(products)
          : Column(
              children: [
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final icon = cat.icon.isNotEmpty
                          ? cat.icon
                          : (categoryEmojiMap[cat.slug] ?? '');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ActionChip(
                          label: Text('$icon ${cat.name}'),
                          onPressed: null,
                        ),
                      );
                    },
                  ),
                ),
                Expanded(child: _buildGrid(products)),
              ],
            ),
    );
  }

  Widget _buildGrid(List<Product> filteredProducts) {
    if (filteredProducts.isEmpty) {
      return Center(
        child: Text(
          VN.noProducts,
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: filteredProducts.length,
      itemBuilder: (_, i) {
        final product = filteredProducts[i];
        final selected = selectedIds.contains(product.id);
        return Stack(
          fit: StackFit.expand,
          children: [
            ProductCard(
              product: product,
              photoBaseUrl: baseUrl,
              cacheBuster: cacheBuster,
              showPriceBadge: true,
              onTap: () => onProductTap(product),
            ),
            if (selected)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.check_circle, color: Colors.white, size: 36),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
