import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
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
    final productsAsync = ref.watch(productsProvider);
    final baseUrl = ref.watch(apiBaseUrlProvider);

    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(VN.tabProducts),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: VN.settings,
              onPressed: () => context.push('/settings'),
            ),
          ],
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
        body: productsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
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
                  onPressed: () => ref.read(productsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(VN.retry),
                ),
              ],
            ),
          ),
          data: (products) => _ProductTabs(
            products: products,
            baseUrl: baseUrl,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/products/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _ProductTabs extends StatelessWidget {
  const _ProductTabs({required this.products, required this.baseUrl});

  final List<Product> products;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Product>>{};
    for (final cat in _categories) {
      grouped[cat] = products.where((p) => p.category == cat).toList();
    }

    return TabBarView(
      children: _categories.map((cat) {
        final items = grouped[cat] ?? [];
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
        return RefreshIndicator(
          onRefresh: () async {
            // This triggers a rebuild from the parent ConsumerWidget
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) => ProductCard(
              product: items[index],
              photoBaseUrl: baseUrl,
              onTap: () =>
                  context.push('/products/${items[index].id}/edit'),
            ),
          ),
        );
      }).toList(),
    );
  }
}
