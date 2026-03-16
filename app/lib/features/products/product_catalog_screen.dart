import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/product.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/product_card.dart';

/// Ordered list of category keys matching the TabBar tabs.
const _categories = [
  'cake',
  'cupcake',
  'tiramisu_mousse',
  'sandwich',
  'bong_lan_trung_muoi',
];

class ProductCatalogScreen extends ConsumerWidget {
  const ProductCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);

    // Group products by category.
    final grouped = <String, List<Product>>{};
    for (final cat in _categories) {
      grouped[cat] = products.where((p) => p.category == cat).toList();
    }

    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(VN.tabProducts),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _categories.map((cat) {
              final emoji = categoryEmojiMap[cat] ?? '';
              final label = categoryMap[cat] ?? cat;
              return Tab(text: '$emoji $label');
            }).toList(),
          ),
        ),
        body: TabBarView(
          children: _categories.map((cat) {
            final items = grouped[cat] ?? [];
            if (items.isEmpty) {
              return const Center(child: Text('Không có sản phẩm'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  ProductCard(product: items[index]),
            );
          }).toList(),
        ),
      ),
    );
  }
}
